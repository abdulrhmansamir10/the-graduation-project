# ============================================================================
# Frontend Dockerfile (Secured)
# ============================================================================
# 
# ARCHITECTURE: Multi-stage build
# 1. Build Stage: Node.js compiles React code
# 2. Production Stage: Nginx serves static files
#
# SECURITY FEATURES:
# - Minimal Nginx Alpine image
# - Non-root execution (where possible with Nginx)
# - Only static files included (no source code)
# ============================================================================

# ----------------------------------------------------------------------------
# Stage 1: Build React App
# ----------------------------------------------------------------------------
FROM node:18-alpine as build

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build

# ----------------------------------------------------------------------------
# Stage 2: Serve with Nginx
# ----------------------------------------------------------------------------
FROM nginx:alpine

# Install curl for healthcheck
RUN apk add --no-cache curl

# Copy build artifacts from build stage
COPY --from=build /app/dist /usr/share/nginx/html

# Copy custom Nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create directory for SSL certificates
RUN mkdir -p /etc/nginx/ssl

# Nginx runs as root by default to bind port 80, then drops privileges
# For stricter security, we can configure it to run as non-root on high ports
# But for standard web server usage, official Nginx image handles this well.
# We will ensure file permissions are correct.

# Change ownership of static files
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d

# Touch the PID file and change ownership
RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

# Switch to non-root user
USER nginx

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]