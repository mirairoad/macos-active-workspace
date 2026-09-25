#!/usr/bin/env bash
#
# Remove Workit.
#
#   curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/uninstall.sh | bash
#
# Quits it and removes the app and the LaunchAgent that starts it at login, including anything
# left by the older installers that put a bare binary in ~/.release/bin or ~/.local/bin. Your
# settings are left alone unless you pass --purge.

set -euo pipefail

RAW="https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main"
DIR="$HOME/Applications"
PURGE=0

BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; OFF=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
die()  { printf '%s==>%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() {
	cat <<EOF
Remove Workit.

Usage: bash uninstall.sh [options]
       curl -fsSL $RAW/uninstall.sh | bash -s -- [options]

Options:
  --dir <dir>   where install.sh put Workit.app (default: ~/Applications)
  --purge       also delete the saved settings
  --help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--dir)     DIR="${2:?--dir needs a directory}"; shift 2 ;;
		--purge)   PURGE=1; shift ;;
		--help|-h) usage; exit 0 ;;
		*)         die "Unknown option: $1" ;;
	esac
done

[ "$(uname -s)" = "Darwin" ] || die "Workit is a macOS menu bar app; there is nothing to remove here."
[ "$(id -u)" -ne 0 ] || die "Run this as yourself, not with sudo. The install lives in your home directory."

# Must match install.sh
LABEL="com.mirairoad.workit"
APP="$DIR/Workit.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
LEGACY_LABEL="com.workspace.monitor"
LEGACY_AGENT="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_BINS=("$HOME/.release/bin/workspace_monitor" "$HOME/.local/bin/workspace_monitor")

say "Removing Workit"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
pkill -x Workit 2>/dev/null || true
[ -d "$APP" ] && rm -rf "$APP" && echo "$APP"
rm -fv "$AGENT" "$LEGACY_AGENT" "${LEGACY_BINS[@]}"
rmdir "$HOME/.release/bin" "$HOME/.release" 2>/dev/null || true

# Colors, size and font live under the old label, kept so settings survived the rename to Workit.
# The app's own domain only holds what macOS saves for it, like the menu bar position.
if [ "$PURGE" -eq 1 ]; then
	for domain in "$LEGACY_LABEL" "$LABEL"; do
		defaults delete "$domain" 2>/dev/null || true
		# defaults empties the file but leaves it behind
		rm -f "$HOME/Library/Preferences/$domain.plist"
	done
	printf '%sDone.%s Settings deleted too.\n' "$GREEN$BOLD" "$OFF"
else
	printf '%sDone.%s Your settings were left alone.\n' "$GREEN$BOLD" "$OFF"
	printf 'Delete them with: curl -fsSL %s/uninstall.sh | bash -s -- --purge\n' "$RAW"
fi
