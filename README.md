# macOS Show Active Workspace

A lightweight menubar utility that displays your current macOS workspace number with a background matching your system's accent color. Perfect for users who want a visual indicator of their current workspace that seamlessly integrates with macOS's design language.

![Workspace 1](screenshots/workspace1.png) ![Workspace 2](screenshots/workspace2.png)

## Features
- Shows current workspace number in the menu bar
- Automatically matches your system accent color
- Pick a color (accent, transparent, gray, red, orange, yellow, green, blue, purple, pink) size (small, medium, large) and font (typeface, text size, bold) from the menu bar item
- Updates instantly when switching spaces
- Minimal resource usage
- Native macOS look and feel

## Installing

```sh
curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh | bash
```

That fetches the source, builds it, installs the binary to `~/.local/bin` and a
LaunchAgent that starts it at every login, and starts it. Everything goes in your
home directory, so it never asks for `sudo`. Running it again updates to the
latest version, and an install from the old `~/.release` script is moved over.

If you would rather read a script before running it - and you should - fetch it
first:

```sh
curl -fsSLO https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh
less install.sh && bash install.sh
```

It builds from source rather than downloading a binary, and that is deliberate.
There is no signed, notarized build to download, and a binary fetched through a
browser gets quarantined and refused by Gatekeeper. Built on your Mac, it never
carries the quarantine flag and is compiled for your CPU.

The only build dependency is the Swift compiler from Apple's Command Line Tools.
The script checks for it first and, if it is missing, prints the one command that
installs it (`xcode-select --install`). It will not run it for you: a script
piped from the internet is the last thing that should be making that decision
quietly.

Options go after `bash -s --` when piping, or straight after `bash install.sh`:
`--ref <tag|branch>` to build something other than `main`, `--prefix <dir>` to
put the binary somewhere other than `~/.local`, `--source <dir>` to build a
local checkout instead of fetching, and `--skip-deps`.

## Customization

Click the workspace number in the menu bar:
- **Color**: accent (default), transparent (number only, adapts to light/dark menu bar) or a fixed color
- **Size**: small, medium or large (default)
- **Font**: typeface (system, rounded, monospaced or serif), text size (small, medium or large, relative to the box) and bold

Settings are saved and restored on restart.

## Uninstalling

```sh
curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/uninstall.sh | bash
```

That stops it and removes the binary and the LaunchAgent, including a copy left
by the old `~/.release` installer. Your settings are left alone;
pass `--purge` (`| bash -s -- --purge`) to delete them too. If you installed with
`--prefix`, pass the same `--prefix` here.

## Development

The application is built using Swift and AppKit. Main components:
- Status bar integration
- Workspace monitoring
- Dynamic updates

Build and run it without installing:

```sh
swiftc -O -o workspace_monitor src/main.swift -framework AppKit && ./workspace_monitor
```
