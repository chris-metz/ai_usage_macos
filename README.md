# Pacemark

A macOS menu bar app that shows how much of your AI subscription limits you have used, and whether you are on pace.

## Install

```sh
brew install --cask chris-metz/tap/pacemark
```

Or download the DMG from the [latest release](https://github.com/chris-metz/pacemark/releases/latest) and drag Pacemark to Applications.

Requirements:

- macOS 27
- Claude Code 2.1.283 or later, installed and logged in

## Build from source

Requirements:

- macOS 27
- Xcode 27
- Claude Code 2.1.283 or later, installed and logged in

Then run:

```sh
./scripts/install.sh
```

It builds Pacemark, installs it to `/Applications/Pacemark.app` and launches it.
