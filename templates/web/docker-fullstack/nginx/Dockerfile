# Nginx Reverse Proxy Dockerfile
FROM nginx:alpine

# Install dependencies for SSL
RUN apk add --no-cache openssl

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY frontend.conf /etc/nginx/conf.d/frontend.conf

# Create SSL directory
RUN mkdir -p /etc/nginx/ssl

# Generate self-signed SSL certificate for development
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dev/CN=localhost"

# Set proper permissions
RUN chmod 600 /etc/nginx/ssl/nginx.key
RUN chmod 644 /etc/nginx/ssl/nginx.crt

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]