package api

import (
	"net"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	loginFailureWindow = 5 * time.Minute
	loginLockDuration  = 5 * time.Minute
	loginCleanupPeriod = time.Minute
	maxLoginFailures   = 8
	maxLoginEntries    = 4096
)

type loginAttemptState struct {
	Failures    int
	WindowStart time.Time
	LockedUntil time.Time
}

var loginAttempts = struct {
	sync.Mutex
	entries     map[string]loginAttemptState
	lastCleanup time.Time
}{entries: make(map[string]loginAttemptState)}

func loginAttemptKey(c *gin.Context, username string) string {
	return strings.ToLower(strings.TrimSpace(username)) + "\x00" + directPeerIP(c)
}

func directPeerIP(c *gin.Context) string {
	if c == nil || c.Request == nil {
		return "unknown"
	}
	host, _, err := net.SplitHostPort(strings.TrimSpace(c.Request.RemoteAddr))
	if err == nil && host != "" {
		return host
	}
	return strings.TrimSpace(c.Request.RemoteAddr)
}

func loginAllowed(key string) (bool, time.Duration) {
	now := time.Now()
	loginAttempts.Lock()
	defer loginAttempts.Unlock()
	cleanupLoginAttemptsLocked(now)
	state, exists := loginAttempts.entries[key]
	if !exists {
		if len(loginAttempts.entries) >= maxLoginEntries {
			return false, loginFailureWindow
		}
		return true, 0
	}
	if now.Before(state.LockedUntil) {
		return false, time.Until(state.LockedUntil).Round(time.Second)
	}
	if now.Sub(state.WindowStart) >= loginFailureWindow {
		delete(loginAttempts.entries, key)
		return true, 0
	}
	return true, 0
}

func recordLoginFailure(key string) {
	now := time.Now()
	loginAttempts.Lock()
	defer loginAttempts.Unlock()
	cleanupLoginAttemptsLocked(now)
	state, exists := loginAttempts.entries[key]
	if !exists && len(loginAttempts.entries) >= maxLoginEntries {
		return
	}
	if state.WindowStart.IsZero() || now.Sub(state.WindowStart) >= loginFailureWindow {
		state = loginAttemptState{WindowStart: now}
	}
	state.Failures++
	if state.Failures >= maxLoginFailures {
		state.LockedUntil = now.Add(loginLockDuration)
	}
	loginAttempts.entries[key] = state
}

func cleanupLoginAttemptsLocked(now time.Time) {
	if loginAttempts.lastCleanup.IsZero() || now.Sub(loginAttempts.lastCleanup) >= loginCleanupPeriod {
		for entryKey, entry := range loginAttempts.entries {
			if now.After(entry.LockedUntil) && now.Sub(entry.WindowStart) >= loginFailureWindow {
				delete(loginAttempts.entries, entryKey)
			}
		}
		loginAttempts.lastCleanup = now
	}
}

func clearLoginFailures(key string) {
	loginAttempts.Lock()
	delete(loginAttempts.entries, key)
	loginAttempts.Unlock()
}
