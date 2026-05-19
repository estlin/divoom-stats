# Divoom Stats (macOS)

A menu-bar Mac app that pushes real-time CPU / GPU / RAM / disk usage and
temperatures to a paired **Divoom Minitoo** display over Bluetooth Classic
(SPP / RFCOMM).

Apple Silicon only. macOS 12+. No sudo required.

## How it works

- **Stats**
  - CPU%  — Mach `host_statistics` (delta between samples)
  - RAM   — Mach `host_statistics64` (Activity Monitor's "used" definition)
  - Disk  — `statfs("/")`
  - GPU%, CPU temp, GPU temp — bundled [`macmon`](https://github.com/vladkens/macmon) subprocess (reads the private `IOReport` framework, no sudo)
- **Renderer** — CoreGraphics draws a 128×128 RGB888 frame, 4-quadrant layout: CPU top-left, GPU top-right, RAM bottom-left, DISK bottom-right. Identical frames are skipped so the Bluetooth radio stays idle when stats don't change.
- **Protocol** — Per [alvinunreal/divoom-minitoo-osx PROTOCOL.md](https://github.com/alvinunreal/divoom-minitoo-osx/blob/main/PROTOCOL.md). Frame envelope `0x01 <len LE16> <cmd> <body> <chk LE16> 0x02`, image command `0x8b` split into a start packet + 256-byte chunks. Pixels compressed with Zstandard (`window_log=17`, level 19).
- **Transport** — `IOBluetooth` RFCOMM channel 1 to the first paired device whose name matches `(?i)divoom|minitoo`.
- **Settings** — refresh interval (1/2/5/10/30s) and temperature unit (°C/°F), persisted in `UserDefaults`.

## Running a prebuilt `.app`

Download the latest release from **https://github.com/estlin/divoom-stats/releases** — `Divoom Stats.app.zip` bundles `libzstd` and `macmon` inside it, so **no Homebrew or other dependencies needed**.

1. Unzip and move `Divoom Stats.app` wherever you like (e.g. `/Applications`).
2. First-launch dance for ad-hoc-signed apps: macOS won't open it via double-click because the bundle isn't notarized. Either:
   - **Right-click → Open** (then click Open in the warning dialog), or
   - Run `xattr -d com.apple.quarantine "Divoom Stats.app"` once, then double-click.
3. Pair your Minitoo from System Settings → Bluetooth (the app auto-discovers it; no MAC needed).
4. Approve the Bluetooth permission prompt on first run.
5. A 📊 icon appears in the menu bar. Open it for status, Settings…, Pause, and Quit.

## Known behavior: last frame stays on quit

When you quit the menu-bar app the Minitoo keeps showing whichever stats frame arrived last — the app doesn't send a "shut down" command on quit. The obvious candidate (`Channel/SetClockSelectId`) locks the firmware into "show stored clock face" mode and from that point silently drops all future `0x8b` image frames until the device is power-cycled, which would make the next launch appear broken (see commit [`5bb8486`](https://github.com/estlin/divoom-stats/commit/5bb8486)). Leaving the last frame on screen is the lesser evil.

**To get back to the device's normal menu after quitting, click the joystick on the Minitoo.** That brings up the device's built-in mode/channel UI and you can navigate away from the frozen stats frame.

## Building from source

To compile the source yourself you do need Homebrew (with `libzstd` headers and the `macmon` binary), but only at build time — the produced `.app` is self-contained.

Requires **arm64 Homebrew** at `/opt/homebrew`. If you only have Intel Homebrew at `/usr/local`, install the arm64 one alongside:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Follow the post-install instructions to add /opt/homebrew/bin to your PATH.
```

Then:

```bash
/opt/homebrew/bin/brew install macmon zstd
./build-app.sh
open "Divoom Stats.app"
```

## Project layout

```
Sources/
├── CZstd/                          system-library wrapper for libzstd
└── DivoomStats/
    ├── main.swift                  menu-bar app + timer loop
    ├── Settings/
    │   ├── Settings.swift          UserDefaults-backed prefs
    │   └── SettingsWindow.swift    NSWindow with refresh + unit popups
    ├── Stats/
    │   ├── Stats.swift             shared struct
    │   ├── CPUSampler.swift        host_statistics
    │   ├── MemorySampler.swift     host_statistics64
    │   ├── DiskSampler.swift       statfs
    │   └── MacmonSampler.swift     macmon subprocess
    ├── Render/
    │   └── FrameRenderer.swift     CoreGraphics 128×128 → RGB888
    ├── Protocol/
    │   ├── Zstd.swift              libzstd wrapper (window_log=17)
    │   └── MinitooProtocol.swift   envelope + 0x8b + 256-byte chunking
    └── Bluetooth/
        └── MinitooConnection.swift IOBluetooth RFCOMM auto-discover + write
Tools/
└── MakeIcon.swift                  generates AppIcon.iconset → AppIcon.icns
```

## Customizing

- **Layout** — edit `FrameRenderer.swift`. Stats arrive in a `Stats` struct; render anything you like to the 128×128 `CGContext`.
- **Device match** — `namePattern` in `MinitooConnection.swift` is a regex; tighten if you have multiple Divoom devices paired.
- **Icon** — `Tools/MakeIcon.swift` draws the app icon programmatically. Edit the colors/loads there and `build-app.sh` will regenerate `Resources/AppIcon.icns` on the next build (delete the cached `.icns` to force).

## Changelog

- **[v0.2.2](https://github.com/estlin/divoom-stats/releases/tag/v0.2.2)** — Smaller frames (zstd level 19), skip unchanged frames during idle, crisper headers and larger temp/size text.
- **[v0.2.1](https://github.com/estlin/divoom-stats/releases/tag/v0.2.1)** — Docs: README now documents the "last frame stays on quit" behavior and how the device joystick brings back the Minitoo's menu.
- **[v0.2](https://github.com/estlin/divoom-stats/releases/tag/v0.2)** — Fix: display no longer freezes on subsequent launches (RFCOMM open on the main thread, preserve the existing ACL).
- **[v0.1](https://github.com/estlin/divoom-stats/releases/tag/v0.1)** — Initial release.

## Acknowledgements

Wire-protocol details, packet shapes, and the RFCOMM-channel-1 hint come from [alvinunreal/divoom-minitoo-osx](https://github.com/alvinunreal/divoom-minitoo-osx). This project ports the protocol to a self-contained Swift app and adds Mac system monitoring.
