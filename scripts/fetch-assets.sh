#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Product artwork is downloaded from Edifier, not redistributed under our MIT license.
if [[ ! -f Resources/M230II.png ]]; then
  tmp=$(mktemp Resources/M230II.XXXXXX)
  trap 'rm -f "$tmp"' EXIT
  curl --fail --location --silent --show-error \
    'https://cn-oss.edifier.com/Uploads/images/2026/10/08/2026100816003717914464376672.png' \
    --output "$tmp"
  sips -g pixelWidth "$tmp" >/dev/null
  mv "$tmp" Resources/M230II.png
fi
