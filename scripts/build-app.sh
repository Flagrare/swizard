#!/bin/bash
set -euo pipefail

# Build SWizard.app — a proper macOS app bundle you can double-click

APP_NAME="SWizard"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="Assets/${APP_NAME}.icns"

echo "Building ${APP_NAME} (release)..."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release --quiet

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
echo "To use:"
echo "  open build/${APP_NAME}.app"
echo "  # or drag it to /Applications"
