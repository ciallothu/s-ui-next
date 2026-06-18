package sub

import (
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestAddSubscriptionHeadersHonorsShowInfo(t *testing.T) {
	gin.SetMode(gin.TestMode)
	headers := []string{"upload=1; download=2; total=3; expire=4", "12", "client"}

	hiddenRecorder := httptest.NewRecorder()
	hiddenContext, _ := gin.CreateTestContext(hiddenRecorder)
	addSubscriptionHeaders(hiddenContext, headers, false)
	if value := hiddenRecorder.Header().Get("Subscription-Userinfo"); value != "" {
		t.Fatalf("Subscription-Userinfo must be hidden, got %q", value)
	}
	if value := hiddenRecorder.Header().Get("Profile-Update-Interval"); value != "12" {
		t.Fatalf("Profile-Update-Interval = %q, want 12", value)
	}

	visibleRecorder := httptest.NewRecorder()
	visibleContext, _ := gin.CreateTestContext(visibleRecorder)
	addSubscriptionHeaders(visibleContext, headers, true)
	if value := visibleRecorder.Header().Get("Subscription-Userinfo"); value != headers[0] {
		t.Fatalf("Subscription-Userinfo = %q, want %q", value, headers[0])
	}
}

func TestAddSubscriptionHeadersAcceptsPartialValues(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	addSubscriptionHeaders(context, nil, true)
}
