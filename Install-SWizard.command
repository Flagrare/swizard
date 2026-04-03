#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$ROOT_DIR/build/SWizard.app"
TARGET_APP="/Applications/SWizard.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  osascript -e 'display dialog "SWizard.app not found in build/. Run Build-SWizard.command first." buttons {"OK"} default button "OK" with icon caution'
  exit 1
fi

rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" || true

open "$TARGET_APP"
