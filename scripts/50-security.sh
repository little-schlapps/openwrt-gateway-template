#!/bin/sh
# Monitoring & security tooling:
#  - nlbwmon: per-host traffic accounting, database on flash (daily commits)
#  - addrwatch: logs IP/MAC pairs seen on LAN + IoT (once per hour per pair)
#  - CrowdSec: syslog intake, dropbear parser, community blocklist enforced
#    by the nftables bouncer on the WAN devices
#  - Snort 3: IDS (alert only) on a low-volume segment, afpacket capture,
#    community rules, alerts to JSON + syslog
#  - SQM: cake prepared on the backup WAN, left disabled
. "$(dirname "$0")/../lib/common.sh"
load_config
require_pkg nlbwmon addrwatch crowdsec crowdsec-firewall-bouncer snort3 sqm-scripts
backup security /etc/config/nlbwmon /etc/config/addrwatch /etc/config/crowdsec \
	/etc/crowdsec/acquis.yaml /etc/config/system /etc/config/snort /etc/config/sqm

# ---------------------------------------------------------------- nlbwmon
uci set nlbwmon.@nlbwmon[0].database_directory='/etc/nlbwmon'
keep_on_upgrade /etc/nlbwmon/

# ---------------------------------------------------------------- addrwatch
uci -q delete addrwatch.@addrwatch[0].interface
uci add_list addrwatch.@addrwatch[0].interface="$LAN_IF"
uci add_list addrwatch.@addrwatch[0].interface="$IOT_IF"
uci set addrwatch.@addrwatch[0].enabled='1'
uci set addrwatch.@addrwatch[0].syslog='1'
uci set addrwatch.@addrwatch[0].hashsize='1024'
uci set addrwatch.@addrwatch[0].ratelimit='3600'

# ---------------------------------------------------------------- CrowdSec
# syslog intake: logd forwards a copy of the system log to CrowdSec
uci set system.@system[0].log_ip='127.0.0.1'
uci set system.@system[0].log_port='4242'
uci set system.@system[0].log_proto='udp'

# ---------------------------------------------------------------- Snort 3
uci set snort.snort.enabled='1'
uci set snort.snort.manual='0'
uci set snort.snort.mode='ids'
uci set snort.snort.method='afpacket'   # pcap delays alerts ~1 min on quiet links
uci set snort.snort.interface="$SNORT_IFACE"
uci set snort.snort.home_net="$SNORT_HOME_NET"
uci set snort.snort.logging='1'
uci set snort.snort.include='/etc/snort/local.lua'

# ---------------------------------------------------------------- SQM (prepared, disabled)
while uci -q delete sqm.@queue[0]; do :; done
uci set sqm.backup_wan=queue
uci set sqm.backup_wan.enabled='0'
uci set sqm.backup_wan.interface="$SQM_DEV"
uci set sqm.backup_wan.download="$SQM_DOWN_KBIT"
uci set sqm.backup_wan.upload="$SQM_UP_KBIT"
uci set sqm.backup_wan.qdisc='cake'
uci set sqm.backup_wan.script='piece_of_cake.qos'
uci set sqm.backup_wan.linklayer='none'

commit_uci nlbwmon addrwatch system snort sqm

if [ "$DRY_RUN" = 1 ]; then log "DRY-RUN: skipping file changes and service restarts"; exit 0; fi

# CrowdSec acquisition + parser + bouncer registration
cp "$TEMPLATE_DIR/files/crowdsec-acquis.yaml" /etc/crowdsec/acquis.yaml
cscli parsers install crowdsecurity/dropbear-logs >/dev/null 2>&1 || true
cscli bouncers delete openwrt-fw >/dev/null 2>&1 || true
KEY=$(cscli bouncers add openwrt-fw -o raw)
uci -q delete crowdsec.bouncer
uci set crowdsec.bouncer=bouncer
uci set crowdsec.bouncer.enabled='1'
uci set crowdsec.bouncer.ipv4='1'
uci set crowdsec.bouncer.ipv6='0'
uci set crowdsec.bouncer.api_url='http://127.0.0.1:8080'
uci set crowdsec.bouncer.api_key="$KEY"
uci set crowdsec.bouncer.interface="$CROWDSEC_WAN_DEVS"
uci set crowdsec.bouncer.deny_action='drop'
uci set crowdsec.bouncer.deny_log='1'
uci set crowdsec.bouncer.filter_input='1'
uci set crowdsec.bouncer.filter_forward='1'
uci commit crowdsec
unset KEY

# Snort include (syslog alerts) + rules ('snort-mgr update-rules' is broken in
# some package versions, so call the helper directly)
cp "$TEMPLATE_DIR/files/snort-local.lua" /etc/snort/local.lua
keep_on_upgrade /etc/snort/local.lua
/usr/bin/snort-rules

service log restart
service nlbwmon restart
service addrwatch enable; service addrwatch restart
service crowdsec restart; sleep 6
service crowdsec-firewall-bouncer enable; service crowdsec-firewall-bouncer restart
service snort enable; service snort restart
log "done. Snort needs ~30-60 s to load rules. Check: cscli decisions list -a | wc -l ; snort-mgr status"
