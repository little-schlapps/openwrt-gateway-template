#!/bin/sh
# Simulated primary-WAN outage: blocks only mwan3's health-check pings on the
# primary WAN device, so the link stays up but mwan3 sees "no internet".
# Reports detection and recovery time and the egress ISP before/during/after.
# The block is always removed (trap + 120 s watchdog).
. "$(dirname "$0")/../lib/common.sh"
load_config

LAN_ADDR="${LAN_IP%/*}"
IOT_ADDR="${IOT_IP%/*}"
targets=$(printf '%s, ' $TRACK_IPS); targets="${targets%, }"

cleanup() { nft delete table inet mwdrill 2>/dev/null; }
trap cleanup EXIT INT TERM
( sleep 120; nft delete table inet mwdrill 2>/dev/null ) &

st()  { mwan3 interfaces 2>/dev/null | grep "interface $1 " | sed 's/^ *//'; }
egr() { curl -s -m 8 --interface "$1" https://ipinfo.io/org; }

log "baseline: LAN=$(egr "$LAN_ADDR") | IoT=$(egr "$IOT_ADDR")"
nft add table inet mwdrill
nft add chain inet mwdrill out '{ type filter hook output priority -150; }'
nft add rule inet mwdrill out oifname "$WAN1_DEV" icmp type echo-request ip daddr "{ $targets }" drop
t=$(date +%s)
while ! st "$WAN1_IF" | grep -q offline && [ $(( $(date +%s) - t )) -lt 90 ]; do sleep 1; done
log "$WAN1_IF offline after $(( $(date +%s) - t ))s -> LAN=$(egr "$LAN_ADDR") | IoT=$(egr "$IOT_ADDR")"

cleanup
t=$(date +%s)
while ! st "$WAN1_IF" | grep -q 'is online' && [ $(( $(date +%s) - t )) -lt 90 ]; do sleep 1; done
log "$WAN1_IF online after $(( $(date +%s) - t ))s -> LAN=$(egr "$LAN_ADDR") | IoT=$(egr "$IOT_ADDR")"
