#!/bin/sh
# Install the packages used by this template (OpenWrt 25.12, apk).
. "$(dirname "$0")/../lib/common.sh"
load_config

PKGS="
mwan3 luci-app-mwan3
adguardhome
nlbwmon luci-app-nlbwmon
addrwatch addrwatch-syslog
sqm-scripts luci-app-sqm
crowdsec crowdsec-firewall-bouncer luci-app-crowdsec-firewall-bouncer
snort3 coreutils-sort
curl tcpdump-mini
"

run apk update
# shellcheck disable=SC2086
run apk add $PKGS

# crowdsec and crowdsec-firewall-bouncer both ship /etc/config/crowdsec; the
# second install reports a conflict and leaves apk with "1 error". Keep the
# engine's file and let 50-security.sh add the bouncer section.
if [ "$DRY_RUN" != 1 ] && ! apk fix >/dev/null 2>&1; then
	cp /etc/config/crowdsec /tmp/crowdsec.keep
	apk fix --force-overwrite crowdsec-firewall-bouncer >/dev/null 2>&1
	cp /tmp/crowdsec.keep /etc/config/crowdsec
	log "resolved crowdsec/bouncer conffile conflict"
fi
log "done"
