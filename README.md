# Jag-Snap
A lightweight reverse proxy for Solana validators, enabling restricted access to snapshots and specific RPC methods.

## Build
```shell
docker build -t jag-snap .
```

## Run
```shell
docker run -d --name jag-snap --network host jag-snap
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
--public-rpc-address 69.67.151.19:18899 \
--rpc-bind-address 127.0.0.1 \
--no-port-check \
...
```

## Firewalling setup
The jag-snap-fw.sh script runs as a systemd timer service to maintain iptables rules that grant Jagpool validators from a specific region access to the snapshots service. The allowed IP list is fetched from the Jagpool API and stored as an ipset, which is then referenced in the iptables rules. The ipset is refreshed and updated every minute

### copy script
```shell
sudo chown root:root /usr/local/bin/jag-snap-fw.sh
sudo chmod 755 /usr/local/bin/jag-snap-fw.sh
```

### Create a Dedicated User
Create a non-root user to run the script, with minimal privileges:

```shell
sudo useradd -m -s /bin/false jag-snap-fw
```

### Configure sudoers for Least Privilege
Grant the jagpool-user permission to run only the necessary iptables and ipset commands with sudo without a password, using a sudoers file.
Create a sudoers configuration file:
```shell
sudo visudo -f /etc/sudoers.d/jag-snap-fw
```
Add the following content:

```shell
jagpool-user ALL=(root) NOPASSWD: /sbin/iptables, /sbin/ipset
```

Set permissions for the sudoers file:

```shell
sudo chmod 440 /etc/sudoers.d/jag-snap-fw
```

Verify the sudoers configuration:

```shell
sudo -u jag-snap-fw sudo iptables -L
```
This should work without a password. Non-allowed commands (e.g., sudo ls) should fail.


## Create a Systemd Service and Timer

Use a systemd service and timer to run the script periodically as jag-snap-fw. This is more robust than cron for systemd-based systems.
Create the Systemd ServiceCreate `/etc/systemd/system/jag-sanp-fw.service`:

```shell
[Unit]
Description=Update jag snap firewall rules
After=network-online.target

[Service]
Type=oneshot
User=jag-snap-fw
ExecStart=/usr/local/bin/jag-snap-fw.sh LATAM 18899
# Replace 'LATAM' and '18899' with your desired region and port
```

* Type=oneshot: The service runs once and exits.
* User=jag-snap-fw: Runs as the dedicated user.
* ExecStart: Specifies the script with example arguments (LATAM and 18899). Adjust as needed.


# Create the Systemd Timer
Create `/etc/systemd/system/jag-snap-fw.timer`:
```shell
[Unit]
Description=Run jag snap firewall update periodically

[Timer]
OnCalendar=*:0/1
Persistent=true

[Install]
WantedBy=timers.target
```

* OnCalendar=hourly: Runs the script minutes, on every hour, on every day. Adjust to your desired schedule (e.g., daily, *:0/30 for every 30 minutes).
* Persistent=true: Runs missed executions if the system was offline.

Set permissions:

```shell
sudo chmod 644 /etc/systemd/system/jag-snap-fw.service
sudo chmod 644 /etc/systemd/system/jag-snap-fw.timer
```

Enable and start the timer:

```shell
sudo systemctl daemon-reload
sudo systemctl enable jag-snap-fw.timer
sudo systemctl start jag-snap-fw.timer
```

Verify the timer:
```shell
sudo systemctl list-timers jag-snap-fw.timer
```