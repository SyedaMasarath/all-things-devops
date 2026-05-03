package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestHandleLive verifies the liveness probe returns 200 with status "ok".
func TestHandleLive(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	w := httptest.NewRecorder()

	handleLive(w, req)

	res := w.Result()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.StatusCode)
	}

	var body map[string]string
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if body["status"] != "ok" {
		t.Errorf("expected status 'ok', got %q", body["status"])
	}
}

// TestHandleReady verifies the readiness probe returns 200 with status "ready".
func TestHandleReady(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health/ready", nil)
	w := httptest.NewRecorder()

	handleReady(w, req)

	res := w.Result()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.StatusCode)
	}

	var body map[string]string
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if body["status"] != "ready" {
		t.Errorf("expected status 'ready', got %q", body["status"])
	}
}

// TestHandleStatus verifies the /api/v1/status endpoint returns expected fields.
func TestHandleStatus(t *testing.T) {
	before := requestsTotal.Load()

	req := httptest.NewRequest(http.MethodGet, "/api/v1/status", nil)
	w := httptest.NewRecorder()

	handleStatus(w, req)

	res := w.Result()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.StatusCode)
	}

	var body map[string]any
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	requiredFields := []string{"status", "version", "environment", "uptime", "go_version"}
	for _, field := range requiredFields {
		if _, ok := body[field]; !ok {
			t.Errorf("missing required field %q in response", field)
		}
	}

	if body["status"] != "ok" {
		t.Errorf("expected status 'ok', got %v", body["status"])
	}

	// Counter should have incremented
	after := requestsTotal.Load()
	if after != before+1 {
		t.Errorf("expected requestsTotal to increment by 1, was %d now %d", before, after)
	}
}

// TestHandleMetrics verifies the /metrics endpoint returns valid Prometheus text format.
func TestHandleMetrics(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	w := httptest.NewRecorder()

	handleMetrics(w, req)

	res := w.Result()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.StatusCode)
	}

	contentType := res.Header.Get("Content-Type")
	if contentType != "text/plain; version=0.0.4; charset=utf-8" {
		t.Errorf("unexpected Content-Type: %q", contentType)
	}

	// Verify required metric names are present
	body := w.Body.String()
	requiredMetrics := []string{
		"api_up",
		"api_uptime_seconds",
		"api_requests_total",
		"api_errors_total",
		"api_build_info",
	}
	for _, metric := range requiredMetrics {
		if !contains(body, metric) {
			t.Errorf("metric %q not found in /metrics output", metric)
		}
	}
}

// TestCORSMiddleware verifies CORS headers are set on responses.
func TestCORSMiddleware(t *testing.T) {
	handler := corsMiddleware(http.HandlerFunc(handleLive))

	req := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	if w.Header().Get("Access-Control-Allow-Origin") != "*" {
		t.Error("expected Access-Control-Allow-Origin: *")
	}
}

// TestCORSMiddlewareOptions verifies preflight OPTIONS requests return 204.
func TestCORSMiddlewareOptions(t *testing.T) {
	handler := corsMiddleware(http.HandlerFunc(handleLive))

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/status", nil)
	w := httptest.NewRecorder()

	handler.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Errorf("expected 204 for OPTIONS, got %d", w.Code)
	}
}

// contains is a simple string contains helper (avoids importing strings).
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr ||
		len(s) > 0 && searchStr(s, substr))
}

func searchStr(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
