package sub

import (
	"testing"

	"gopkg.in/yaml.v3"
)

func TestConvertToClashMetaHandlesIncompleteOptionalFields(t *testing.T) {
	outbounds := []map[string]interface{}{
		{
			"tag":         "test",
			"type":        "vless",
			"server":      "example.com",
			"server_port": float64(443),
			"uuid":        "00000000-0000-0000-0000-000000000000",
			"tls": map[string]interface{}{
				"enabled": true,
				"reality": map[string]interface{}{},
				"ech": map[string]interface{}{
					"enabled": true,
					"config":  []interface{}{},
				},
			},
			"transport": map[string]interface{}{
				"type": "http",
				"path": []interface{}{},
				"host": []interface{}{},
			},
		},
	}
	result, err := (&ClashService{}).ConvertToClashMeta(&outbounds, basicClashConfig)
	if err != nil {
		t.Fatal(err)
	}
	var parsed map[string]interface{}
	if err := yaml.Unmarshal([]byte(result), &parsed); err != nil {
		t.Fatalf("generated Clash configuration is invalid: %v", err)
	}
}

func TestConvertToClashMetaRejectsMalformedBaseConfig(t *testing.T) {
	outbounds := []map[string]interface{}{}
	if _, err := (&ClashService{}).ConvertToClashMeta(&outbounds, "["); err == nil {
		t.Fatal("malformed Clash base configuration should be rejected")
	}
}
