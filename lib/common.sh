# Shared helpers for openwrt-gateway-template scripts (POSIX sh / busybox ash).
# shellcheck shell=sh

set -u

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-/root/cfg-backup}"
DRY_RUN="${DRY_RUN:-0}"

log()  { printf '[%s] %s\n' "$(basename "$0")" "$*"; }
die()  { log "ERROR: $*"; exit 1; }

load_config() {
	[ -f "$TEMPLATE_DIR/config.env" ] || die "config.env not found (copy config.env.example first)"
	# shellcheck disable=SC1091
	. "$TEMPLATE_DIR/config.env"
}

# backup <name> <file...>: copy files to a timestamped backup directory once per run
backup() {
	name="$1"; shift
	dir="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$name"
	mkdir -p "$dir"
	for f in "$@"; do [ -e "$f" ] && cp -a "$f" "$dir/"; done
	log "backup: $dir"
}

# run <cmd...>: execute, or just print in dry-run mode
run() {
	if [ "$DRY_RUN" = 1 ]; then log "DRY-RUN: $*"; else "$@"; fi
}

# commit_uci <config...>: show staged changes, then commit (or revert in dry-run)
commit_uci() {
	for c in "$@"; do
		changes="$(uci changes "$c")"
		[ -n "$changes" ] || continue
		printf '%s\n' "$changes" | sed 's/^/    /'
		if [ "$DRY_RUN" = 1 ]; then uci revert "$c"; else uci commit "$c"; fi
	done
}

# keep_on_upgrade <path>: make sysupgrade preserve a file or directory
keep_on_upgrade() {
	grep -qxF "$1" /etc/sysupgrade.conf 2>/dev/null || run sh -c "echo '$1' >> /etc/sysupgrade.conf"
}

# fetch_verified <url> <sha256> <dest>: download and verify a file
fetch_verified() {
	url="$1"; sum="$2"; dest="$3"
	[ -n "$url" ] && [ -n "$sum" ] || die "URL and SHA256 are both required for $dest"
	wget -q -O "$dest" "$url" || die "download failed: $url"
	echo "$sum  $dest" | sha256sum -c - >/dev/null 2>&1 || { rm -f "$dest"; die "checksum mismatch: $dest"; }
}

require_pkg() {
	for p in "$@"; do apk info -e "$p" >/dev/null 2>&1 || die "package $p not installed (run 00-packages.sh)"; done
}
