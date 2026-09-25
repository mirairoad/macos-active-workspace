# Workit

A lightweight menu bar app that shows which macOS desktop (Space) you are on, as a number in a
rounded square that matches your accent color, or any color you pick.

![Workspace 1](screenshots/workspace1.png) ![Workspace 2](screenshots/workspace2.png)

## Features
- Shows the current desktop number in the menu bar
- Updates instantly when switching desktops
- With more than one display, desktops are numbered per display, next to an outlined display number: `[2] 1` is the first desktop on display 2
- Pick a color (accent, transparent, gray, red, orange, yellow, green, blue, purple, pink), size (small, medium, large) and font (typeface, text size, bold) from its menu
- The same size on every display, whatever the menu bar height
- Menu bar only: no Dock icon, minimal resource usage

## Installing

```sh
curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh | bash
```

That fetches the source, builds `Workit.app` into `~/Applications`, adds it to
your login items, and starts it. Everything goes in your home directory, so it
never asks for `sudo`. Running it again updates to the latest version, and an
install from the older scripts (a bare `workspace_monitor` in `~/.release/bin`
or `~/.local/bin`) is moved over, settings included.

If you would rather read a script before running it - and you should - fetch it
first:

```sh
curl -fsSLO https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/install.sh
less install.sh && bash install.sh
```

It builds from source rather than downloading an app, and that is deliberate.
There is no signed, notarized build to download, and an app fetched through a
browser gets quarantined and refused by Gatekeeper. Built on your Mac, it never
carries the quarantine flag and is compiled for your CPU.

The only build dependency is the Swift compiler from Apple's Command Line Tools.
The script checks for it first and, if it is missing, prints the one command that
installs it (`xcode-select --install`). It will not run it for you: a script
piped from the internet is the last thing that should be making that decision
quietly.

Options go after `bash -s --` when piping, or straight after `bash install.sh`:
`--ref <tag|branch>` to build something other than `main`, `--dir <dir>` to put
the app somewhere other than `~/Applications`, `--source <dir>` to build a local
checkout instead of fetching, and `--skip-deps`.

## Using it

Click the number in the menu bar:
- **Color**: accent (default), transparent (number only, adapts to light/dark menu bar) or a fixed color
- **Size**: small, medium or large (default)
- **Font**: typeface (system, rounded, monospaced or serif), text size (small, medium or large, relative to the box) and bold
- **Quit Workit**: closes it until you open it again or next log in

Settings are saved and restored on restart. To bring it back after quitting, open
Workit from Spotlight, Launchpad or `~/Applications`.

## Uninstalling

```sh
curl -fsSL https://raw.githubusercontent.com/mirairoad/macos-active-workspace/main/uninstall.sh | bash
```

That quits it and removes the app and its login item, including anything the
older scripts left behind. Your settings are left alone; pass `--purge`
(`| bash -s -- --purge`) to delete them too. If you installed with `--dir`, pass
the same `--dir` here.

## Development

Workit is a single Swift file, `src/main.swift`, built with AppKit. Build the app
and run it without installing:

```sh
bash scripts/build-app.sh && open build/Workit.app
```

Only one copy runs at a time, so quit the installed one first.

The icon is drawn in code; after editing `assets/make-icon.swift`, regenerate it
with `swift assets/make-icon.swift`.
