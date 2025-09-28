#!/bin/bash

# Usage: script.sh <region> [port]
# port defaults to 18899

set -e

region="$1"
if [ -z "$region" ]; then
  echo "Error: Region parameter is required."
  exit 1
fi

port="${2:-18899}"

# Ensure required commands
for cmd in curl jq iptables ipset; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd is required."; exit 1; }
done

# Check if UFW is enabled
ufw_enabled=false
if command -v ufw >/dev/null 2>&1; then
  if sudo ufw status | grep -q "Status: active"; then
    ufw_enabled=true
  fi
fi

# Fetch IPs from API
api_url="https://api.jagpool.xyz/validators-ips/$region"
ips_json=$(curl -s --fail "$api_url")
if [ -z "$ips_json" ]; then
  echo "Error: API call failed or returned empty response."
  exit 1
fi

# ipset configuration
set_name="jag-snap-allowlist"
temp_name="${set_name}-tmp"
set_options="hash:ip family inet hashsize 1024 maxelem 65536"

if sudo ipset list "$set_name" &> /dev/null; then
  sudo ipset create "$temp_name" $set_options
  for ip in $(echo "$ips_json" | jq -r '.[]'); do
    sudo ipset add "$temp_name" "$ip"
  done
  sudo ipset swap "$temp_name" "$set_name"
  sudo ipset destroy "$temp_name"
else
  sudo ipset create "$set_name" $set_options
  for ip in $(echo "$ips_json" | jq -r '.[]'); do
    sudo ipset add "$set_name" "$ip"
  done
fi

# iptables chain
chain_name="JAG_${port}"

if ! sudo iptables -L "$chain_name" -n &> /dev/null; then
  sudo iptables -N "$chain_name"
  sudo iptables -A "$chain_name" -m set --match-set "$set_name" src -j ACCEPT
  sudo iptables -A "$chain_name" -j DROP
else
  # ensure rules inside the chain are correct
  sudo iptables -F "$chain_name"
  sudo iptables -A "$chain_name" -m set --match-set "$set_name" src -j ACCEPT
  sudo iptables -A "$chain_name" -j DROP
fi

jump_rule="-p tcp --dport $port -j $chain_name"
if ! sudo iptables -C INPUT $jump_rule 2>/dev/null; then
  sudo iptables -I INPUT 1 $jump_rule
fi

# --- Special handling if UFW is enabled ---
if [ "$ufw_enabled" = true ]; then
  echo "UFW detected: ensuring persistence in /etc/ufw/before.rules"

  before_rules="/etc/ufw/before.rules"
  tmpfile=$(mktemp)

  # If our chain isn’t already in before.rules, add it
  if ! sudo grep -q "$chain_name" "$before_rules"; then
    sudo cp "$before_rules" "$before_rules.bak.$(date +%s)"
    awk -v chain="$chain_name" -v set_name="$set_name" -v port="$port" '
      /^COMMIT$/ && !done {
        print ": " chain " - [0:0]"
        print "-A " chain " -m set --match-set " set_name " src -j ACCEPT"
        print "-A " chain " -j DROP"
        print "-A INPUT -p tcp --dport " port " -j " chain
        done=1
      }
      {print}
    ' "$before_rules" | sudo tee "$tmpfile" >/dev/null
    sudo mv "$tmpfile" "$before_rules"
    sudo ufw reload
  fi
fi

echo "ipset updated, chain $chain_name configured, rules ensured for port $port."
if [ "$ufw_enabled" = true ]; then
  echo "Integration with UFW complete (before.rules updated)."
fi