FROM envoyproxy/envoy:v1.26.0

COPY envoy.yaml /etc/envoy/envoy.yaml

EXPOSE 18899
EXPOSE 9901

CMD ["envoy", "-c", "/etc/envoy/envoy.yaml", "--log-level", "debug"]
