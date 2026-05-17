#!/bin/bash
# Build Divoom Stats.app — a Mac app that pushes system stats to a paired
# Divoom Minitoo over Bluetooth Classic SPP.
#
# Requires arm64 Homebrew with: brew install macmon zstd
set -euo pipefail

cd "$(dirname "$0")"

BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}"
if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
  echo "error: $BREW_PREFIX/bin/brew not found. Install arm64 Homebrew first:" >&2
  echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" >&2
  exit 1
fi

ZSTD_PREFIX="$($BREW_PREFIX/bin/brew --prefix zstd 2>/dev/null || true)"
if [[ -z "$ZSTD_PREFIX" || ! -d "$ZSTD_PREFIX" ]]; then
  echo "error: zstd not installed. Run: $BREW_PREFIX/bin/brew install zstd" >&2
  exit 1
fi

export PKG_CONFIG_PATH="$ZSTD_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

echo "==> swift build (release)"
swift build -c release --arch arm64

BIN=".build/arm64-apple-macosx/release/DivoomStats"
if [[ ! -x "$BIN" ]]; then
  echo "error: build did not produce $BIN" >&2
  exit 1
fi

APP="Divoom Stats.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DivoomStats"

# Generate icon if not already cached.
if [[ ! -f "Resources/AppIcon.icns" ]]; then
  echo "==> generating AppIcon.icns"
  mkdir -p Resources
  swift Tools/MakeIcon.swift Resources/AppIcon.iconset
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Divoom Stats</string>
    <key>CFBundleDisplayName</key><string>Divoom Stats</string>
    <key>CFBundleIdentifier</key><string>local.divoom.stats</string>
    <key>CFBundleVersion</key><string>0.1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleExecutable</key><string>DivoomStats</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Divoom Stats sends real-time CPU/GPU/RAM/disk stats to a paired Divoom Minitoo display over Bluetooth.</string>
</dict>
</plist>
PLIST

cat > /tmp/divoom.entitlements <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.bluetooth</key><true/>
</dict>
</plist>
ENT

echo "==> ad-hoc codesigning"
codesign --force --deep --sign - --entitlements /tmp/divoom.entitlements "$APP"

# Refresh icon cache so the new .icns shows immediately instead of after a reboot.
touch "$APP"

echo
echo "Done. Launch with:"
echo "  open \"$APP\""
