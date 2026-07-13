package api

import (
	"fmt"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestLoginRateLimitLocksAndClears(t *testing.T) {
	gin.SetMode(gin.TestMode)
	request := httptest.NewRequest("POST", "/login", nil)
	request.RemoteAddr = "192.0.2.10:12345"
	context, _ := gin.CreateTestContext(httptest.NewRecorder())
	context.Request = request
	key := loginAttemptKey(context, "Admin")
	clearLoginFailures(key)
	defer clearLoginFailures(key)

	for index := 0; index < maxLoginFailures; index++ {
		recordLoginFailure(key)
	}
	if allowed, _ := loginAllowed(key); allowed {
		t.Fatal("login should be locked after repeated failures")
	}
	clearLoginFailures(key)
	if allowed, _ := loginAllowed(key); !allowed {
		t.Fatal("successful login should clear the failure state")
	}
}

func TestLoginRateLimitHasBoundedState(t *testing.T) {
	loginAttempts.Lock()
	loginAttempts.entries = make(map[string]loginAttemptState)
	loginAttempts.lastCleanup = time.Time{}
	loginAttempts.Unlock()
	defer func() {
		loginAttempts.Lock()
		loginAttempts.entries = make(map[string]loginAttemptState)
		loginAttempts.lastCleanup = time.Time{}
		loginAttempts.Unlock()
	}()

	for index := 0; index < maxLoginEntries+10; index++ {
		recordLoginFailure(fmt.Sprintf("attempt-%d", index))
	}
	loginAttempts.Lock()
	entryCount := len(loginAttempts.entries)
	loginAttempts.Unlock()
	if entryCount > maxLoginEntries {
		t.Fatalf("login limiter retained %d entries, want at most %d", entryCount, maxLoginEntries)
	}
}

func TestLoginRateLimitDoesNotEvictLockedEntriesAtCapacity(t *testing.T) {
	now := time.Now()
	loginAttempts.Lock()
	loginAttempts.entries = make(map[string]loginAttemptState, maxLoginEntries)
	loginAttempts.lastCleanup = now
	loginAttempts.entries["locked-user"] = loginAttemptState{
		Failures: maxLoginFailures, WindowStart: now, LockedUntil: now.Add(loginLockDuration),
	}
	for index := 1; index < maxLoginEntries; index++ {
		loginAttempts.entries[fmt.Sprintf("attempt-%d", index)] = loginAttemptState{Failures: 1, WindowStart: now}
	}
	loginAttempts.Unlock()
	defer func() {
		loginAttempts.Lock()
		loginAttempts.entries = make(map[string]loginAttemptState)
		loginAttempts.lastCleanup = time.Time{}
		loginAttempts.Unlock()
	}()

	recordLoginFailure("overflow")
	loginAttempts.Lock()
	_, lockedExists := loginAttempts.entries["locked-user"]
	_, overflowExists := loginAttempts.entries["overflow"]
	loginAttempts.Unlock()
	if !lockedExists || overflowExists {
		t.Fatal("capacity handling evicted a protected entry")
	}
	if allowed, _ := loginAllowed("new-user"); allowed {
		t.Fatal("new login keys should fail closed while limiter state is full")
	}
}
