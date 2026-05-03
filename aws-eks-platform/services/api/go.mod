module github.com/your-org/api-service

// Go 1.22 required for:
//   - Typed HTTP mux patterns (e.g. "GET /path")
//   - log/slog structured logging (1.21+)
//   - Range-over-int (minor convenience)
go 1.22
