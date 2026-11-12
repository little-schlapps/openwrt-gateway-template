#!/bin/sh
# LuCI extras:
#  - Status > Overview "Layer 3 Interfaces" section, placed above Network
#    and Port status (Port status is moved from 29_ to 32_)
#  - optional: luci-app-snort and the Argon theme from verified release files
. "$(dirname "$0")/../lib/common.sh"
load_config
D=/www/luci-static/resources/view/status/include

run cp "$TEMPLATE_DIR/files/27_l3interfaces.js" "$D/27_l3interfaces.js"
keep_on_upgrade "$D/27_l3interfaces.js"
# 29_ports.js belongs to luci-mod-status; an upgrade of that package restores it
# (delete 29_ports.js again if Port status then appears twice).
[ -f "$D/29_ports.js" ] && run mv "$D/29_ports.js" "$D/32_ports.js"

if [ -n "$LUCI_APP_SNORT_URL" ]; then
	run fetch_verified "$LUCI_APP_SNORT_URL" "$LUCI_APP_SNORT_SHA256" /tmp/luci-app-snort.apk
	run apk add --allow-untrusted /tmp/luci-app-snort.apk
fi

if [ -n "$ARGON_URL" ]; then
	# Review third-party themes before installing; prefer manual updates over
	# the theme's built-in self-updater.
	run fetch_verified "$ARGON_URL" "$ARGON_SHA256" /tmp/luci-theme-argon.apk
	run apk add --allow-untrusted /tmp/luci-theme-argon.apk
	run uci set luci.main.mediaurlbase='/luci-static/argon'
	commit_uci luci
fi

run rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
log "done - log out of LuCI and back in to load new menus/permissions"
