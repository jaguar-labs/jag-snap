# Jag-Snap
A lightweight reverse proxy for Solana validators, enabling restricted access to snapshots and specific RPC methods.

### Build
```shell
docker build -t jag-snap .
```

### Run
```shell
docker run -d --name jag-snap --network host jag-snap
```

### Validator args
To serve snapshots from a known validator, the RPC address and port must be advertised via gossip. To route traffic through the proxy and restrict access to all RPC methods, modify the validator startup arguments as follows:To serve snapshots from a known validator, the RPC address and port must be advertised via gossip. To route traffic through the proxy and restrict access to all RPC methods, modify the validator startup arguments as follows:
* remove `--private-rpc` if present
* remove `--rpc-bind-address 127.0.0.1` if present
* add `--public-rpc-address <public ip>:18899`

#### Example
```shell
...
--rpc-port 8899 \
--public-rpc-address 69.67.151.19:18899
...
```

### Open proxy port to outside
To serve snapshots from a known validator, the RPC address and port must be advertised via gossip. To route traffic through the proxy and restrict access to all RPC methods, modify the validator startup arguments as follows:
#### Ipdables example
```shell
sudo iptables -A INPUT -p tcp --dport 18899 -j ACCEPT
```

#### UFW example
```shell
sudo ufw allow 18899/tcp
```