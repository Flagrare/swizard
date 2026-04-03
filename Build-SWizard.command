#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$ROOT_DIR/scripts/build-app.sh"

open "$ROOT_DIR/build"
