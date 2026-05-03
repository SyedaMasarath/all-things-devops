################################################################################
# Stage 1 — Builder
# For a pure static frontend there's no build step yet.
# This stage is here so adding npm/Vite later is a one-line change.
# Future: RUN npm ci && npm run build
################################################################################
FROM node:20-alpine AS builder
WORKDIR /app
COPY src/ ./dist/

################################################################################
# Stage 2 — nginx (non-root)
# Serves the static dashboard and proxies /api/ → api-service.
################################################################################
FROM nginx:1.27-alpine

# Remove the default config
RUN rm /etc/nginx/conf.d/default.conf

# Install custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built static assets
COPY --from=builder /app/dist/ /usr/share/nginx/html/

# Grant nginx user ownership of the directories it needs to write to
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

# Drop to non-root
USER nginx

EXPOSE 80

# Docker-level health check (separate from K8s probes)
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]