package service

import (
	"encoding/hex"
	"strings"
	"testing"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
)

func TestResolvePasskeyNameUsesAAGUIDBeforePlatformFallback(t *testing.T) {
	credential := &webauthn.Credential{
		Authenticator: webauthn.Authenticator{
			AAGUID:     decodeAAGUID(t, "d548826e-79b4-db40-a3d8-11116f7e8349"),
			Attachment: protocol.Platform,
		},
		Transport: []protocol.AuthenticatorTransport{protocol.Internal},
	}

	name, err := resolvePasskeyName(credential, "", "windows")
	if err != nil {
		t.Fatal(err)
	}
	if name != "Bitwarden" {
		t.Fatalf("expected Bitwarden, got %q", name)
	}
}

func TestResolvePasskeyNameFallsBackToPlatformAndTransport(t *testing.T) {
	tests := []struct {
		name       string
		credential *webauthn.Credential
		platform   string
		want       string
	}{
		{
			name: "windows platform authenticator",
			credential: &webauthn.Credential{
				Authenticator: webauthn.Authenticator{Attachment: protocol.Platform},
				Transport:     []protocol.AuthenticatorTransport{protocol.Internal},
			},
			platform: "windows",
			want:     "Windows Hello",
		},
		{
			name: "roaming security key",
			credential: &webauthn.Credential{
				Authenticator: webauthn.Authenticator{Attachment: protocol.CrossPlatform},
				Transport:     []protocol.AuthenticatorTransport{protocol.USB},
			},
			platform: "macos",
			want:     "Security key",
		},
		{
			name: "hybrid phone",
			credential: &webauthn.Credential{
				Authenticator: webauthn.Authenticator{Attachment: protocol.CrossPlatform},
				Transport:     []protocol.AuthenticatorTransport{protocol.Hybrid},
			},
			platform: "linux",
			want:     "Phone or tablet",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			name, err := resolvePasskeyName(test.credential, "", test.platform)
			if err != nil {
				t.Fatal(err)
			}
			if name != test.want {
				t.Fatalf("expected %q, got %q", test.want, name)
			}
		})
	}
}

func TestResolvePasskeyNamePreservesValidCustomName(t *testing.T) {
	name, err := resolvePasskeyName(&webauthn.Credential{}, "  Work laptop  ", "windows")
	if err != nil {
		t.Fatal(err)
	}
	if name != "Work laptop" {
		t.Fatalf("expected trimmed custom name, got %q", name)
	}

	if _, err := resolvePasskeyName(&webauthn.Credential{}, strings.Repeat("x", maxPasskeyNameRunes+1), ""); err == nil {
		t.Fatal("expected an overlong passkey name to be rejected")
	}
}

func decodeAAGUID(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := hex.DecodeString(strings.ReplaceAll(value, "-", ""))
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}
