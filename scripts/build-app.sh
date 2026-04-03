#!/bin/bash
set -euo pipefail

# Build SWizard.app — a proper macOS app bundle you can double-click

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SWizard"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
TARGET_APP="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="$ROOT_DIR/Assets/${APP_NAME}.icns"
INSTALL_TO_APPLICATIONS=false

for arg in "$@"; do
    case "$arg" in
        --install)
            INSTALL_TO_APPLICATIONS=true
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: scripts/build-app.sh [--install]"
            exit 1
            ;;
    esac
done

echo "Building ${APP_NAME} (release)..."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build --package-path "$ROOT_DIR" -c release --quiet

echo "Creating app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

if [[ -f "${ICON_SOURCE}" ]]; then
    cp "${ICON_SOURCE}" "${RESOURCES_DIR}/${APP_NAME}.icns"
fi

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SWizard</string>
    <key>CFBundleIdentifier</key>
    <string>com.swizard.app</string>
    <key>CFBundleName</key>
    <string>SWizard</string>
    <key>CFBundleDisplayName</key>
    <string>SWizard</string>
    <key>CFBundleIconFile</key>
    <string>SWizard.icns</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

echo ""
echo "✅ ${APP_DIR} ready!"
echo ""

if [[ "$INSTALL_TO_APPLICATIONS" == true ]]; then
    echo "Installing to /Applications..."
    rm -rf "$TARGET_APP"
    ditto "$APP_DIR" "$TARGET_APP"
    xattr -dr com.apple.quarantine "$TARGET_APP" || true
    echo "✅ Installed at $TARGET_APP"
    open "$TARGET_APP"
else
    echo "To use:"
    echo "  open \"$ROOT_DIR/build/${APP_NAME}.app\""
    echo "  # or run scripts/build-app.sh --install"
fi
