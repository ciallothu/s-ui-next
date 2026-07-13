package service

import (
	"fmt"
	"testing"
	"time"
)

func TestPendingAuthStateIsBoundedAndConsumed(t *testing.T) {
	oidcPendingStates.Lock()
	oidcPendingStates.entries = make(map[string]oidcPending)
	oidcPendingStates.lastCleanup = time.Time{}
	oidcPendingStates.Unlock()
	defer func() {
		oidcPendingStates.Lock()
		oidcPendingStates.entries = make(map[string]oidcPending)
		oidcPendingStates.lastCleanup = time.Time{}
		oidcPendingStates.Unlock()
	}()

	expiry := time.Now().Add(time.Minute)
	for index := 0; index < maxPendingAuthSessions; index++ {
		key := fmt.Sprintf("state-%d", index)
		if err := storeOIDCPending(key, oidcPending{Expiry: expiry}); err != nil {
			t.Fatal(err)
		}
	}
	if err := storeOIDCPending("overflow", oidcPending{Expiry: expiry}); err == nil {
		t.Fatal("pending OIDC state should reject entries beyond its capacity")
	}
	if _, ok := takeOIDCPending("state-0"); !ok {
		t.Fatal("stored OIDC state was not returned")
	}
	if _, ok := takeOIDCPending("state-0"); ok {
		t.Fatal("OIDC state must be single-use")
	}
}
