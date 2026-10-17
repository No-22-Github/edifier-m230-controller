#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/fetch-assets.sh
swift build --configuration release --product M230Controller
bin_path=$(swift build --configuration release --show-bin-path)
app='dist/M230 Controller.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/M230Controller" "$app/Contents/MacOS/M230Controller"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/M230II.png "$app/Contents/Resources/M230II.png"
# Prefer a stable local identity so macOS can keep Bluetooth consent across updates.
# Override with a certificate name/hash, or explicitly use '-' for ad-hoc signing.
identity="${M230_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning | sed -nE '/"(Apple Development|Developer ID Application)/s/^[[:space:]]*[0-9]+\) ([0-9A-F]+).*/\1/p' | head -n 1)
fi
if [[ -z "$identity" ]]; then
  identity='-'
  echo 'No signing identity found; using ad-hoc signing. Rebuilds may need Bluetooth consent again.' >&2
fi
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
printf 'Built: %s\n' "$app"
