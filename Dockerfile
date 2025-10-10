FROM openresty/openresty:alpine

# Copy NGINX configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

RUN apk add --no-cache curl unzip
RUN mkdir -p /usr/local/openresty/lualib/prometheus
RUN curl -L https://github.com/knyar/nginx-lua-prometheus/archive/refs/heads/master.zip -o /tmp/prometheus.zip \
    && unzip /tmp/prometheus.zip -d /tmp \
    && cp -r /tmp/nginx-lua-prometheus-master/* /usr/local/openresty/lualib/prometheus \
    && rm -rf /tmp/*

# Expose port for RPC and snapshot access
EXPOSE 18899 9145

# Run OpenResty in foreground
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]