# Jag-Snap
A compact reverse proxy designed for Solana validators, allowing controlled access to snapshots and selected RPC methods.

## Build
```shell
docker build -t jag-snap .
```

## Run
```shell
docker run -d -p 18899:18899 -p 9901:9901 --network host jag-snap
```

## Validator args
To serve snapshots from a known validator, the RPC address and port must be advertised via gossip. To route traffic through the proxy and restrict access to all RPC methods, modify the validator startup arguments as follows:To serve snapshots from a known validator, the RPC address and port must be advertised via gossip. To route traffic through the proxy and restrict access to all RPC methods, modify the validator startup arguments as follows:
* remove `--private-rpc` if present
* add `--rpc-port 8899`
* add `--rpc-bind-address 127.0.0.1` to only allow traffic localhost traffic reaching port 8899
* add `--public-rpc-address <public ip>:18899`
* add `--no-port-check`

### Example
```shell
...
--rpc-port 8899 \
--public-rpc-address <PUBLIC IP>:18899 \
--rpc-bind-address 127.0.0.1 \
--no-port-check \
...
```

## Firewalling setup

### If you use iptables
```shell
sudo iptables -A INPUT -p tcp --dport 18899 -j ACCEPT
```

### If you use iptables
```shell
sudo ufw allow 18899/tcp
sudo ufw reload
```
