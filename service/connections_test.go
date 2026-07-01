package service

import (
	"testing"

	"github.com/ciallothu/s-ui-next/logger"
)

func TestParseConnectionLogExamples(t *testing.T) {
	tests := []struct {
		message     string
		resource    string
		protocol    string
		tag         string
		user        string
		remote      string
		destination string
		source      string
	}{
		{
			message:  "outbound/direct[direct]outbound connection to 149.154.175.211:443",
			resource: "outbound", protocol: "direct", tag: "direct",
			remote: "149.154.175.211:443", destination: "149.154.175.211:443",
		},
		{
			message:  "inbound/vless[vless-443][刘晓辰] inbound connection to 149.154.175.211:443",
			resource: "inbound", protocol: "vless", tag: "vless-443", user: "刘晓辰",
			remote: "149.154.175.211:443", destination: "149.154.175.211:443",
		},
		{
			message:  "inbound/vless[vless-443]inbound connection from 166.111.232.125:61748",
			resource: "inbound", protocol: "vless", tag: "vless-443",
			source: "166.111.232.125:61748",
		},
		{
			message:  "endpoint/wireguard[office] endpoint connection to 10.0.0.2:443",
			resource: "endpoint", protocol: "wireguard", tag: "office",
			remote: "10.0.0.2:443", destination: "10.0.0.2:443",
		},
	}

	for _, test := range tests {
		entry, ok := parseConnectionLog(logger.LogEntry{Timestamp: 1, Time: "2026/06/18 23:03:09", Message: test.message})
		if !ok {
			t.Fatalf("message was not parsed: %q", test.message)
		}
		if entry.Resource != test.resource || entry.Protocol != test.protocol || entry.Tag != test.tag || entry.User != test.user || entry.Remote != test.remote || entry.Destination != test.destination || entry.Source != test.source {
			t.Fatalf("unexpected parse result for %q: %#v", test.message, entry)
		}
	}
}

func TestAttachConnectionSources(t *testing.T) {
	items := []ConnectionEntry{
		{
			Timestamp:   100,
			Resource:    "inbound",
			Protocol:    "vless",
			Tag:         "vless-443",
			User:        "刘晓辰",
			Destination: "www.gstatic.com:80",
		},
		{
			Timestamp: 101,
			Resource:  "inbound",
			Protocol:  "vless",
			Tag:       "vless-443",
			Source:    "166.111.232.125:61748",
			SourceInfo: &ConnectionIPInfo{
				Address: "166.111.232.125:61748",
				Host:    "166.111.232.125",
				Port:    "61748",
				IP:      "166.111.232.125",
			},
		},
	}

	AttachConnectionSources(items)
	if items[0].Source != "166.111.232.125:61748" || items[0].SourceInfo == nil || items[0].SourceInfo.IP != "166.111.232.125" {
		t.Fatalf("source was not attached to user connection: %#v", items[0])
	}
}

func TestConnectionIPInfo(t *testing.T) {
	entry, ok := parseConnectionLog(logger.LogEntry{Timestamp: 1, Time: "2026/06/18 23:03:09", Message: "inbound/vless[vless-443]inbound connection from 10.0.0.2:61748"})
	if !ok {
		t.Fatalf("message was not parsed")
	}
	if entry.SourceInfo == nil || entry.SourceInfo.IP != "10.0.0.2" || entry.SourceInfo.Scope != "private" || entry.SourceInfo.Port != "61748" {
		t.Fatalf("source info missing: %#v", entry.SourceInfo)
	}
}

func TestConnectionSummaryIncludesEndpoints(t *testing.T) {
	summary := summarizeConnections([]ConnectionEntry{
		{Resource: "endpoint", Tag: "office", User: "alice", Destination: "10.0.0.2:443", Timestamp: 100},
		{Resource: "inbound", Protocol: "vless", Tag: "vless-443", Source: "166.111.232.125:61748", Timestamp: 101},
	})
	if len(summary["endpoints"]) != 1 || summary["endpoints"][0].Tag != "office" {
		t.Fatalf("endpoint summary missing: %#v", summary)
	}
	if len(summary["destinations"]) != 1 || summary["destinations"][0].Tag != "10.0.0.2" {
		t.Fatalf("destination summary should only include targets: %#v", summary)
	}
}
