#!/bin/sh
# mwan3: wan1 primary, wan2 backup, health-checked failover.
# The IoT subnet is excluded (it has its own policy routing, see 20-iot-segment.sh).
. "$(dirname "$0")/../lib/common.sh"
load_config
require_pkg mwan3
backup mwan3 /etc/config/mwan3

track() { for ip in $TRACK_IPS; do printf "\tlist track_ip '%s'\n" "$ip"; done; }

iface() {
	cat <<EOF

config interface '$1'
	option enabled '1'
	option family 'ipv4'
	option initial_state 'online'
	option track_method 'ping'
$(track)
	option reliability '2'
	option count '1'
	option size '56'
	option timeout '$2'
	option interval '5'
	option failure_interval '5'
	option recovery_interval '5'
	option down '3'
	option up '3'
EOF
}

conf=$(
	printf "config globals 'globals'\n\toption mmx_mask '0x3F00'\n"
	iface "$WAN1_IF" 2
	iface "$WAN2_IF" 3
	cat <<EOF

config member '${WAN1_IF}_m1'
	option interface '$WAN1_IF'
	option metric '1'
	option weight '1'

config member '${WAN2_IF}_m2'
	option interface '$WAN2_IF'
	option metric '2'
	option weight '1'

config policy 'primary_backup'
	list use_member '${WAN1_IF}_m1'
	list use_member '${WAN2_IF}_m2'
	option last_resort 'unreachable'

config rule 'iot_bypass'
	option family 'ipv4'
	option src_ip '$IOT_NET'
	option use_policy 'default'

config rule 'default_v4'
	option family 'ipv4'
	option dest_ip '0.0.0.0/0'
	option use_policy 'primary_backup'
EOF
)

if [ "$DRY_RUN" = 1 ]; then
	printf '%s\n' "$conf" | sed 's/^/    /'
	log "DRY-RUN: /etc/config/mwan3 not written"
	exit 0
fi

printf '%s\n' "$conf" > /etc/config/mwan3
service mwan3 enable
log "apply with: service mwan3 restart   (status: mwan3 status)"
log "test failover with tools/failover-drill.sh"
