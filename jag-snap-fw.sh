#!/bin/bash

# Usage: script.sh <region> [port]
# port defaults to 18899

# Exit on any error
set -e

region="$1"
if [ -z "$region" ]; then
  echo "Error: Region parameter is required."
  exit 1
fi

port="${2:-18899}"

# Ensure required commands are available
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required."; exit 1; }
command -v iptables >/dev/null 2>&1 || { echo "Error: iptables is required."; exit 1; }
command -v ipset >/dev/null 2>&1 || { echo "Error: ipset is required."; exit 1; }

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

# Check if ipset exists and update accordingly
if sudo ipset list "$set_name" &> /dev/null; then
  sudo ipset destroy "$temp_name" 2>/dev/null || true
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

# iptables configuration
chain_name="JAG_${port}"

# Check if chain exists; create and configure only if it doesn't
if ! sudo iptables -L "$chain_name" -n &> /dev/null; then
  sudo iptables -N "$chain_name"
  # Add rules to the chain: allow from ipset, drop others
  sudo iptables -A "$chain_name" -m set --match-set "$set_name" src -j ACCEPT
  sudo iptables -A "$chain_name" -j DROP
else
  # Check if the required rules already exist in the chain
  rule1="-m set --match-set $set_name src -j ACCEPT"
  rule2="-j DROP"
  if ! sudo iptables -C "$chain_name" $rule1 2>/dev/null || ! sudo iptables -C "$chain_name" $rule2 2>/dev/null; then
    # Flush and re-add rules only if they don't match the expected configuration
    sudo iptables -F "$chain_name"
    sudo iptables -A "$chain_name" -m set --match-set "$set_name" src -j ACCEPT
    sudo iptables -A "$chain_name" -j DROP
  fi
fi

# Ensure global rules for established connections and loopback are in place at top positions
rules=$(sudo iptables -S INPUT | nl -v 1 | grep -E -- "-A INPUT")
established_rule="-m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
loopback_rule="-i lo -j ACCEPT"
jump_rule="-p tcp --dport $port -j $chain_name"

established_pos=$(echo "$rules" | grep -- "$established_rule" | awk '{print $1}' | head -n 1)
loopback_pos=$(echo "$rules" | grep -- "$loopback_rule" | awk '{print $1}' | head -n 1)

jump_pos=$((established_pos > loopback_pos ? established_pos : loopback_pos))

# Check if jump rule exists; add only if it doesn't
if ! sudo iptables -C INPUT $jump_rule 2>/dev/null; then
  sudo iptables -I INPUT $jump_pos $jump_rule
fi

echo "ipset updated, custom chain $chain_name configured, and iptables rules ensured for port $port."
