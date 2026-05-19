#!/bin/bash
# Build Divoom Stats.app — a Mac app that pushes system stats to a paired
# Divoom Minitoo over Bluetooth Classic SPP.
#
# Build-time requirements (arm64 Homebrew): brew install macmon zstd
# The produced .app bundles libzstd and macmon, so end users don't need
# Homebrew to run it — just drop the .app on any Apple Silicon Mac.
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

MACMON_BIN="$BREW_PREFIX/bin/macmon"
if [[ ! -x "$MACMON_BIN" ]]; then
  echo "error: macmon not installed. Run: $BREW_PREFIX/bin/brew install macmon" >&2
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/DivoomStats"

# Generate icon if not already cached.
if [[ ! -f "Resources/AppIcon.icns" ]]; then
  echo "==> generating AppIcon.icns"
  mkdir -p Resources
  swift Tools/MakeIcon.swift Resources/AppIcon.iconset
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# --- Bundle libzstd so end users don't need Homebrew installed ---------------
echo "==> bundling libzstd.1.dylib"
# Find the exact path the binary was linked against (e.g. /opt/homebrew/opt/zstd/lib/libzstd.1.dylib).
ZSTD_REF="$(otool -L "$APP/Contents/MacOS/DivoomStats" | awk '/libzstd/ {print $1; exit}')"
if [[ -z "$ZSTD_REF" ]]; then
  echo "error: couldn't find libzstd reference in binary" >&2
  exit 1
fi
cp -L "$ZSTD_REF" "$APP/Contents/Frameworks/libzstd.1.dylib"
chmod u+w "$APP/Contents/Frameworks/libzstd.1.dylib"
# Rewrite the dylib's own id and the binary's reference + rpath so the loader
# finds it inside the bundle at @executable_path/../Frameworks/libzstd.1.dylib.
install_name_tool -id "@rpath/libzstd.1.dylib" \
  "$APP/Contents/Frameworks/libzstd.1.dylib"
install_name_tool \
  -change "$ZSTD_REF" "@rpath/libzstd.1.dylib" \
  -add_rpath "@executable_path/../Frameworks" \
  "$APP/Contents/MacOS/DivoomStats"

# --- Bundle macmon -----------------------------------------------------------
echo "==> bundling macmon"
cp -L "$MACMON_BIN" "$APP/Contents/Resources/macmon"
chmod +x "$APP/Contents/Resources/macmon"

# --- Info.plist + entitlements -----------------------------------------------
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Divoom Stats</string>
    <key>CFBundleDisplayName</key><string>Divoom Stats</string>
    <key>CFBundleIdentifier</key><string>local.divoom.stats</string>
    <key>CFBundleVersion</key><string>0.2.2</string>
    <key>CFBundleShortVersionString</key><string>0.2.2</string>
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

# --- Codesign (must come AFTER install_name_tool edits) ----------------------
# Sign the embedded binaries first, then the bundle. --deep also re-signs the
# nested dylib/binary, but signing them explicitly is more robust.
echo "==> ad-hoc codesigning"
codesign --force --sign - "$APP/Contents/Frameworks/libzstd.1.dylib"
codesign --force --sign - "$APP/Contents/Resources/macmon"
codesign --force --deep --sign - --entitlements /tmp/divoom.entitlements "$APP"

# Refresh icon cache so the new .icns shows immediately instead of after a reboot.
touch "$APP"

# Quick self-check: confirm the binary no longer references absolute brew paths.
echo
echo "==> verifying bundle is self-contained"
if otool -L "$APP/Contents/MacOS/DivoomStats" | grep -qE '/opt/homebrew|/usr/local/'; then
  echo "WARNING: binary still references absolute brew paths:" >&2
  otool -L "$APP/Contents/MacOS/DivoomStats" | grep -E '/opt/homebrew|/usr/local/' >&2
else
  echo "✓ no external Homebrew dependencies"
fi

echo
echo "Done. Launch with:"
echo "  open \"$APP\""
