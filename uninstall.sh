#!/usr/bin/env bash
#
# Remove macOS Active Workspace.
#
#   curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/uninstall.sh | bash
#
# Stops it and removes the binary and the LaunchAgent that starts it at login, including a copy
# left by the old ~/.release installer. Your settings are left alone unless you
# pass --purge.

set -euo pipefail

RAW="https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main"
PREFIX="$HOME/.local"
PURGE=0

BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; OFF=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
die()  { printf '%s==>%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() {
	cat <<EOF
Remove macOS Active Workspace.

Usage: bash uninstall.sh [options]
       curl -fsSL $RAW/uninstall.sh | bash -s -- [options]

Options:
  --prefix <dir>   where install.sh put the binary (default: ~/.local)
  --purge          also delete the saved settings
  --help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--prefix)  PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
		--purge)   PURGE=1; shift ;;
		--help|-h) usage; exit 0 ;;
		*)         die "Unknown option: $1" ;;
	esac
done

[ "$(uname -s)" = "Darwin" ] || die "This is a macOS menu bar app; there is nothing to remove here."
[ "$(id -u)" -ne 0 ] || die "Run this as yourself, not with sudo. The install lives in your home directory."

# Must match install.sh
LABEL="com.workspace.monitor"
BIN="$PREFIX/bin/workspace_monitor"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_DIR="$HOME/.release"
DOMAIN="gui/$(id -u)"

say "Removing macOS Active Workspace"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -fv "$BIN" "$AGENT" "$LEGACY_DIR/bin/workspace_monitor"
rmdir "$LEGACY_DIR/bin" "$LEGACY_DIR" 2>/dev/null || true

if [ "$PURGE" -eq 1 ]; then
	defaults delete "$LABEL" 2>/dev/null || true
	# defaults empties the file but leaves it behind
	rm -f "$HOME/Library/Preferences/$LABEL.plist"
	printf '%sDone.%s Settings deleted too.\n' "$GREEN$BOLD" "$OFF"
else
	printf '%sDone.%s Your settings were left alone.\n' "$GREEN$BOLD" "$OFF"
	printf 'Delete them with: defaults delete %s\n' "$LABEL"
fi
