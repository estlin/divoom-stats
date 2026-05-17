#!/bin/bash
# release.sh — build, zip, and publish a Divoom Stats GitHub Release.
#
# Usage:
#   ./release.sh vX.Y[.Z] [extra release notes...]
#
# Examples:
#   ./release.sh v0.2
#   ./release.sh v0.2 "Added per-quadrant color customization"
#   ./release.sh v1.0.0 "First stable release."
#
# Requires gh CLI authenticated (`gh auth login`) and a clean working tree.
# The version tag is what users see; the bundle's CFBundleShortVersionString is
# not auto-bumped here — edit build-app.sh's Info.plist heredoc if you want
# the in-app About string to match.
set -euo pipefail

cd "$(dirname "$0")"

REPO_URL="https://github.com/estlin/divoom-stats"

# --- args ---------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 vX.Y[.Z] [extra release notes]" >&2
  exit 1
fi
TAG="$1"; shift
EXTRA_NOTES="${*:-}"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: tag must look like v0.1 or v1.2.3 (got: $TAG)" >&2
  exit 1
fi

# --- preflight ----------------------------------------------------------------

GH="$(command -v gh || true)"
[[ -z "$GH" && -x /opt/homebrew/bin/gh ]] && GH=/opt/homebrew/bin/gh
if [[ -z "$GH" ]]; then
  echo "error: gh CLI not found. Install with: brew install gh" >&2
  exit 1
fi
if ! "$GH" auth status >/dev/null 2>&1; then
  echo "error: gh not authenticated. Run: gh auth login" >&2
  exit 1
fi

if ! git diff --quiet HEAD 2>/dev/null; then
  echo "error: working tree has uncommitted changes. Commit or stash first:" >&2
  git status --short >&2
  exit 1
fi

if "$GH" release view "$TAG" >/dev/null 2>&1; then
  echo "error: release $TAG already exists. To re-release, first delete it:" >&2
  echo "  $GH release delete $TAG --cleanup-tag" >&2
  exit 1
fi

# --- build --------------------------------------------------------------------

echo "==> building (./build-app.sh)"
./build-app.sh

APP="Divoom Stats.app"
if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found after build" >&2
  exit 1
fi

# --- package ------------------------------------------------------------------

ZIP="Divoom Stats.app.zip"
echo "==> packaging $APP as $ZIP"
rm -f "$ZIP"
# ditto preserves the embedded code signature; plain `zip` corrupts it.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"

# --- release notes ------------------------------------------------------------

COMMIT="$(git rev-parse --short HEAD)"
NOTES_FILE="$(mktemp -t divoom-release-notes)"

{
  if [[ -n "$EXTRA_NOTES" ]]; then
    echo "$EXTRA_NOTES"
    echo
  fi
  cat <<EOF
## Install

1. Download \`Divoom Stats.app.zip\` below, unzip, and move \`Divoom Stats.app\` wherever you like (e.g. \`/Applications\`).
2. macOS will refuse to open ad-hoc-signed apps via double-click. Either:
   - **Right-click → Open** (then click Open in the warning dialog), or
   - Run once in Terminal: \`xattr -d com.apple.quarantine "Divoom Stats.app"\`
3. Pair your Divoom Minitoo from System Settings → Bluetooth before launching.
4. Approve the Bluetooth permission prompt on first run.
5. A 📊 icon appears in your menu bar.

## Requirements

- Apple Silicon Mac (M1 / M2 / M3 / M4)
- macOS 12 (Monterey) or later
- Bluetooth-paired Divoom Minitoo

No Homebrew or other dependencies — \`libzstd\` and \`macmon\` are bundled inside the .app.

---

Built from commit \`$COMMIT\`.
EOF
} > "$NOTES_FILE"

# --- publish ------------------------------------------------------------------

echo "==> creating release $TAG"
"$GH" release create "$TAG" "$ZIP" \
  --title "$TAG" \
  --notes-file "$NOTES_FILE"

rm -f "$ZIP" "$NOTES_FILE"

echo
echo "Done: $REPO_URL/releases/tag/$TAG"
