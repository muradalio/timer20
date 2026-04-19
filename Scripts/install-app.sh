#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Timer20"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
SOURCE_APP="$ROOT_DIR/build/$APP_NAME.app"
DEST_APP="$INSTALL_DIR/$APP_NAME.app"

"$ROOT_DIR/Scripts/build-app.sh" release >/dev/null

mkdir -p "$INSTALL_DIR"
rm -rf "$DEST_APP"
cp -R "$SOURCE_APP" "$DEST_APP"

echo "$DEST_APP"
