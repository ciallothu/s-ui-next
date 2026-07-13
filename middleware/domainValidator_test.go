package middleware

import "testing"

func TestNormalizeHostname(t *testing.T) {
	tests := map[string]string{
		"Example.COM:443":       "example.com",
		"panel.example.com.":    "panel.example.com",
		"[2001:db8::1]:8443":    "2001:db8::1",
		"2001:0db8:0:0:0:0:0:1": "2001:db8::1",
	}
	for input, expected := range tests {
		if actual := normalizeHostname(input); actual != expected {
			t.Fatalf("normalizeHostname(%q) = %q, want %q", input, actual, expected)
		}
	}
}
