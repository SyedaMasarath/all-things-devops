################################################################################
# Stage 1 — Build
# Uses the official Go image with Alpine for a minimal build environment.
# CGO is disabled to produce a fully static binary.
################################################################################
FROM golang:1.22-alpine AS builder

# Install CA certificates and timezone data so the final image can make
# HTTPS calls and handle timezones without a full OS.
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache ca-certificates tzdata && \
    update-ca-certificates

WORKDIR /build

# Cache dependency downloads as a separate layer.
# Only re-runs when go.mod changes (not on every source code change).
COPY go.mod ./
RUN go mod download

# Copy source and build the static binary.
# -trimpath:   removes local file paths from the binary (reproducible builds)
# -s -w:       strips debug symbols (reduces binary size ~30%)
# -X main.*:   injects build-time variables from Docker build args
COPY . .

ARG VERSION=dev
ARG GIT_COMMIT=none
ARG BUILD_DATE=unknown

RUN CGO_ENABLED=0 GOOS=linux go build \
      -trimpath \
      -ldflags="-s -w \
        -X main.version=${VERSION} \
        -X main.gitCommit=${GIT_COMMIT} \
        -X main.buildDate=${BUILD_DATE}" \
      -o api-service .

# Verify the binary is truly static (will error if it has dynamic links)
RUN file api-service | grep -q "statically linked" || \
    { echo "Binary is NOT statically linked!"; exit 1; }

################################################################################
# Stage 2 — Final (distroless)
# gcr.io/distroless/static-debian12:nonroot contains:
#   - CA certificates
#   - No shell, no package manager, no tools
#   - Non-root user (uid 65532) pre-configured
# This eliminates the entire OS attack surface.
################################################################################
FROM gcr.io/distroless/static-debian12:nonroot

# Copy timezone data and CA certs from the builder stage
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the static binary
COPY --from=builder /build/api-service /api-service

# The :nonroot image sets USER 65532 (nonroot) by default.
# Explicitly declaring it here makes the intent clear in image scanners.
USER 65532:65532

EXPOSE 8080

# No shell in distroless — must use exec form (JSON array)
ENTRYPOINT ["/api-service"]
