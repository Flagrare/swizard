# SWizard

Native macOS app for installing Nintendo Switch games via USB — bypassing macOS Tahoe's broken MTP protocol.

SWizard speaks DBI's USB backend protocol directly over libusb, so you never have to fight with OpenMTP, Android File Transfer, or MTP again.

## Why

macOS Tahoe on Apple Silicon aggressively blocks MTP connections, making existing tools (OpenMTP, AFT) unreliable or non-functional for Switch game installation. SWizard implements DBI's custom binary protocol (`DBI0`) over raw USB bulk transfers — no MTP involved.

## Features

- **Drag-and-drop** `.nsp`, `.nsz`, `.xci`, `.xcz` files into the app
- **Split panel UI** — file queue on the left, color-coded activity log on the right
- **Transfer speed + ETA** — sliding-window speed calculation with real-time MB/s and time remaining
- **USB retry + stall recovery** — automatic retry on transient USB errors with endpoint stall recovery (`libusb_clear_halt`)
- **Session reconnect** — if the cable disconnects mid-transfer, SWizard reconnects and DBI resumes from where it left off
- **Structured logging** — debug/info/warning/error levels with color-coding and filtering
- **Device mutex** — USB polling pauses during active transfers to prevent libusb contention

## Architecture

Built with SOLID principles, TDD (87 tests), and clean design patterns:

```
┌─────────────────────────────────────────┐
│           SwiftUI Views                 │  Presentation
├─────────────────────────────────────────┤
│           AppState (@Observable)        │  State Management
├─────────────────────────────────────────┤
│     InstallationCoordinator             │  Orchestration (Mediator)
├──────────────┬──────────────────────────┤
│ DBIProtocol  │     FileServer           │  Domain (Command Pattern)
├──────────────┴──────────────────────────┤
│  RetryableTransport → USBTransport      │  Infrastructure (Decorator + Adapter)
├─────────────────────────────────────────┤
│           CLibUSB (libusb)              │  C Bridge
└─────────────────────────────────────────┘
```

**Design patterns**: Command, Strategy, Decorator, Adapter, Mediator, Observer, Policy Object, Sliding Window, Null Object

## Prerequisites

- macOS 15+ (Sonoma or later)
- [Homebrew](https://brew.sh): `brew install libusb`
- Xcode 16+ (Swift 6)
- Nintendo Switch with [DBI](https://github.com/rashevskyv/dbi) homebrew installed

## Build & Run

```bash
# Build
swift build

# Run tests (requires full Xcode, not just CLI tools)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Run the app
.build/debug/SWizard
```

## Build app bundle (recommended for local use)

If you cloned this repo and want a normal `.app` you can double-click:

1. Run `Build-SWizard.command` (builds `build/SWizard.app`)
2. Run `Install-SWizard.command` (copies app to `/Applications` and opens it)

After that, launch SWizard from Applications/Finder like any other macOS app.

## Releasing via GitHub Actions

You can publish a specific version from the **Release** workflow:

1. Open **Actions** -> **Release** -> **Run workflow**
2. Set `version` in `vMAJOR.MINOR.PATCH` format (example: `v1.2.3`) or prerelease format (example: `v0.1.0-alpha`)
3. Choose whether to mark it as `latest`

The workflow will:

- Create and push the tag if it does not exist yet
- Build a macOS arm64 `.app` bundle
- Bundle `SWizard.app` with `Install-SWizard.command`
- Upload `SWizard-<version>-macos-arm64.zip` to a GitHub Release

## Install from GitHub Release (no build required)

1. Download `SWizard-<version>-macos-arm64.zip` from the Release page
2. Unzip it and run `Install-SWizard.command`
3. Open SWizard from Applications
4. If macOS still blocks launch, open Terminal once and run:

```bash
xattr -dr com.apple.quarantine "/Applications/SWizard.app"
```

## Use with Nintendo Switch (DBI)

1. On the Switch, open DBI and select **Run DBI backend** (do not use MTP responder)
2. Connect the Switch to your Mac with a USB data cable
3. Launch SWizard from Applications
4. Wait for SWizard to show connected status
5. Drag `.nsp`, `.nsz`, `.xci`, or `.xcz` files into the drop area
6. Click **Install** and keep DBI open until transfer finishes

### Troubleshooting

- If SWizard does not detect the Switch, confirm DBI is in **Run DBI backend** mode
- If transfer is interrupted, keep SWizard open and reconnect USB; it will attempt to recover
- If launch is blocked by macOS security, run the quarantine removal command shown above

## DBI0 Protocol

SWizard implements the DBI0 binary protocol — the same protocol used by the official `dbibackend` Python script:

- **16-byte headers**: `DBI0` magic + command type + command ID + data size (all little-endian)
- **Commands**: LIST (file inventory), FILE_RANGE (chunk transfer), EXIT
- **Flow**: Switch drives the conversation — it requests file lists and byte ranges, Mac responds
- **Chunk size**: 1 MB per transfer

## Project Structure

```
Sources/
├── CLibUSB/           # libusb C bridge (module.modulemap)
├── USBTransport/      # libusb adapter, retry decorator, device monitor
├── DBIProtocol/       # DBI0 protocol: headers, commands, session state machine
├── Installer/         # Coordinator, file server, progress, speed calculator
└── SWizard/           # SwiftUI app: split panel, drop zone, log view
```

## License

MIT
