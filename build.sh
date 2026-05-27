#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="caip"
APP_DIR="build/${APP_NAME}.app"

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

# Bundle app icon if present
if [ -f build/AppIcon.icns ]; then
  cp build/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# ad-hoc sign with stable identifier so Accessibility/Keychain re-grants survive rebuilds
codesign --force --sign - --identifier net.variant.caip --deep "${APP_DIR}" 2>/dev/null || true

echo "==> Built ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
