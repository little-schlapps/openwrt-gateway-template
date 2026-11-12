#!/bin/sh
# Disable IPv6 at configuration level (for networks that do not use it):
# no ULA prefix, no prefix delegation, no IPv6 on the uplinks, no RA/DHCPv6/NDP,
# odhcpd stopped, AdGuard Home stops answering AAAA.
#
# Deliberately NOT done: sysctl net.ipv6.conf.all.disable_ipv6=1 - it removes ::1,
# which uhttpd/AdGuard listen on, and gains little once nothing is advertised.
. "$(dirname "$0")/../lib/common.sh"
load_config
Y=/etc/adguardhome/adguardhome.yaml
backup noipv6 /etc/config/network /etc/config/dhcp "$Y"

uci -q delete network.globals.ula_prefix
for i in "$LAN_IF" "$IOT_IF"; do
	uci -q delete network.$i.ip6assign
	uci set network.$i.delegate='0'
	uci set dhcp.$i.ra='disabled'
	uci set dhcp.$i.dhcpv6='disabled'
	uci set dhcp.$i.ndp='disabled'
	uci -q delete dhcp.$i.ra_flags
	uci -q delete dhcp.$i.ra_preference
done
uci set network.$WAN1_IF.ipv6='0'
uci set network.$WAN2_IF.ipv6='0'
commit_uci network dhcp

[ "$DRY_RUN" = 1 ] && exit 0

if [ -f "$Y" ]; then
	service adguardhome stop
	# drop IPv6 global/ULA listen addresses (they disappear) and AAAA answers
	sed -i -E '/^    - (fd|fc)[0-9a-f:]+$/d' "$Y"
	sed -i 's/^  aaaa_disabled: false$/  aaaa_disabled: true/' "$Y"
	service adguardhome start
fi
service odhcpd stop; service odhcpd disable
log "apply with: service network reload && service dnsmasq restart"
log "an old ULA address may linger as 'deprecated' until it expires (or: ip -6 addr flush scope global)"
