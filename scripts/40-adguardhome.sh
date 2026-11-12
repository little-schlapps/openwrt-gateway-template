#!/bin/sh
# AdGuard Home as the network DNS server, dnsmasq kept for DHCP and local names.
#  1. data dir on flash, admin UI on the LAN address
#  2. first-run setup via the API on a temporary DNS port (no DNS outage)
#  3. upstreams (DoH), bootstrap, local PTR/.lan via dnsmasq, filter refresh
#  4. cut over: dnsmasq -> port 54, AdGuard -> port 53, query log in RAM,
#     DHCP option 6 announces the router; automatic rollback on failure
. "$(dirname "$0")/../lib/common.sh"
load_config
require_pkg adguardhome curl
[ "$DRY_RUN" = 1 ] && { log "DRY-RUN not supported for this step (interactive setup)"; exit 0; }

LAN_ADDR="${LAN_IP%/*}"
IOT_ADDR="${IOT_IP%/*}"
Y=/etc/adguardhome/adguardhome.yaml
API="http://$LAN_ADDR:$AGH_WEB_PORT/control"

if [ -z "${AGH_PASSWORD:-}" ]; then
	printf 'AdGuard Home admin password: '; stty -echo 2>/dev/null; read -r AGH_PASSWORD; stty echo 2>/dev/null; echo
fi
[ ${#AGH_PASSWORD} -ge 12 ] || die "use a password of at least 12 characters"
case "$AGH_PASSWORD" in *'"'*|*'\'*) die 'the password must not contain " or \' ;; esac

backup adguard /etc/config/dhcp /etc/config/adguardhome "$Y"

# --- 1. persistent work dir (default /var/lib is RAM)
mkdir -p /etc/adguardhome/data
chown -R adguardhome:adguardhome /etc/adguardhome
uci set adguardhome.config.work_dir='/etc/adguardhome/data'
uci commit adguardhome
keep_on_upgrade /etc/adguardhome/
service adguardhome enable
service adguardhome restart
sleep 4

# --- 2. first-run wizard (only if not configured yet)
if [ ! -s "$Y" ] || ! grep -q '^users:' "$Y"; then
	curl -sf -H 'Content-Type: application/json' \
		-d "{\"web\":{\"ip\":\"$LAN_ADDR\",\"port\":$AGH_WEB_PORT},\"dns\":{\"ip\":\"127.0.0.1\",\"port\":5353},\"username\":\"admin\",\"password\":\"$AGH_PASSWORD\"}" \
		http://"$LAN_ADDR":3000/control/install/configure >/dev/null || die "first-run setup failed"
	sleep 3
fi

# --- 3. DNS settings + filter refresh
json_list() { printf '['; sep=''; for x in "$@"; do printf '%s"%s"' "$sep" "$x"; sep=','; done; printf ']'; }
# shellcheck disable=SC2086
up=$(json_list $AGH_UPSTREAMS "[/lan/]127.0.0.1:54")
# shellcheck disable=SC2086
boot=$(json_list $AGH_BOOTSTRAP)
curl -sf -u "admin:$AGH_PASSWORD" -H 'Content-Type: application/json' \
	-d "{\"upstream_dns\":$up,\"bootstrap_dns\":$boot,\"fallback_dns\":$boot,\"upstream_mode\":\"load_balance\",\"local_ptr_upstreams\":[\"127.0.0.1:54\"],\"use_private_ptr_resolvers\":true,\"resolve_clients\":true}" \
	"$API/dns_config" >/dev/null || die "dns_config failed (wrong password?)"
curl -sf -u "admin:$AGH_PASSWORD" -H 'Content-Type: application/json' -d '{"whitelist":false}' \
	"$API/filtering/refresh" >/dev/null

# --- 4. cut over with rollback
cp "$Y" /tmp/agh.pre-cutover.yaml
cp /etc/config/dhcp /tmp/dhcp.pre-cutover
service adguardhome stop
awk -v lan="$LAN_ADDR" -v iot="$IOT_ADDR" '
	BEGIN{d=0} /^dns:/{d=1} /^[a-z_]+:/ && !/^dns:/{d=0}
	d && /^  bind_hosts:/{print; print "    - 127.0.0.1"; print "    - " lan; print "    - " iot; skip=1; next}
	skip && /^    - /{next} {skip=0}
	d && /^  port: /{print "  port: 53"; next} {print}' "$Y" > /tmp/agh.new.yaml
sed -i -e 's/^  file_enabled: true$/  file_enabled: false/' /tmp/agh.new.yaml
cp /tmp/agh.new.yaml "$Y"; chown adguardhome:adguardhome "$Y"; chmod 600 "$Y"

uci set dhcp.@dnsmasq[0].port='54'
for i in "$LAN_IF:$LAN_ADDR" "$IOT_IF:$IOT_ADDR"; do
	sec=${i%%:*}; addr=${i#*:}
	uci -q del_list dhcp.$sec.dhcp_option="6,$addr"
	uci add_list dhcp.$sec.dhcp_option="6,$addr"
done
uci commit dhcp
service dnsmasq restart; sleep 2
service adguardhome start
for _ in 1 2 3 4 5 6 7 8 9 10; do nslookup -type=a openwrt.org "$LAN_ADDR" >/dev/null 2>&1 && break; sleep 2; done

if nslookup -type=a openwrt.org "$LAN_ADDR" 2>/dev/null | awk '/^Address/ && $2 !~ /:/ {f=1} END{exit !f}'; then
	log "AdGuard Home now serves DNS on :53 (admin UI http://$LAN_ADDR:$AGH_WEB_PORT)"
else
	log "DNS check failed - rolling back"
	service adguardhome stop
	cp /tmp/agh.pre-cutover.yaml "$Y"; cp /tmp/dhcp.pre-cutover /etc/config/dhcp
	service dnsmasq restart; service adguardhome start
	die "rolled back; dnsmasq serves DNS again"
fi
