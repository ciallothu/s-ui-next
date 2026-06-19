package service

import (
	"net"
	"net/url"
	"regexp"
	"sort"
	"strings"

	"github.com/alireza0/s-ui/logger"
)

type ConnectionFilter struct {
	Resource string
	Tag      string
	User     string
	Search   string
	Start    int64
	End      int64
	Offset   int
	Limit    int
}

type ConnectionEntry struct {
	Timestamp   int64  `json:"timestamp"`
	Time        string `json:"time"`
	Resource    string `json:"resource"`
	Protocol    string `json:"protocol"`
	Tag         string `json:"tag"`
	User        string `json:"user,omitempty"`
	Event       string `json:"event"`
	Remote      string `json:"remote,omitempty"`
	Destination string `json:"destination,omitempty"`
	Source      string `json:"source,omitempty"`
	Message     string `json:"message"`
}

type ConnectionSummary struct {
	Resource string   `json:"resource"`
	Tag      string   `json:"tag"`
	Count    int      `json:"count"`
	LastSeen int64    `json:"lastSeen"`
	Users    []string `json:"users,omitempty"`
}

type ConnectionQueryResult struct {
	Items   []ConnectionEntry              `json:"items"`
	Total   int                            `json:"total"`
	Offset  int                            `json:"offset"`
	Limit   int                            `json:"limit"`
	Summary map[string][]ConnectionSummary `json:"summary"`
	Parsed  int                            `json:"parsed"`
	Scanned int                            `json:"scanned"`
}

var (
	connectionPrefixPattern = regexp.MustCompile(`^(inbound|outbound|endpoint)/([^\[]+)\[([^\]]+)\](?:\[([^\]]+)\])?\s*(.*)$`)
	connectionToPattern     = regexp.MustCompile(`\bconnection\s+to\s+([^,\s]+)`)
	connectionFromPattern   = regexp.MustCompile(`\bconnection\s+from\s+([^,\s]+)`)
)

func parseConnectionLog(entry logger.LogEntry) (ConnectionEntry, bool) {
	message := strings.TrimSpace(entry.Message)
	matches := connectionPrefixPattern.FindStringSubmatch(message)
	if len(matches) == 0 {
		return ConnectionEntry{}, false
	}
	detail := strings.TrimSpace(matches[5])
	result := ConnectionEntry{
		Timestamp: entry.Timestamp,
		Time:      entry.Time,
		Resource:  matches[1],
		Protocol:  matches[2],
		Tag:       matches[3],
		User:      strings.TrimSpace(matches[4]),
		Event:     detail,
		Message:   message,
	}
	if to := connectionToPattern.FindStringSubmatch(detail); len(to) > 1 {
		result.Destination = strings.TrimSpace(to[1])
		result.Remote = result.Destination
	}
	if from := connectionFromPattern.FindStringSubmatch(detail); len(from) > 1 {
		result.Source = strings.TrimSpace(from[1])
		if result.Remote == "" {
			result.Remote = result.Source
		}
	}
	return result, true
}

func (s *StatsService) QueryConnections(filter ConnectionFilter) (*ConnectionQueryResult, error) {
	filter.Offset, filter.Limit = normalizePage(filter.Offset, filter.Limit, 2000)
	logs, scanned := logger.QueryLogs(logger.LogQuery{
		Level: "INFO", User: filter.User, Search: filter.Search,
		Start: filter.Start, End: filter.End, Limit: 5000,
	})

	items := make([]ConnectionEntry, 0, len(logs))
	for _, logEntry := range logs {
		item, ok := parseConnectionLog(logEntry)
		if !ok || !connectionMatches(item, filter) {
			continue
		}
		items = append(items, item)
	}
	sort.SliceStable(items, func(i, j int) bool { return items[i].Timestamp > items[j].Timestamp })
	total := len(items)
	pageEnd := filter.Offset + filter.Limit
	if pageEnd > total {
		pageEnd = total
	}
	page := []ConnectionEntry{}
	if filter.Offset < total {
		page = items[filter.Offset:pageEnd]
	}
	return &ConnectionQueryResult{
		Items: page, Total: total, Offset: filter.Offset, Limit: filter.Limit,
		Summary: summarizeConnections(items), Parsed: len(items), Scanned: scanned,
	}, nil
}

func connectionMatches(item ConnectionEntry, filter ConnectionFilter) bool {
	resource := strings.ToLower(strings.TrimSpace(filter.Resource))
	tag := strings.TrimSpace(filter.Tag)
	user := strings.TrimSpace(filter.User)
	search := strings.ToLower(strings.TrimSpace(filter.Search))

	if user != "" && !strings.EqualFold(item.User, user) && !strings.Contains(strings.ToLower(item.Message), strings.ToLower(user)) {
		return false
	}
	switch resource {
	case "", "all":
	case "user":
		if tag != "" && !strings.EqualFold(item.User, tag) {
			return false
		}
	case "inbound", "outbound", "endpoint", "node":
		if resource == "node" {
			resource = "endpoint"
		}
		if item.Resource != resource {
			return false
		}
		if tag != "" && item.Tag != tag {
			return false
		}
	case "destination", "remote":
		if tag != "" && item.Remote != tag && item.Destination != tag && item.Source != tag {
			return false
		}
	default:
		if tag != "" && item.Tag != tag {
			return false
		}
	}
	if search == "" {
		return true
	}
	haystack := strings.ToLower(strings.Join([]string{
		item.Resource, item.Protocol, item.Tag, item.User, item.Event, item.Remote, item.Destination, item.Source, item.Message,
	}, " "))
	return strings.Contains(haystack, search)
}

func summarizeConnections(items []ConnectionEntry) map[string][]ConnectionSummary {
	type bucket struct {
		ConnectionSummary
		userSet map[string]bool
	}
	maps := map[string]map[string]*bucket{
		"users":        {},
		"inbounds":     {},
		"outbounds":    {},
		"endpoints":    {},
		"destinations": {},
	}
	add := func(kind, resource, tag, user string, timestamp int64) {
		tag = strings.TrimSpace(tag)
		if tag == "" {
			return
		}
		key := resource + "\x00" + tag
		item := maps[kind][key]
		if item == nil {
			item = &bucket{ConnectionSummary: ConnectionSummary{Resource: resource, Tag: tag}, userSet: map[string]bool{}}
			maps[kind][key] = item
		}
		item.Count++
		if timestamp > item.LastSeen {
			item.LastSeen = timestamp
		}
		if user != "" {
			item.userSet[user] = true
		}
	}
	for _, item := range items {
		add(item.Resource+"s", item.Resource, item.Tag, item.User, item.Timestamp)
		if item.User != "" {
			add("users", "user", item.User, item.User, item.Timestamp)
		}
		if item.Remote != "" {
			add("destinations", "destination", normalizeRemote(item.Remote), item.User, item.Timestamp)
		}
	}
	result := make(map[string][]ConnectionSummary, len(maps))
	for kind, source := range maps {
		values := make([]ConnectionSummary, 0, len(source))
		for _, item := range source {
			for user := range item.userSet {
				item.Users = append(item.Users, user)
			}
			sort.Strings(item.Users)
			values = append(values, item.ConnectionSummary)
		}
		sort.SliceStable(values, func(i, j int) bool {
			if values[i].Count == values[j].Count {
				return values[i].Tag < values[j].Tag
			}
			return values[i].Count > values[j].Count
		})
		if len(values) > 100 {
			values = values[:100]
		}
		result[kind] = values
	}
	return result
}

func normalizeRemote(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return value
	}
	if host, _, err := net.SplitHostPort(value); err == nil {
		return host
	}
	if parsed, err := url.Parse("//" + value); err == nil && parsed.Hostname() != "" {
		return parsed.Hostname()
	}
	return value
}
