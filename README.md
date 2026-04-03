# Blimp

Blimp is a lightweight macOS cleaner focused on the two simplest maintenance tasks:

- release reclaimable memory pressure without asking for administrator access
- clear user cache and log folders from a small menu bar app

This package now includes both the menu bar app and the terminal CLI.

## Features

- macOS menu bar app with a small blimp status item
- live RAM usage tracking
- estimated reclaimable storage from `~/Library/Caches` and `~/Library/Logs`
- one-click memory pressure release
- one-click cache and log cleanup
- no background service or admin prompt required

## Requirements

- macOS 14 or later
- Xcode 15 or a Swift 5.9 toolchain

## Run The Menu Bar App

```bash
swift run BlimpApp
```

## Run The CLI

```bash
swift run blimp
```

## Build

```bash
swift build
```

## Project Layout

```text
Package.swift
Sources/Blimp/
Sources/BlimpCLI/
```
