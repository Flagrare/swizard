
<table>
  <tr>
    <td width="84" valign="middle">
      <img src="Assets/logo.png" alt="SWizard logo" width="72" />
    </td>
    <td valign="middle">
      <h1>SWizard</h1>
    </td>
  </tr>
</table>

The most complete and reliable macOS app for installing Nintendo Switch games — **3 transport modes**, works on Apple Silicon + macOS Tahoe where other tools fail.

![SWizard](./Assets/swizard.gif)

## Why

macOS Tahoe on Apple Silicon breaks MTP connections, making OpenMTP and Android File Transfer unreliable or non-functional. SWizard solves this with three different transport modes — at least one will work regardless of your setup.

## Transport Modes

### MTP (default)
- Uses **libmtp** with privileged kernel driver detach to bypass macOS Tahoe's MTP restrictions
- On your Switch: DBI → **Run MTP responder**
- SWizard prompts for admin password once (required to claim USB from macOS)
- First working MTP solution on Apple Silicon + macOS Tahoe

### DBI Backend
- Custom **DBI0 binary protocol** over raw USB bulk transfers via libusb
- On your Switch: DBI → **Run DBI backend**
- No admin password needed — direct USB communication
- Fastest mode, USB retry + stall recovery + session reconnect

### Network (FTP)
- Uploads games wirelessly via **FTP** to DBI's FTP server on the Switch
- On your Switch: DBI → **Start FTP** → **Install on SD Card**
- Enter the Switch's IP:port in SWizard, drop files, install
- No USB cable needed — works over WiFi
- Remembers last FTP address across sessions

## Features

- **Drag-and-drop** `.nsp`, `.nsz`, `.xci`, `.xcz` files
- **Split panel UI** — file queue on the left, color-coded activity log on the right
- **Transfer speed + ETA** — sliding-window speed calculation with real-time MB/s and time remaining
- **SD Card / NAND picker** — choose install destination in MTP mode
- **USB retry + stall recovery** — automatic retry on transient USB errors
- **Session reconnect** — DBI Backend mode recovers from cable disconnects
- **Structured logging** — debug/info/warning/error levels with color-coding and filtering
- **Copy logs** — clipboard button for easy debugging
- **Persistent settings** — remembers transport mode and FTP address
- **Auto device detection** — shows connection status per mode (USB scan or FTP address validation)

## Architecture

Built with SOLID principles, TDD (277 tests), and clean design patterns:

```
┌─────────────────────────────────────────────┐
│           SwiftUI Views                     │  Presentation
├─────────────────────────────────────────────┤
│           AppState (@Observable)            │  State Management
├─────────────────────────────────────────────┤
│     InstallationCoordinator                 │  Orchestration (Mediator)
├────────┬────────┬────────┬──────────────────┤
│ DBI    │ MTP    │ FTP    │   FileServer     │  Domain
│Protocol│libmtp  │curl    │                  │
├────────┴────────┴────────┴──────────────────┤
│  USBTransport │ NativeMTPTransport │ Network │  Infrastructure
│  (libusb)     │ (IOUSBHost+libmtp) │ (curl)  │
├───────────────┴────────────────────┴────────┤
│  CLibUSB │ CLibMTP                          │  C Bridges
└─────────────────────────────────────────────┘
```

**Design patterns**: Command, Strategy, Decorator, Adapter, Mediator, Observer, Policy Object, Facade, Sliding Window, Value Object, Null Object

## Prerequisites

- macOS 15+ (Apple Silicon)
- [Homebrew](https://brew.sh): `brew install libusb libmtp`
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

1. Run `Build-SWizard.command` (builds and installs `/Applications/SWizard.app`, replacing existing app)
2. Open SWizard from Applications/Finder

If you only want to build without installing, run `scripts/build-app.sh`.

To regenerate the app icon asset used by the bundle, run `scripts/generate-icon.sh`.

## Releasing via GitHub Actions

You can publish a specific version from the **Release** workflow:

1. Open **Actions** -> **Release** -> **Run workflow**
2. Set `version` in `vMAJOR.MINOR.PATCH` format (example: `v1.2.3`) or prerelease format (example: `v0.1.0-alpha`)
3. Choose whether to mark it as `latest`

The workflow will:

- Create and push the tag if it does not exist yet
- Build a macOS arm64 `.app` bundle
- Upload `SWizard-<version>-macos-arm64.zip` to a GitHub Release

## Install from GitHub Release (no build required)

Because this project is unsigned/not notarized, use this Terminal-assisted install flow.

1. Download `SWizard-<version>-macos-arm64.zip` from the Release page
2. Unzip the archive
3. Open Terminal and run:

```bash
ditto "$HOME/Downloads/SWizard-<version>/SWizard.app" "/Applications/SWizard.app" && xattr -dr com.apple.quarantine "/Applications/SWizard.app" && open "/Applications/SWizard.app"
```

Replace `<version>` with the release version (example: `v0.1.0-alpha`).

## Use with Nintendo Switch (DBI)

### MTP Mode (recommended)
1. On the Switch, open DBI → **Run MTP responder**
2. Connect the Switch to your Mac with a USB data cable
3. Launch SWizard → select **MTP** mode
4. Drag `.nsp`, `.nsz`, `.xci`, or `.xcz` files into the drop area
5. Select install destination (SD Card / NAND)
6. Click **Install** → enter admin password when prompted
7. Keep DBI open until transfer finishes

### DBI Backend Mode
1. On the Switch, open DBI → **Run DBI backend**
2. Connect via USB
3. Launch SWizard → select **DBI Backend** mode
4. Wait for connection status to turn green
5. Drop files and click **Install**

### Network (FTP) Mode
1. On the Switch, open DBI → **Start FTP** → **Install on SD Card**
2. Note the IP:port shown on the Switch screen
3. Launch SWizard → select **Network** mode
4. Enter the Switch's IP:port and click **Connect**
5. Drop files and click **Install**

### Troubleshooting

- **MTP not detecting Switch**: Ensure DBI is in "Run MTP responder" mode. SWizard will ask for admin password — this is required to claim USB from macOS
- **DBI Backend not connecting**: Confirm DBI shows "Run DBI backend", not MTP
- **FTP failing**: Ensure Switch and Mac are on the same WiFi network. Try the IP shown on the Switch screen
- **Transfer interrupted**: In DBI Backend mode, SWizard auto-reconnects. In MTP/FTP mode, restart the transfer
- **macOS security blocking launch**: Run `xattr -dr com.apple.quarantine /Applications/SWizard.app`
- **First-time network permission**: macOS asks once to allow network access — click Allow

## Technical Details

### MTP on macOS Tahoe

macOS Tahoe's `AppleUSBHostCompositeDevice` kernel driver claims MTP devices before userspace apps can. SWizard's solution:

1. Run as root via admin password prompt (`osascript` with administrator privileges)
2. `libusb_set_auto_detach_kernel_driver` + `libusb_detach_kernel_driver` to release the kernel driver
3. `LIBMTP_Send_File_From_File` for the actual MTP transfer (proven reference implementation)

### DBI0 Protocol

SWizard implements the DBI0 binary protocol — the same protocol used by the official `dbibackend` Python script:

- **16-byte headers**: `DBI0` magic + command type + command ID + data size (all little-endian)
- **Commands**: LIST (file inventory), FILE_RANGE (chunk transfer), EXIT
- **Flow**: Switch drives the conversation — it requests file lists and byte ranges, Mac responds
- **Chunk size**: 1 MB per transfer

### FTP Upload

Uses system `curl` for FTP uploads to DBI's FTP server:
- Anonymous login, PASV mode
- `--globoff` for filenames with brackets
- `--disable-epsv` for DBI compatibility
- Progress tracking via curl stderr parsing

## Project Structure

```
Sources/
├── CLibUSB/              # libusb C bridge
├── CLibMTP/              # libmtp C bridge
├── USBTransport/         # libusb adapter, retry decorator, device monitor
├── DBIProtocol/          # DBI0 protocol: headers, commands, session state machine
├── MTPTransport/         # MTP device protocol, value objects
├── NativeMTPTransport/   # IOUSBHost adapter, privileged MTP session, USB scanner
├── NetworkTransport/     # FTP upload client, curl progress parser, HTTP server
├── Installer/            # Coordinator, file server, progress, speed calculator
└── SWizard/              # SwiftUI app: split panel, drop zone, log view
```

## License

MIT
