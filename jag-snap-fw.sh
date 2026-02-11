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
  sudo ipset create "$temp_name" $set_options -exist
  for ip in $(echo "$ips_json" | jq -r '.[]'); do
    sudo ipset add "$temp_name" "$ip" -exist
  done
  sudo ipset swap "$temp_name" "$set_name"
  sudo ipset destroy "$temp_name"
else
  sudo ipset create "$set_name" $set_options -exist
  for ip in $(echo "$ips_json" | jq -r '.[]'); do
    sudo ipset add "$set_name" "$ip" -exist
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

# Ensure baseline INPUT rules exist (idempotent)
established_rule="-m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
loopback_rule="-i lo -j ACCEPT"
jump_rule="-p tcp --dport $port -j $chain_name"

# Ensure ESTABLISHED rule present at/near top
if ! sudo iptables -C INPUT $established_rule 2>/dev/null; then
  sudo iptables -I INPUT 1 $established_rule
fi

# Ensure loopback rule present just after ESTABLISHED if possible
if ! sudo iptables -C INPUT $loopback_rule 2>/dev/null; then
  # Insert at 2 (after whatever is at 1—ideally ESTABLISHED from above)
  sudo iptables -I INPUT 2 $loopback_rule || sudo iptables -I INPUT 1 $loopback_rule
fi

# Figure out the (1-based) line numbers for those two rules
# (Empty -> treat as 0 so +1 below becomes 1)
established_pos=$(sudo iptables -L INPUT --line-numbers -n | awk '/RELATED,ESTABLISHED/ {print $1; exit}')
loopback_pos=$(sudo iptables -L INPUT --line-numbers -n | awk '/\blo\b/ && /ACCEPT/ {print $1; exit}')
: "${established_pos:=0}"
: "${loopback_pos:=0}"

# Choose the larger position and add 1 so we place *after* both
jump_pos=$(( (established_pos > loopback_pos ? established_pos : loopback_pos) + 1 ))
if [ "$jump_pos" -lt 1 ]; then jump_pos=1; fi

# Add the jump rule only if missing, at the computed position
if ! sudo iptables -C INPUT $jump_rule 2>/dev/null; then
  sudo iptables -I INPUT "$jump_pos" $jump_rule
fi

echo "ipset updated, custom chain $chain_name configured, and iptables rules ensured for port $port."