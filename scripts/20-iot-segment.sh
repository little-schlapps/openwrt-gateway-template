#!/bin/sh
# Isolated IoT/camera segment on its own port:
#  - own subnet + DHCP, own firewall zone
#  - internet allowed, LAN -> IoT allowed, IoT -> LAN rejected
#  - router itself only answers DHCP and DNS from the IoT side
#  - IoT internet traffic is policy-routed via the backup WAN only and is
#    rejected on the primary WAN (no silent fallback)
. "$(dirname "$0")/../lib/common.sh"
load_config
backup iot /etc/config/network /etc/config/dhcp /etc/config/firewall

# --- remove the IoT port from the LAN bridge if present
br=$(uci show network | sed -n "s/^network\.\(@device\[[0-9]*\]\)\.name='br-lan'$/\1/p" | head -n1)
[ -n "$br" ] && uci -q del_list network.$br.ports="$IOT_DEV"

# --- interface + DHCP
uci set network.$IOT_IF=interface
uci set network.$IOT_IF.proto='static'
uci set network.$IOT_IF.device="$IOT_DEV"
uci set network.$IOT_IF.ipaddr="$IOT_IP"
uci set dhcp.$IOT_IF=dhcp
uci set dhcp.$IOT_IF.interface="$IOT_IF"
uci set dhcp.$IOT_IF.start='100'
uci set dhcp.$IOT_IF.limit='150'
uci set dhcp.$IOT_IF.leasetime='12h'

# --- policy routing: rules (the default route in table $IOT_ROUTE_TABLE is
# maintained by the hotplug script, because the backup WAN gateway comes from DHCP)
uci set network.main_nodefault=rule
uci set network.main_nodefault.lookup='main'
uci set network.main_nodefault.suppress_prefixlength='0'
uci set network.main_nodefault.priority='90'
uci set network.iot_policy=rule
uci set network.iot_policy.src="$IOT_NET"
uci set network.iot_policy.lookup="$IOT_ROUTE_TABLE"
uci set network.iot_policy.priority='100'

# --- firewall zone + forwardings + rules (named sections, so re-runs are idempotent)
uci set firewall.zone_iot=zone
uci set firewall.zone_iot.name="$IOT_IF"
uci set firewall.zone_iot.network="$IOT_IF"
uci set firewall.zone_iot.input='REJECT'
uci set firewall.zone_iot.output='ACCEPT'
uci set firewall.zone_iot.forward='REJECT'
uci set firewall.fwd_iot_wan=forwarding
uci set firewall.fwd_iot_wan.src="$IOT_IF"
uci set firewall.fwd_iot_wan.dest='wan'
uci set firewall.fwd_lan_iot=forwarding
uci set firewall.fwd_lan_iot.src="$LAN_IF"
uci set firewall.fwd_lan_iot.dest="$IOT_IF"
uci set firewall.iot_dhcp=rule
uci set firewall.iot_dhcp.name='IoT-DHCP'
uci set firewall.iot_dhcp.src="$IOT_IF"
uci set firewall.iot_dhcp.proto='udp'
uci set firewall.iot_dhcp.dest_port='67-68'
uci set firewall.iot_dhcp.target='ACCEPT'
uci set firewall.iot_dns=rule
uci set firewall.iot_dns.name='IoT-DNS'
uci set firewall.iot_dns.src="$IOT_IF"
uci set firewall.iot_dns.proto='tcp udp'
uci set firewall.iot_dns.dest_port='53'
uci set firewall.iot_dns.target='ACCEPT'
uci set firewall.iot_no_primary=rule
uci set firewall.iot_no_primary.name='IoT-no-primary-WAN'
uci set firewall.iot_no_primary.src="$IOT_IF"
uci set firewall.iot_no_primary.dest='wan'
uci set firewall.iot_no_primary.device="$IOT_BLOCKED_DEV"
uci set firewall.iot_no_primary.direction='out'
uci set firewall.iot_no_primary.proto='all'
uci set firewall.iot_no_primary.target='REJECT'

commit_uci network dhcp firewall

# --- hotplug: keep "default via <backup WAN gateway>" in the IoT routing table
H=/etc/hotplug.d/iface/90-iot-policy-route
if [ "$DRY_RUN" = 1 ]; then
	log "DRY-RUN: would install $H"
else
	sed -e "s|@EGRESS_IF@|$IOT_EGRESS_IF|g" -e "s|@TABLE@|$IOT_ROUTE_TABLE|g" \
		"$TEMPLATE_DIR/files/hotplug-iot-policy-route" > "$H"
	chmod 0644 "$H"
	keep_on_upgrade "$H"
fi

log "apply with: service network reload && service firewall reload && service dnsmasq restart"
log "then: ACTION=ifup INTERFACE=$IOT_EGRESS_IF sh $H   (or ifup $IOT_EGRESS_IF)"
