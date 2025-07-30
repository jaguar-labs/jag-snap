FROM openresty/openresty:alpine

# Copy NGINX configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Expose port for RPC and snapshot access
EXPOSE 18899

# Run OpenResty in foreground
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]