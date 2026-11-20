#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]] || ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "Use um Mac ou runner macOS com o Xcode instalado." >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$root/build/StormVR-unsigned.ipa}"
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
if [[ -e "$output" ]]; then
  echo "O arquivo já existe: $output" >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

xcrun swiftc "$root/StormVR/Wire.swift" "$root/tests/WireCheck.swift" -o "$stage/wire-check"
"$stage/wire-check"
xcodebuild -project "$root/StormVR.xcodeproj" -scheme StormVR -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$stage/build" \
  CODE_SIGNING_ALLOWED=NO build
app="$stage/build/Build/Products/Release-iphoneos/StormVR.app"
xcrun lipo "$app/StormVR" -verify_arch arm64
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/StormVR.app"
ditto -c -k --norsrc --keepParent "$stage/Payload" "$stage/StormVR-unsigned.ipa"
mv "$stage/StormVR-unsigned.ipa" "$output"
echo "$output"
