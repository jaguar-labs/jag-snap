# Jag-Snap
A simple reverse proxy allowing solana validators to only serve snapshots and a subsets of rpc methods

### Build
```shell
docker build -t jag-snap .
```

### Run
```shell
docker run -d --name jag-snap --network host jag-snap
```