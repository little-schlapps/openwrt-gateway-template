#!/bin/sh
# Read-only health check of everything the template sets up.
. "$(dirname "$0")/../lib/common.sh"
load_config
LAN_ADDR="${LAN_IP%/*}"
IOT_ADDR="${IOT_IP%/*}"

ok()  { printf '  [ok]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; }
chk() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

echo "services"
for s in mwan3 adguardhome dnsmasq nlbwmon addrwatch crowdsec crowdsec-firewall-bouncer snort; do
	chk "$s running" "service $s running"
done
echo "routing"
chk "mwan3: $WAN1_IF online" "mwan3 interfaces | grep -q 'interface $WAN1_IF is online'"
chk "mwan3: $WAN2_IF online" "mwan3 interfaces | grep -q 'interface $WAN2_IF is online'"
chk "IoT policy rule present" "ip rule | grep -q 'from $IOT_NET lookup $IOT_ROUTE_TABLE'"
chk "IoT table has default route" "ip route show table $IOT_ROUTE_TABLE | grep -q '^default'"
chk "wan zone pins both WAN devices" "fw4 print | grep -q 'define wan_devices = .*$WAN1_DEV.*' && fw4 print | grep -q 'define wan_devices = .*$WAN2_DEV.*'"
echo "dns"
chk "AdGuard answers on LAN" "nslookup -type=a openwrt.org $LAN_ADDR | awk '/^Address/ && \$2 !~ /:/ {f=1} END{exit !f}'"
chk "ad domain blocked" "nslookup -type=a doubleclick.net $LAN_ADDR | grep -q '0.0.0.0'"
echo "egress"
printf '  LAN -> %s\n' "$(curl -s -m 8 --interface "$LAN_ADDR" https://ipinfo.io/org)"
printf '  IoT -> %s\n' "$(curl -s -m 8 --interface "$IOT_ADDR" https://ipinfo.io/org)"
echo "security"
printf '  CrowdSec decisions: %s\n' "$(cscli decisions list -a -o raw 2>/dev/null | tail -n +2 | wc -l)"
printf '  Snort alerts logged: %s\n' "$(wc -l < /var/log/alert_json.txt 2>/dev/null || echo 0)"
