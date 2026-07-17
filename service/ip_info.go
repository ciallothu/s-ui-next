package service

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sagernet/sing-box/adapter"
)

type cachedIPOwner struct {
	attribution string
	isp         string
	asn         string
	country     string
	region      string
	city        string
	network     string
	geolocated  bool
}

type cachedIPOwnerEntry struct {
	owner     cachedIPOwner
	expiresAt time.Time
}

type cachedDomainResolutionEntry struct {
	addresses []netip.Addr
	expiresAt time.Time
}

const (
	maxIPOwnerCacheEntries        = 4096
	maxDomainResolutionEntries    = 4096
	positiveIPOwnerTTL            = 24 * time.Hour
	negativeIPOwnerTTL            = 5 * time.Minute
	positiveDomainResolutionTTL   = 10 * time.Minute
	connectionOwnerLookupTimeout  = 900 * time.Millisecond
	connectionDetailLookupTimeout = 4 * time.Second
	connectionDNSRouterTimeout    = 700 * time.Millisecond
	connectionOwnerLookupWorkers  = 8
	maxConnectionAddressLength    = 512
	maxIPWhoResponseBytes         = 32 << 10
)

const ipWhoLookupBaseURL = "https://ipwho.is/"

var ipOwnerHTTPClient = &http.Client{Timeout: connectionDetailLookupTimeout}

var ipOwnerCache = struct {
	sync.Mutex
	entries map[string]cachedIPOwnerEntry
}{entries: make(map[string]cachedIPOwnerEntry)}

var domainResolutionCache = struct {
	sync.Mutex
	entries map[string]cachedDomainResolutionEntry
}{entries: make(map[string]cachedDomainResolutionEntry)}

type ConnectionOwnerLookupBudget struct {
	remaining atomic.Int64
}

func NewConnectionOwnerLookupBudget(limit int) *ConnectionOwnerLookupBudget {
	if limit < 0 {
		limit = 0
	}
	budget := &ConnectionOwnerLookupBudget{}
	budget.remaining.Store(int64(limit))
	return budget
}

func (b *ConnectionOwnerLookupBudget) allowLookup() bool {
	if b == nil {
		return true
	}
	for {
		remaining := b.remaining.Load()
		if remaining <= 0 {
			return false
		}
		if b.remaining.CompareAndSwap(remaining, remaining-1) {
			return true
		}
	}
}

func describeConnectionAddress(value string) *ConnectionIPInfo {
	address := strings.TrimSpace(value)
	if address == "" {
		return nil
	}

	host, port := splitConnectionHostPort(address)
	info := &ConnectionIPInfo{
		Address: address,
		Host:    host,
		Port:    port,
	}
	if host == "" {
		return info
	}

	ipHost := strings.Trim(host, "[]")
	if percent := strings.IndexByte(ipHost, '%'); percent >= 0 {
		ipHost = ipHost[:percent]
	}
	addr, err := netip.ParseAddr(ipHost)
	if err != nil {
		info.Scope = "domain"
		info.Attribution = "Domain name"
		return info
	}

	info.IP = addr.String()
	info.Scope = classifyIPScope(addr)
	info.Attribution = scopeAttribution(info.Scope)
	info.ISP = scopeISP(info.Scope)
	return info
}

func enrichConnectionEntryOwners(ctx context.Context, entry *ConnectionEntry, budget *ConnectionOwnerLookupBudget) {
	enrichConnectionIPInfo(ctx, entry.DestinationInfo, budget)
	enrichConnectionIPInfo(ctx, entry.SourceInfo, budget)
	if entry.RemoteInfo != entry.SourceInfo && entry.RemoteInfo != entry.DestinationInfo {
		enrichConnectionIPInfo(ctx, entry.RemoteInfo, budget)
	}
}

func EnrichConnectionEntryOwners(entry *ConnectionEntry) {
	if entry == nil {
		return
	}
	EnrichConnectionEntriesOwners([]*ConnectionEntry{entry}, 8)
}

func EnrichConnectionEntryOwnersWithBudget(entry *ConnectionEntry, budget *ConnectionOwnerLookupBudget) {
	if entry == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), connectionOwnerLookupTimeout)
	defer cancel()
	enrichConnectionEntryOwners(ctx, entry, budget)
}

type connectionInfoTarget struct {
	info    ConnectionIPInfo
	targets []*ConnectionIPInfo
}

type connectionInfoResult struct {
	index int
	info  ConnectionIPInfo
}

// EnrichConnectionEntriesOwners resolves and describes only the requested page.
// Lookups are deduplicated and share one deadline so log APIs remain responsive.
func EnrichConnectionEntriesOwners(entries []*ConnectionEntry, limit int) {
	targets := collectConnectionInfoTargets(entries)
	if len(targets) == 0 {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), connectionOwnerLookupTimeout)
	defer cancel()
	budget := NewConnectionOwnerLookupBudget(limit)
	jobs := make(chan int, len(targets))
	results := make(chan connectionInfoResult, len(targets))
	for index := range targets {
		jobs <- index
	}
	close(jobs)

	workerCount := connectionOwnerLookupWorkers
	if len(targets) < workerCount {
		workerCount = len(targets)
	}
	var workers sync.WaitGroup
	workers.Add(workerCount)
	for range workerCount {
		go func() {
			defer workers.Done()
			for index := range jobs {
				info := targets[index].info
				enrichConnectionIPInfo(ctx, &info, budget)
				results <- connectionInfoResult{index: index, info: info}
			}
		}()
	}
	workers.Wait()
	close(results)

	for result := range results {
		for _, target := range targets[result.index].targets {
			applyConnectionInfo(target, result.info)
		}
	}
}

func collectConnectionInfoTargets(entries []*ConnectionEntry) []connectionInfoTarget {
	targets := make([]connectionInfoTarget, 0)
	indexByKey := make(map[string]int)
	seenPointers := make(map[*ConnectionIPInfo]bool)
	add := func(info *ConnectionIPInfo) {
		if info == nil || seenPointers[info] {
			return
		}
		seenPointers[info] = true
		key := connectionInfoCacheKey(info)
		if key == "" {
			return
		}
		if index, loaded := indexByKey[key]; loaded {
			targets[index].targets = append(targets[index].targets, info)
			return
		}
		indexByKey[key] = len(targets)
		targets = append(targets, connectionInfoTarget{info: *info, targets: []*ConnectionIPInfo{info}})
	}
	for _, entry := range entries {
		if entry == nil {
			continue
		}
		add(entry.DestinationInfo)
	}
	for _, entry := range entries {
		if entry == nil {
			continue
		}
		add(entry.RemoteInfo)
	}
	for _, entry := range entries {
		if entry == nil {
			continue
		}
		add(entry.SourceInfo)
	}
	return targets
}

func connectionInfoCacheKey(info *ConnectionIPInfo) string {
	if info.IP != "" {
		return "ip:" + strings.ToLower(strings.TrimSpace(info.IP))
	}
	if info.Host != "" {
		return "host:" + strings.ToLower(strings.TrimSpace(info.Host))
	}
	address := strings.ToLower(strings.TrimSpace(info.Address))
	if address == "" {
		return ""
	}
	return "address:" + address
}

func applyConnectionInfo(target *ConnectionIPInfo, source ConnectionIPInfo) {
	if target == nil {
		return
	}
	target.IP = source.IP
	target.Scope = source.Scope
	target.Attribution = source.Attribution
	target.ISP = source.ISP
	target.ASN = source.ASN
	target.Country = source.Country
	target.Region = source.Region
	target.City = source.City
	target.Network = source.Network
}

func ResolveConnectionAddress(ctx context.Context, value string) (*ConnectionIPInfo, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, fmt.Errorf("address is required")
	}
	if len(value) > maxConnectionAddressLength {
		return nil, fmt.Errorf("address is too long")
	}
	info := describeConnectionAddress(value)
	if info == nil || info.Host == "" {
		return nil, fmt.Errorf("invalid address")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	lookupCtx, cancel := context.WithTimeout(ctx, connectionDetailLookupTimeout)
	defer cancel()
	enrichConnectionIPInfo(lookupCtx, info, nil)
	return info, nil
}

func enrichConnectionIPInfo(ctx context.Context, info *ConnectionIPInfo, budget *ConnectionOwnerLookupBudget) {
	if info == nil {
		return
	}
	lookupAllowed := false
	allowLookup := func() bool {
		if lookupAllowed {
			return true
		}
		lookupAllowed = budget.allowLookup()
		return lookupAllowed
	}

	if info.IP == "" && info.Scope == "domain" && info.Host != "" {
		addresses, loaded := loadCachedDomainResolution(info.Host)
		if !loaded {
			if !allowLookup() {
				return
			}
			var err error
			addresses, err = lookupConnectionDomain(ctx, info.Host)
			if err != nil || len(addresses) == 0 {
				return
			}
			storeCachedDomainResolution(info.Host, addresses)
		}
		resolved, loaded := selectConnectionAddress(addresses)
		if !loaded {
			return
		}
		info.IP = resolved.String()
		info.Scope = classifyIPScope(resolved)
		info.Attribution = scopeAttribution(info.Scope)
		info.ISP = scopeISP(info.Scope)
	}

	if info.IP == "" {
		return
	}
	addr, err := netip.ParseAddr(info.IP)
	if err != nil {
		return
	}
	if info.Scope == "" || info.Scope == "domain" {
		info.Scope = classifyIPScope(addr)
		info.Attribution = scopeAttribution(info.Scope)
		info.ISP = scopeISP(info.Scope)
	}
	if info.Scope != "public" || info.ASN != "" || info.ISP != "" {
		return
	}
	requireGeolocation := budget == nil
	if owner, hit, ok := cachedPublicIPOwner(info.IP); hit && (!requireGeolocation || (ok && owner.geolocated)) {
		if ok {
			applyIPOwner(info, owner)
		}
		return
	}
	if !allowLookup() {
		return
	}
	if owner, ok := lookupPublicIPOwner(ctx, addr, requireGeolocation); ok {
		applyIPOwner(info, owner)
	}
}

func lookupConnectionDomain(ctx context.Context, host string) ([]netip.Addr, error) {
	if corePtr != nil && corePtr.IsRunning() {
		instance := corePtr.GetInstance()
		if instance != nil && instance.DNSRouter() != nil {
			routerCtx, cancel := context.WithTimeout(ctx, connectionDNSRouterTimeout)
			addresses, err := instance.DNSRouter().Lookup(routerCtx, host, adapter.DNSQueryOptions{})
			cancel()
			if err == nil && len(addresses) > 0 {
				return addresses, nil
			}
		}
	}
	return net.DefaultResolver.LookupNetIP(ctx, "ip", host)
}

func selectConnectionAddress(addresses []netip.Addr) (netip.Addr, bool) {
	for _, address := range addresses {
		if address.IsValid() && classifyIPScope(address) == "public" {
			return address, true
		}
	}
	for _, address := range addresses {
		if address.IsValid() {
			return address, true
		}
	}
	return netip.Addr{}, false
}

func loadCachedDomainResolution(host string) ([]netip.Addr, bool) {
	key := strings.ToLower(strings.TrimSpace(host))
	now := time.Now()
	domainResolutionCache.Lock()
	defer domainResolutionCache.Unlock()
	entry, loaded := domainResolutionCache.entries[key]
	if !loaded {
		return nil, false
	}
	if !now.Before(entry.expiresAt) {
		delete(domainResolutionCache.entries, key)
		return nil, false
	}
	return append([]netip.Addr(nil), entry.addresses...), true
}

func storeCachedDomainResolution(host string, addresses []netip.Addr) {
	key := strings.ToLower(strings.TrimSpace(host))
	if key == "" || len(addresses) == 0 {
		return
	}
	now := time.Now()
	domainResolutionCache.Lock()
	defer domainResolutionCache.Unlock()
	if len(domainResolutionCache.entries) >= maxDomainResolutionEntries {
		for cachedHost, entry := range domainResolutionCache.entries {
			if !now.Before(entry.expiresAt) {
				delete(domainResolutionCache.entries, cachedHost)
			}
		}
	}
	if len(domainResolutionCache.entries) >= maxDomainResolutionEntries {
		for cachedHost := range domainResolutionCache.entries {
			delete(domainResolutionCache.entries, cachedHost)
			break
		}
	}
	domainResolutionCache.entries[key] = cachedDomainResolutionEntry{
		addresses: append([]netip.Addr(nil), addresses...),
		expiresAt: now.Add(positiveDomainResolutionTTL),
	}
}

func clearConnectionDomainResolutionCache() {
	domainResolutionCache.Lock()
	domainResolutionCache.entries = make(map[string]cachedDomainResolutionEntry)
	domainResolutionCache.Unlock()
}

func cachedPublicIPOwner(ip string) (cachedIPOwner, bool, bool) {
	return loadCachedIPOwner(ip)
}

func applyIPOwner(info *ConnectionIPInfo, owner cachedIPOwner) {
	info.ASN = owner.asn
	info.Country = owner.country
	info.Region = owner.region
	info.City = owner.city
	info.Network = owner.network
	info.Attribution = owner.attribution
	info.ISP = owner.isp
}

func splitConnectionHostPort(value string) (string, string) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", ""
	}
	if host, port, err := net.SplitHostPort(value); err == nil {
		return strings.Trim(host, "[]"), port
	}
	if parsed, err := url.Parse("//" + value); err == nil && parsed.Hostname() != "" {
		return parsed.Hostname(), parsed.Port()
	}
	if strings.Count(value, ":") == 1 {
		parts := strings.SplitN(value, ":", 2)
		return strings.Trim(parts[0], "[]"), parts[1]
	}
	return strings.Trim(value, "[]"), ""
}

func classifyIPScope(addr netip.Addr) string {
	switch {
	case addr.IsUnspecified():
		return "unspecified"
	case addr.IsLoopback():
		return "loopback"
	case addr.IsPrivate():
		return "private"
	case addr.IsLinkLocalUnicast():
		return "link_local"
	case addr.IsMulticast():
		return "multicast"
	case addr.IsGlobalUnicast():
		return "public"
	default:
		return "reserved"
	}
}

func scopeAttribution(scope string) string {
	switch scope {
	case "domain":
		return "Domain name"
	case "private":
		return "Private network"
	case "loopback":
		return "Loopback"
	case "link_local":
		return "Link-local network"
	case "multicast":
		return "Multicast"
	case "unspecified":
		return "Unspecified address"
	case "reserved":
		return "Reserved address"
	case "public":
		return "Public Internet"
	default:
		return ""
	}
}

func scopeISP(scope string) string {
	switch scope {
	case "private":
		return "Private network"
	case "loopback":
		return "Local host"
	case "link_local":
		return "Local link"
	case "multicast":
		return "Multicast"
	case "reserved", "unspecified":
		return "Reserved"
	default:
		return ""
	}
}

func loadCachedIPOwner(key string) (cachedIPOwner, bool, bool) {
	now := time.Now()
	ipOwnerCache.Lock()
	defer ipOwnerCache.Unlock()
	entry, ok := ipOwnerCache.entries[key]
	if !ok {
		return cachedIPOwner{}, false, false
	}
	if !now.Before(entry.expiresAt) {
		delete(ipOwnerCache.entries, key)
		return cachedIPOwner{}, false, false
	}
	owner := entry.owner
	return owner, true, owner.attribution != "" || owner.isp != "" || owner.asn != ""
}

func storeCachedIPOwner(key string, owner cachedIPOwner, ttl time.Duration) {
	now := time.Now()
	ipOwnerCache.Lock()
	defer ipOwnerCache.Unlock()
	if len(ipOwnerCache.entries) >= maxIPOwnerCacheEntries {
		for cachedKey, entry := range ipOwnerCache.entries {
			if !now.Before(entry.expiresAt) {
				delete(ipOwnerCache.entries, cachedKey)
			}
		}
	}
	if len(ipOwnerCache.entries) >= maxIPOwnerCacheEntries {
		for cachedKey := range ipOwnerCache.entries {
			delete(ipOwnerCache.entries, cachedKey)
			break
		}
	}
	ipOwnerCache.entries[key] = cachedIPOwnerEntry{owner: owner, expiresAt: now.Add(ttl)}
}

func lookupPublicIPOwner(ctx context.Context, addr netip.Addr, requireGeolocation bool) (cachedIPOwner, bool) {
	key := addr.String()
	if owner, hit, ok := loadCachedIPOwner(key); hit && (!requireGeolocation || (ok && owner.geolocated)) {
		return owner, ok
	}

	owner, ok := queryIPWhoOwner(ctx, addr)
	if !ok && ctx.Err() == nil {
		owner, ok = queryCymruOwner(ctx, addr)
	}
	if !ok {
		if ctx.Err() == nil {
			storeCachedIPOwner(key, cachedIPOwner{}, negativeIPOwnerTTL)
		}
		return cachedIPOwner{}, false
	}
	storeCachedIPOwner(key, owner, positiveIPOwnerTTL)
	return owner, true
}

type ipWhoResponse struct {
	IP          string `json:"ip"`
	Success     bool   `json:"success"`
	Country     string `json:"country"`
	CountryCode string `json:"country_code"`
	Region      string `json:"region"`
	City        string `json:"city"`
	Connection  struct {
		ASN int64  `json:"asn"`
		Org string `json:"org"`
		ISP string `json:"isp"`
	} `json:"connection"`
}

func queryIPWhoOwner(ctx context.Context, addr netip.Addr) (cachedIPOwner, bool) {
	requestURL := ipWhoLookupBaseURL + url.PathEscape(addr.String()) + "?fields=success,ip,country,country_code,region,city,connection"
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL, nil)
	if err != nil {
		return cachedIPOwner{}, false
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("User-Agent", "s-ui-next")
	response, err := ipOwnerHTTPClient.Do(request)
	if err != nil {
		return cachedIPOwner{}, false
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return cachedIPOwner{}, false
	}

	body, err := io.ReadAll(io.LimitReader(response.Body, maxIPWhoResponseBytes+1))
	if err != nil || len(body) > maxIPWhoResponseBytes {
		return cachedIPOwner{}, false
	}
	return parseIPWhoOwner(body, addr)
}

func parseIPWhoOwner(body []byte, addr netip.Addr) (cachedIPOwner, bool) {
	var payload ipWhoResponse
	if json.Unmarshal(body, &payload) != nil || !payload.Success {
		return cachedIPOwner{}, false
	}
	returnedIP, err := netip.ParseAddr(strings.TrimSpace(payload.IP))
	if err != nil || returnedIP.Unmap() != addr.Unmap() {
		return cachedIPOwner{}, false
	}

	owner := cachedIPOwner{
		isp:        firstNonEmptyString(payload.Connection.Org, payload.Connection.ISP),
		country:    firstNonEmptyString(payload.CountryCode, payload.Country),
		region:     strings.TrimSpace(payload.Region),
		city:       strings.TrimSpace(payload.City),
		geolocated: true,
	}
	if payload.Connection.ASN > 0 {
		owner.asn = strconv.FormatInt(payload.Connection.ASN, 10)
	}
	owner.attribution = formatIPOwnerAttribution(owner)
	if owner.attribution == "" && owner.asn == "" {
		return cachedIPOwner{}, false
	}
	return owner, true
}

func formatIPOwnerAttribution(owner cachedIPOwner) string {
	parts := make([]string, 0, 2)
	if owner.isp != "" {
		parts = append(parts, owner.isp)
	} else if owner.asn != "" {
		parts = append(parts, "AS"+owner.asn)
	}
	location := firstNonEmptyString(owner.city, owner.region, owner.country)
	if location != "" {
		parts = append(parts, location)
	}
	return strings.Join(parts, " · ")
}

func firstNonEmptyString(values ...string) string {
	for _, value := range values {
		if value = strings.TrimSpace(value); value != "" {
			return value
		}
	}
	return ""
}

func queryCymruOwner(ctx context.Context, addr netip.Addr) (cachedIPOwner, bool) {
	resolver := net.DefaultResolver
	txts, err := resolver.LookupTXT(ctx, cymruOriginName(addr))
	if err != nil || len(txts) == 0 {
		return cachedIPOwner{}, false
	}
	fields := splitCymruFields(txts[0])
	if len(fields) < 5 || fields[0] == "" {
		return cachedIPOwner{}, false
	}

	owner := cachedIPOwner{
		asn:     fields[0],
		network: fields[1],
		country: fields[2],
	}

	name := lookupASNName(ctx, resolver, owner.asn)
	if name != "" {
		owner.isp = name
		owner.attribution = fmt.Sprintf("AS%s · %s", owner.asn, name)
	} else {
		owner.attribution = "AS" + owner.asn
	}
	if owner.country != "" {
		if owner.attribution != "" {
			owner.attribution += " · " + owner.country
		} else {
			owner.attribution = owner.country
		}
	}
	return owner, true
}

func lookupASNName(ctx context.Context, resolver *net.Resolver, asn string) string {
	asn = strings.TrimSpace(asn)
	if asn == "" {
		return ""
	}
	txts, err := resolver.LookupTXT(ctx, "AS"+asn+".asn.cymru.com")
	if err != nil || len(txts) == 0 {
		return ""
	}
	fields := splitCymruFields(txts[0])
	if len(fields) < 5 {
		return ""
	}
	return fields[4]
}

func splitCymruFields(value string) []string {
	raw := strings.Split(value, "|")
	fields := make([]string, 0, len(raw))
	for _, field := range raw {
		fields = append(fields, strings.TrimSpace(field))
	}
	return fields
}

func cymruOriginName(addr netip.Addr) string {
	if addr.Is4() {
		ip := addr.As4()
		return fmt.Sprintf("%d.%d.%d.%d.origin.asn.cymru.com", ip[3], ip[2], ip[1], ip[0])
	}

	ip := addr.As16()
	parts := make([]string, 0, 32)
	for index := len(ip) - 1; index >= 0; index-- {
		parts = append(parts, fmt.Sprintf("%x", ip[index]&0x0f), fmt.Sprintf("%x", ip[index]>>4))
	}
	return strings.Join(parts, ".") + ".origin6.asn.cymru.com"
}
