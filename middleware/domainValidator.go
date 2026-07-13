package middleware

import (
	"net"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

func DomainValidator(domain string) gin.HandlerFunc {
	expectedHost := normalizeHostname(domain)
	return func(c *gin.Context) {
		if expectedHost == "" || normalizeHostname(c.Request.Host) != expectedHost {
			c.AbortWithStatus(http.StatusForbidden)
			return
		}

		c.Next()
	}
}

func normalizeHostname(value string) string {
	value = strings.TrimSpace(value)
	if host, _, err := net.SplitHostPort(value); err == nil {
		value = host
	}
	value = strings.TrimSuffix(strings.Trim(strings.TrimSpace(value), "[]"), ".")
	if ip := net.ParseIP(value); ip != nil {
		return ip.String()
	}
	return strings.ToLower(value)
}
