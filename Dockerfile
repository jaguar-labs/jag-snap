FROM openresty/openresty:alpine-fat

# Copy NGINX configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

RUN /usr/local/openresty/luajit/bin/luarocks install nginx-lua-prometheus

# Expose port for RPC and snapshot access
EXPOSE 18899 9145

# Run OpenResty in foreground
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]