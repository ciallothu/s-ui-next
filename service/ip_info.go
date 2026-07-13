package service

import (
	"context"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strings"
	"sync"
	"time"
)

type cachedIPOwner struct {
	attribution string
	isp         string
	asn         string
	country     string
	network     string
}

type cachedIPOwnerEntry struct {
	owner     cachedIPOwner
	expiresAt time.Time
}

const (
	maxIPOwnerCacheEntries = 4096
	positiveIPOwnerTTL     = 24 * time.Hour
	negativeIPOwnerTTL     = 5 * time.Minute
)

var ipOwnerCache = struct {
	sync.Mutex
	entries map[string]cachedIPOwnerEntry
}{entries: make(map[string]cachedIPOwnerEntry)}

type ConnectionOwnerLookupBudget struct {
	remaining int
}

func NewConnectionOwnerLookupBudget(limit int) *ConnectionOwnerLookupBudget {
	if limit < 0 {
		limit = 0
	}
	return &ConnectionOwnerLookupBudget{remaining: limit}
}

func (b *ConnectionOwnerLookupBudget) allowLookup() bool {
	if b == nil {
		return true
	}
	if b.remaining <= 0 {
		return false
	}
	b.remaining--
	return true
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

func enrichConnectionEntryOwners(entry *ConnectionEntry, budget *ConnectionOwnerLookupBudget) {
	enrichConnectionIPInfo(entry.SourceInfo, budget)
	enrichConnectionIPInfo(entry.DestinationInfo, budget)
	if entry.RemoteInfo != entry.SourceInfo && entry.RemoteInfo != entry.DestinationInfo {
		enrichConnectionIPInfo(entry.RemoteInfo, budget)
	}
}

func EnrichConnectionEntryOwners(entry *ConnectionEntry) {
	if entry == nil {
		return
	}
	enrichConnectionEntryOwners(entry, NewConnectionOwnerLookupBudget(8))
}

func EnrichConnectionEntryOwnersWithBudget(entry *ConnectionEntry, budget *ConnectionOwnerLookupBudget) {
	if entry == nil {
		return
	}
	enrichConnectionEntryOwners(entry, budget)
}

func enrichConnectionIPInfo(info *ConnectionIPInfo, budget *ConnectionOwnerLookupBudget) {
	if info == nil || info.Scope != "public" || info.IP == "" {
		return
	}
	if info.ASN != "" || info.ISP != "" {
		return
	}
	if owner, hit, ok := cachedPublicIPOwner(info.IP); hit {
		if ok {
			applyIPOwner(info, owner)
		}
		return
	}
	if !budget.allowLookup() {
		return
	}
	addr, err := netip.ParseAddr(info.IP)
	if err != nil {
		return
	}
	if owner, ok := lookupPublicIPOwner(addr); ok {
		applyIPOwner(info, owner)
	}
}

func cachedPublicIPOwner(ip string) (cachedIPOwner, bool, bool) {
	return loadCachedIPOwner(ip)
}

func applyIPOwner(info *ConnectionIPInfo, owner cachedIPOwner) {
	info.ASN = owner.asn
	info.Country = owner.country
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

func lookupPublicIPOwner(addr netip.Addr) (cachedIPOwner, bool) {
	key := addr.String()
	if owner, hit, ok := loadCachedIPOwner(key); hit {
		return owner, ok
	}

	owner, ok := queryCymruOwner(addr)
	if !ok {
		storeCachedIPOwner(key, cachedIPOwner{}, negativeIPOwnerTTL)
		return cachedIPOwner{}, false
	}
	storeCachedIPOwner(key, owner, positiveIPOwnerTTL)
	return owner, true
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

func queryCymruOwner(addr netip.Addr) (cachedIPOwner, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 900*time.Millisecond)
	defer cancel()

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
