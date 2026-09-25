#!/usr/bin/env bash
#
# Build macOS Active Workspace from source and install it.
#
#   curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh | bash
#
# Or, better, read it first:
#
#   curl -fsSLO https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh
#   less install.sh && bash install.sh
#
# Building on the machine it will run on is deliberate rather than a shortcut. There is no signed,
# notarized binary to download, and one fetched through a browser gets quarantined and refused by
# Gatekeeper. Compiled here, it never carries the quarantine flag and targets this Mac's CPU.
#
# Everything goes in your home directory, so nothing here needs sudo. Running it again updates.
# Remove it with uninstall.sh.

set -euo pipefail

TARBALL="https://github.com/mirairoad/macos-active-workspace/archive"
RAW="https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main"
REF="main"
PREFIX="$HOME/.local"
SKIP_DEPS=0
SOURCE=""

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$BOLD" "$OFF" "$*"; }
warn() { printf '%s==>%s %s\n' "$YELLOW" "$OFF" "$*" >&2; }
die()  { printf '%s==>%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

# A function rather than reading the header back out of $0, which is just "bash" when piped
usage() {
	cat <<EOF
Build macOS Active Workspace from source and install it.

Usage: bash install.sh [options]
       curl -fsSL $RAW/install.sh | bash -s -- [options]

Options:
  --ref <tag|branch>   what to build (default: main)
  --prefix <dir>       where the binary goes (default: ~/.local)
  --source <dir>       build a local checkout instead of fetching (for trying
                       changes before they are pushed)
  --skip-deps          do not check for build dependencies
  --help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--ref)       REF="${2:?--ref needs a tag or branch}"; shift 2 ;;
		--prefix)    PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
		--source)    SOURCE="${2:?--source needs a directory}"; shift 2 ;;
		--skip-deps) SKIP_DEPS=1; shift ;;
		--help|-h)   usage; exit 0 ;;
		*)           die "Unknown option: $1" ;;
	esac
done

[ "$(uname -s)" = "Darwin" ] || die "This is a macOS menu bar app; it will not build or run here."

# Run as root, the LaunchAgent would land in root's home and never start in your login session
[ "$(id -u)" -ne 0 ] || die "Run this as yourself, not with sudo. It only writes to your home directory."

# Must match uninstall.sh
LABEL="com.workspace.monitor"
BIN="$PREFIX/bin/workspace_monitor"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_DIR="$HOME/.release"
DOMAIN="gui/$(id -u)"

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
	MAIN="$SOURCE/src/main.swift"
	[ -f "$MAIN" ] || die "No src/main.swift in $SOURCE"
	say "Using the checkout in $SOURCE"
else
	MAIN="$WORK/src/main.swift"
	say "Fetching $REF"
	curl -fsSL "$TARBALL/$REF.tar.gz" | tar -xz -C "$WORK" --strip-components 1 \
		|| die "Could not fetch $REF from $TARBALL"
fi

say "Building"
xcrun swiftc -O -o "$WORK/workspace_monitor" "$MAIN" -framework AppKit \
	|| die "Build failed"

[ -x "$WORK/workspace_monitor" ] || die "Build reported success but produced no binary"

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

# Stopped before the binary is replaced, so a running copy never sees its file change under it
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

say "Installing to $BIN"
mkdir -p "$(dirname "$BIN")"
install -m 755 "$WORK/workspace_monitor" "$BIN"

# The old installer put the binary in ~/.release/bin. The LaunchAgent is rewritten below, so all
# that is left of it is the file. rmdir only removes the directories if nothing else is in them.
if [ -e "$LEGACY_DIR/bin/workspace_monitor" ]; then
	say "Removing the old install from $LEGACY_DIR"
	rm -f "$LEGACY_DIR/bin/workspace_monitor"
	rmdir "$LEGACY_DIR/bin" "$LEGACY_DIR" 2>/dev/null || true
fi

say "Adding it to your login items"
mkdir -p "$(dirname "$AGENT")"
# KeepAlive only on an unsuccessful exit: it comes back after a crash, but Quit in its menu
# (a clean exit) keeps it closed until the next login instead of relaunching it straight away.
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
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
[ "$started" -eq 1 ] || die "Installed, but launchd would not start it. Try: launchctl bootstrap $DOMAIN $AGENT"

printf '\n%smacOS Active Workspace is installed and running.%s\n' "$GREEN$BOLD" "$OFF"
printf '  %sLook for%s         the desktop number in your menu bar. Click it for color, size and font.\n' "$DIM" "$OFF"
printf '  %sIt starts%s        at every login. Quit from its menu closes it until the next one.\n' "$DIM" "$OFF"
printf '  %sUpdate by%s        running this again.\n' "$DIM" "$OFF"
printf '  %sUninstall with:%s  curl -fsSL %s/uninstall.sh | bash\n\n' "$DIM" "$OFF" "$RAW"
