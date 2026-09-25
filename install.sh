#!/usr/bin/env bash
#
# Build Workit from source and install it.
#
#   curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh | bash
#
# Or, better, read it first:
#
#   curl -fsSLO https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh
#   less install.sh && bash install.sh
#
# Building on the machine it will run on is deliberate rather than a shortcut. There is no signed,
# notarized app to download, and one fetched through a browser gets quarantined and refused by
# Gatekeeper. Built here, it never carries the quarantine flag and targets this Mac's CPU.
#
# Everything goes in your home directory, so nothing here needs sudo. Running it again updates.
# Remove it with uninstall.sh.

set -euo pipefail

TARBALL="https://github.com/mirairoad/macos-active-workspace/archive"
RAW="https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main"
REF="main"
DIR="$HOME/Applications"
SKIP_DEPS=0
SOURCE=""

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
warn() { printf '%s==>%s %s\n' "$YELLOW" "$OFF" "$*" >&2; }
die()  { printf '%s==>%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

# A function rather than reading the header back out of $0, which is just "bash" when piped
usage() {
	cat <<EOF
Build Workit from source and install it.

Usage: bash install.sh [options]
       curl -fsSL $RAW/install.sh | bash -s -- [options]

Options:
  --ref <tag|branch>   what to build (default: main)
  --dir <dir>          where Workit.app goes (default: ~/Applications)
  --source <dir>       build a local checkout instead of fetching (for trying
                       changes before they are pushed)
  --skip-deps          do not check for build dependencies
  --help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--ref)       REF="${2:?--ref needs a tag or branch}"; shift 2 ;;
		--dir)       DIR="${2:?--dir needs a directory}"; shift 2 ;;
		--source)    SOURCE="${2:?--source needs a directory}"; shift 2 ;;
		--skip-deps) SKIP_DEPS=1; shift ;;
		--help|-h)   usage; exit 0 ;;
		*)           die "Unknown option: $1" ;;
	esac
done

[ "$(uname -s)" = "Darwin" ] || die "Workit is a macOS menu bar app; it will not build or run here."

# Run as root, the LaunchAgent would land in root's home and never start in your login session
[ "$(id -u)" -ne 0 ] || die "Run this as yourself, not with sudo. It only writes to your home directory."

# Must match uninstall.sh
LABEL="com.mirairoad.workit"
APP="$DIR/Workit.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# Earlier installs: a bare binary in ~/.release/bin (the first installer) or ~/.local/bin, started
# by a LaunchAgent under the old label
LEGACY_LABEL="com.workspace.monitor"
LEGACY_AGENT="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_BINS=("$HOME/.release/bin/workspace_monitor" "$HOME/.local/bin/workspace_monitor")

# ---------------------------------------------------------------------------
# Build dependencies
# ---------------------------------------------------------------------------

check_dependencies() {
	# The Swift compiler and the macOS SDK both come with Apple's Command Line Tools, or with Xcode.
	# xcode-select goes first: calling a developer tool shim without them pops up an install dialog.
	if xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; then
		say "Build dependencies: ${GREEN}all present${OFF}"
		return
	fi

	warn "Missing build dependency: the Swift compiler, from Apple's Command Line Tools"
	printf '\n  xcode-select --install\n\n'
	# Not run automatically: installing system software is the user's decision, and a script
	# piped from the internet is the last thing that should be making it silently.
	die "Install those and run this again, or pass --skip-deps if you know better."
}

[ "$SKIP_DEPS" -eq 1 ] || check_dependencies

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "$SOURCE" ]; then
	ROOT="$SOURCE"
	[ -f "$ROOT/scripts/build-app.sh" ] || die "No scripts/build-app.sh in $SOURCE"
	say "Using the checkout in $SOURCE"
else
	ROOT="$WORK/src"
	mkdir -p "$ROOT"
	say "Fetching $REF"
	curl -fsSL "$TARBALL/$REF.tar.gz" | tar -xz -C "$ROOT" --strip-components 1 \
		|| die "Could not fetch $REF from $TARBALL"
fi

say "Building"
bash "$ROOT/scripts/build-app.sh" "$WORK/build" >/dev/null || die "Build failed"
[ -x "$WORK/build/Workit.app/Contents/MacOS/Workit" ] || die "Build reported success but produced no app"

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

# Stopped before the app is replaced, so a running copy never sees its files change under it.
# pkill catches a copy opened from Spotlight or Finder, which launchd does not know about.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
pkill -x Workit 2>/dev/null || true

say "Installing $APP"
mkdir -p "$DIR"
rm -rf "$APP"
ditto "$WORK/build/Workit.app" "$APP"

# So Spotlight, Launchpad and `open -a Workit` know about it straight away
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	-f "$APP" 2>/dev/null || true

# rmdir only removes ~/.release if nothing else is in it; ~/.local is shared with other tools
for bin in "${LEGACY_BINS[@]}"; do
	if [ -e "$bin" ]; then
		say "Removing the old install at $bin"
		rm -f "$bin"
	fi
done
rm -f "$LEGACY_AGENT"
rmdir "$HOME/.release/bin" "$HOME/.release" 2>/dev/null || true

say "Adding it to your login items"
mkdir -p "$(dirname "$AGENT")"
# KeepAlive only on an unsuccessful exit: it comes back after a crash, but Quit in its menu
# (a clean exit) keeps it closed until you open it again or log in.
# AssociatedBundleIdentifiers makes System Settings > Login Items show it as Workit, with its icon.
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/Workit</string>
    </array>
    <key>AssociatedBundleIdentifiers</key>
    <string>$LABEL</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
</dict>
</plist>
EOF
chmod 644 "$AGENT"

# bootout returns before launchd has fully let go of the label, and bootstrapping in that window
# fails with an I/O error, so give it a few tries.
say "Starting it"
started=0
for _ in 1 2 3 4 5; do
	if launchctl bootstrap "$DOMAIN" "$AGENT" 2>/dev/null; then
		started=1
		break
	fi
	sleep 1
done
[ "$started" -eq 1 ] || die "Installed, but launchd would not start it. Try: open \"$APP\""

printf '\n%sWorkit is installed and running.%s\n' "$GREEN$BOLD" "$OFF"
printf '  %sLook for%s         the desktop number in your menu bar. Click it for color, size and font.\n' "$DIM" "$OFF"
printf '  %sIt starts%s        at every login. After Quit, open it again from Spotlight or Launchpad.\n' "$DIM" "$OFF"
printf '  %sUpdate by%s        running this again.\n' "$DIM" "$OFF"
printf '  %sUninstall with:%s  curl -fsSL %s/uninstall.sh | bash\n\n' "$DIM" "$OFF" "$RAW"
