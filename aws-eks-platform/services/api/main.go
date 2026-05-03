// Package main is the entry point for the api-service.
// Zero external dependencies — uses only the Go standard library.
// Exposes: /health/live, /health/ready, /metrics, /api/v1/status
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"sync/atomic"
	"syscall"
	"time"
)

// Build-time variables — injected by -ldflags in the Dockerfile.
// Defaults are set for local development.
var (
	version   = "dev"
	gitCommit = "none"
	buildDate = "unknown"
)

// Runtime config — injected via environment variables (Kubernetes ConfigMap/Secrets).
var (
	startTime   = time.Now()
	environment = getEnv("ENVIRONMENT", "development")
	port        = getEnv("PORT", "8080")
)

// Prometheus-compatible counters using atomic integers (no external libs needed).
var (
	requestsTotal  atomic.Int64
	requestsErrors atomic.Int64
)

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("failed to encode response", "error", err)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Handlers
// ─────────────────────────────────────────────────────────────────────────────

// handleLive is the Kubernetes liveness probe endpoint.
// Returns 200 as long as the process is running.
func handleLive(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleReady is the Kubernetes readiness probe endpoint.
// Extend this to check DB connectivity, cache warmup, etc.
// Return 503 to signal the pod should be removed from the load balancer.
func handleReady(w http.ResponseWriter, r *http.Request) {
	// TODO: add real dependency checks here (DB ping, cache check, etc.)
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

// handleStatus returns runtime information about the service.
// This is the primary API endpoint the frontend calls.
func handleStatus(w http.ResponseWriter, r *http.Request) {
	requestsTotal.Add(1)

	resp := map[string]any{
		"status":      "ok",
		"version":     version,
		"git_commit":  gitCommit,
		"build_date":  buildDate,
		"environment": environment,
		"uptime":      time.Since(startTime).Round(time.Second).String(),
		"go_version":  runtime.Version(),
		"goos":        runtime.GOOS,
		"goarch":      runtime.GOARCH,
		"requests":    requestsTotal.Load(),
	}
	writeJSON(w, http.StatusOK, resp)
}

// handleMetrics exposes Prometheus-compatible metrics in the text exposition format.
// The Helm chart's ServiceMonitor scrapes this endpoint every 30s.
func handleMetrics(w http.ResponseWriter, r *http.Request) {
	uptime := time.Since(startTime).Seconds()
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")

	fmt.Fprintf(w, `# HELP api_up Whether the API is healthy (1 = up, 0 = down).
# TYPE api_up gauge
api_up 1
# HELP api_uptime_seconds Number of seconds since the API service started.
# TYPE api_uptime_seconds gauge
api_uptime_seconds %.2f
# HELP api_requests_total Total number of requests handled by the API.
# TYPE api_requests_total counter
api_requests_total %d
# HELP api_errors_total Total number of errors returned by the API.
# TYPE api_errors_total counter
api_errors_total %d
# HELP api_build_info Static build information.
# TYPE api_build_info gauge
api_build_info{version=%q,git_commit=%q,build_date=%q,environment=%q,go_version=%q} 1
`,
		uptime,
		requestsTotal.Load(),
		requestsErrors.Load(),
		version, gitCommit, buildDate, environment, runtime.Version(),
	)
}

// ─────────────────────────────────────────────────────────────────────────────
// Middleware
// ─────────────────────────────────────────────────────────────────────────────

// loggingMiddleware logs every request as structured JSON via slog.
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap ResponseWriter to capture status code
		lrw := &loggingResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(lrw, r)

		// Skip logging probe endpoints to reduce noise
		if r.URL.Path == "/health/live" || r.URL.Path == "/health/ready" {
			return
		}

		slog.Info("http request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", lrw.statusCode,
			"duration_ms", time.Since(start).Milliseconds(),
			"remote_addr", r.RemoteAddr,
			"user_agent", r.UserAgent(),
		)
	})
}

type loggingResponseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (lrw *loggingResponseWriter) WriteHeader(code int) {
	lrw.statusCode = code
	lrw.ResponseWriter.WriteHeader(code)
}

// corsMiddleware adds CORS headers so the frontend can call the API.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

func main() {
	// Structured JSON logging — picked up by Fluentd/Loki in the cluster
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	// Register routes using Go 1.22 typed mux patterns
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", handleLive)
	mux.HandleFunc("GET /health/ready", handleReady)
	mux.HandleFunc("GET /metrics", handleMetrics)
	mux.HandleFunc("GET /api/v1/status", handleStatus)

	// Stack middleware: CORS → logging → mux
	handler := corsMiddleware(loggingMiddleware(mux))

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      handler,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Graceful shutdown on SIGINT / SIGTERM
	shutdownDone := make(chan struct{})
	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
		sig := <-quit

		slog.Info("shutdown signal received — draining connections",
			"signal", sig.String(),
			"timeout", "30s",
		)

		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		if err := srv.Shutdown(ctx); err != nil {
			slog.Error("graceful shutdown failed", "error", err)
		}
		close(shutdownDone)
	}()

	slog.Info("api-service started",
		"port", port,
		"environment", environment,
		"version", version,
		"git_commit", gitCommit,
		"build_date", buildDate,
	)

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}

	<-shutdownDone
	slog.Info("api-service stopped gracefully")
}
