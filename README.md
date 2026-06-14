<div align="center">

# 🪂 Blimp

### A fast, cross-platform terminal system janitor

Clean RAM, wipe caches, and snipe the bloated files you forgot you had —
all from a snappy keyboard-driven TUI.

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-4f8ef7)](#-platform-support)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](#-license)

```
 > /snipe_
────────────────────────────────────────────────────────────
 SNIPER — 12 groups  ↑↓:navigate  SPACE:select  A:all  ESC:back
────────────────────────────────────────────────────────────
 [x] [DMG] DMG Installers              2.4 GB │ iOS Backups
 [ ] [XCD] Xcode DerivedData          18.1 GB │ ─────────────────
 [x] [OLD] Old Downloads (60d+)        910 MB │   iPhone — Mathieu   7.2 GB
 [ ] [BCK] iOS Backups                 7.2 GB │   iPad  — Studio     4.0 GB
────────────────────────────────────────────────────────────
 CPU[███░░░░░░░]28%  RAM[██████░░░░]61%  SSD 412/994GB
```

</div>

---

## ✨ Features

- **🧹 One-shot cleanup** — free inactive RAM and wipe caches/logs in a single command.
- **🎯 Smart file sniper** — `/snipe` scans your system for the heavy stuff you probably don't need (stale downloads, disk images, build artifacts, simulators, backups) and groups them so you can **select a whole group and delete it at once**.
- **📊 Live system bars** — CPU, RAM and disk usage update in real time, color-coded green → yellow → red.
- **🔍 Disk breakdown** — `/scan` shows where your space actually went, with inline bars.
- **🧠 Top processes** — `/top` lists the biggest memory hogs.
- **⌨️ Pure keyboard TUI** — tab-completion, command history, arrow-key navigation, plus mouse click support where the terminal allows it.
- **🎨 Hot-reloadable config** — colors, command names and bar glyphs live in a JSON file that reloads while running.
- **🖥️ Cross-platform** — one codebase, native system APIs on each OS.

---

## 🚀 Installation

### Build from source

Requires [Swift 5.9+](https://www.swift.org/install/).

```bash
git clone https://github.com/MathieuDvv/Blimp-cli.git
cd Blimp-cli
swift build -c release
```

The binary lands at `.build/release/blimp`. Drop it somewhere on your `PATH`:

```bash
# macOS / Linux
cp .build/release/blimp ~/.local/bin/blimp     # make sure ~/.local/bin is on $PATH

# Windows (PowerShell)
copy .build\release\blimp.exe $Env:USERPROFILE\bin\blimp.exe
```

Then just run:

```bash
blimp
```

---

## ⌨️ Commands

### Universal (macOS · Linux · Windows)

| Command         | Description                                    |
| --------------- | ---------------------------------------------- |
| `/clean`        | Full sweep — free RAM **and** wipe caches/logs |
| `/clean ram`    | Purge inactive memory pages                    |
| `/clean cache`  | Wipe caches & logs (platform-aware targets)    |
| `/snipe`        | Interactive large-file sniper (see below)      |
| `/scan`         | Disk-usage breakdown with bars                 |
| `/top`          | Top processes by memory                        |
| `/trash`        | Empty the Trash / Recycle Bin                  |
| `/brew`         | Run `brew cleanup --prune=all` (macOS/Linux)   |
| `/config`       | Open the hot-reloadable config file            |
| `/help`         | Show the command matrix                        |
| `/quit`         | Exit (or press `Esc` / `Ctrl-C`)               |

### macOS-only

| Command             | Description                                            |
| ------------------- | ----------------------------------------------------- |
| `/xcode`            | Nuke Xcode `DerivedData`                               |
| `/apps`             | List all applications                                 |
| `/apps installed`   | List user-installed (non-Apple) apps                  |
| `/uninstall <name>` | Deep-uninstall an app **and** its support/cache files |
| `/ui`               | Launch the companion menu-bar UI                      |
| `/ui autostart`     | Toggle launch-at-login for the menu-bar UI            |
| `/ui quit`          | Dismiss the menu-bar UI                                |

---

## 🎯 The Sniper

`/snipe` is the headline feature. It scans for the categories of files that
quietly eat your disk, **groups** them, and lets you delete entire groups in
one keystroke.

```
 SPACE   toggle the highlighted group
 ↑ / ↓   move between groups
 A       select / deselect all
 ENTER   delete selected groups (asks for confirmation)
 ESC     back out
```

The right pane previews every file in the highlighted group with its size, so
you always see exactly what's about to go.

**What it hunts for:**

| Everywhere                     | macOS                          | Linux                                   | Windows                          |
| ------------------------------ | ------------------------------ | --------------------------------------- | -------------------------------- |
| Archives (`.zip`, `.tar`, …)   | DMG & PKG installers           | npm / yarn / pip / gradle / cargo cache | `%TEMP%`                         |
| Old downloads (60+ days)       | Xcode DerivedData & Archives   | Go module cache                         | npm / pip / yarn caches          |
| Large videos (>100 MB)         | iOS Simulators & Backups       | Big `~/.cache` dirs (>50 MB)            | gradle / maven repos             |
|                                | Homebrew cache, logs, Trash    | Trash, your `/tmp` files                |                                  |

> Deletions try a permanent `rm` first and fall back to moving items to the
> Trash if that fails. Always glance at the preview pane before hitting Enter.

---

## 🖥️ Platform support

Blimp talks to each OS through its native APIs — no shelling out for stats:

| Subsystem    | macOS                       | Linux                      | Windows                          |
| ------------ | --------------------------- | -------------------------- | -------------------------------- |
| **Memory**   | Mach `vm_statistics64`      | `/proc/meminfo`            | `GlobalMemoryStatusEx`           |
| **CPU**      | `host_cpu_load_info`        | `/proc/stat`               | `GetSystemTimes`                 |
| **Terminal** | POSIX `termios` / `poll`    | POSIX `termios` / `poll`   | `WinSDK` console + VT sequences  |
| **Disk**     | Foundation volume keys      | Foundation volume keys     | Foundation volume keys           |

All OS-specific paths (home, cache, logs, temp, trash) are centralized in
`Platform.swift`, and platform-only commands are compiled out where they don't
apply.

---

## ⚙️ Configuration

On first run Blimp writes a config file you can edit live:

```
~/.config/blimp/config.json
```

It's hot-reloaded — save the file and the TUI updates instantly. You can
remap command strings, change the ANSI colors, and swap the progress-bar
glyphs:

```json
{
  "colors": {
    "topBarBg": "#1a1a2e",
    "accent":   "#4f8ef7"
  },
  "misc": {
    "barFill":  "█",
    "barEmpty": "░"
  }
}
```

Run `/config` inside Blimp to open it directly.

---

## 🏗️ Project structure

```
Sources/blimp/
├── blimp.swift         # Entry point, TUI loop, command routing, rendering
├── Platform.swift      # Cross-platform paths & OS detection
├── Terminal.swift      # Raw mode, key input, window size (per-OS)
├── SystemMonitor.swift # RAM / CPU / storage stats & clean actions (per-OS)
├── DiskAnalyzer.swift  # Snipe groups & disk-usage scanning (per-OS)
└── AppManager.swift    # App listing & deep uninstall (macOS-only)
```

---

## 📄 License

MIT — see [LICENSE](LICENSE).

<div align="center">
<sub>Built with Swift · Enjoy the flight 🪂</sub>
</div>
