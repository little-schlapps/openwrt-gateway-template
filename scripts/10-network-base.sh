#!/bin/sh
# LAN bridge, two DHCP WAN uplinks with distinct metrics, firewall WAN zone
# with explicit devices, STP on the LAN bridge, dropbear on all interfaces.
. "$(dirname "$0")/../lib/common.sh"
load_config
backup network-base /etc/config/network /etc/config/firewall /etc/config/dropbear

# --- LAN bridge
br=$(uci show network | sed -n "s/^network\.\(@device\[[0-9]*\]\)\.name='br-lan'$/\1/p" | head -n1)
[ -n "$br" ] || die "br-lan device section not found"
uci -q delete network.$br.ports
for p in $LAN_PORTS; do uci add_list network.$br.ports="$p"; done
uci set network.$br.stp="$LAN_STP"
[ "$LAN_STP" = 1 ] && uci set network.$br.forward_delay="$LAN_STP_FORWARD_DELAY"
uci set network.$LAN_IF.ipaddr="$LAN_IP"

# --- WAN uplinks (replace the default single 'wan')
for n in 1 2; do
	eval ifn=\$WAN${n}_IF dev=\$WAN${n}_DEV metric=\$WAN${n}_METRIC cid=\$WAN${n}_SENDCLIENTID
	uci set network.$ifn=interface
	uci set network.$ifn.proto='dhcp'
	uci set network.$ifn.device="$dev"
	uci set network.$ifn.metric="$metric"
	if [ -n "$cid" ]; then uci set network.$ifn.sendclientid="$cid"; else uci -q delete network.$ifn.sendclientid; fi
done
[ "$WAN1_IF" != wan ] && [ "$WAN2_IF" != wan ] && { uci -q delete network.wan; uci -q delete network.wan6; }

# --- firewall: put both uplinks in the 'wan' zone and pin the devices.
# fw4 only adds an interface's device to the zone if the interface has an
# address when the firewall loads; an uplink that comes up later then gets no
# masquerading. Listing the devices explicitly avoids that.
wz=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p" | head -n1)
[ -n "$wz" ] || die "firewall zone 'wan' not found"
uci -q delete firewall.$wz.network
uci -q delete firewall.$wz.device
for n in "$WAN1_IF" "$WAN2_IF"; do uci add_list firewall.$wz.network="$n"; done
for d in "$WAN1_DEV" "$WAN2_DEV"; do uci add_list firewall.$wz.device="$d"; done

# --- dropbear on all interfaces (survives network reloads; wan input is rejected by the firewall)
uci -q delete dropbear.@dropbear[0].Interface

commit_uci network firewall dropbear
log "apply with: service network reload && service firewall reload && service dropbear restart"
log "note: with STP enabled the LAN pauses for 2x forward_delay after each reload"
