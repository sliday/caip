#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="caip"
APP_DIR="build/${APP_NAME}.app"

# Build per-arch and lipo together. Works with Command Line Tools only.
# Passing both --arch flags to a single swift-build invocation requires the
# full Xcode SDK (xcbuild), which most build hosts (including bare CLT
# installs) do not have.

echo "==> swift build arm64 (${CONFIG})"
swift build -c "${CONFIG}" --arch arm64
ARM_BIN="$(swift build -c "${CONFIG}" --arch arm64 --show-bin-path)/${APP_NAME}"

X86_BIN=""
if [ "${UNIVERSAL:-1}" = "1" ]; then
  echo "==> swift build x86_64 (${CONFIG})"
  if swift build -c "${CONFIG}" --arch x86_64; then
    X86_BIN="$(swift build -c "${CONFIG}" --arch x86_64 --show-bin-path)/${APP_NAME}"
  else
    echo "    (x86_64 build failed — shipping arm64-only)"
  fi
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

if [ -n "${X86_BIN}" ]; then
  echo "==> lipo arm64 + x86_64"
  lipo -create -output "${APP_DIR}/Contents/MacOS/${APP_NAME}" "${ARM_BIN}" "${X86_BIN}"
else
  cp "${ARM_BIN}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
fi

cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

# Bundle app icon if present
if [ -f build/AppIcon.icns ]; then
  cp build/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# ad-hoc sign with stable identifier so Accessibility/Keychain re-grants survive rebuilds
codesign --force --sign - --identifier net.variant.caip --deep "${APP_DIR}" 2>/dev/null || true

echo "==> Built ${APP_DIR}"
echo "    Architectures: $(lipo -archs "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || echo unknown)"
echo "Run with: open ${APP_DIR}"
