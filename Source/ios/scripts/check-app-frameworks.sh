#!/bin/bash
set -euo pipefail

app="$1"
binary="$app/$2"
dependencies="$(xcrun otool -L "$binary" | awk '$1 ~ /^@rpath\/.*\.framework\// { print $1 }')"
if [[ -z "$dependencies" ]]; then
  exit 0
fi

rpaths="$(xcrun otool -l "$binary" | awk '$1 == "cmd" && $2 == "LC_RPATH" { nextline=1; next } nextline && $1 == "path" { print $2; nextline=0 }')"
if ! grep -Fxq "@executable_path/Frameworks" <<< "$rpaths"; then
  echo "O executável precisa do rpath @executable_path/Frameworks para abrir no iPhone." >&2
  exit 1
fi

while IFS= read -r dependency; do
  framework="${dependency#@rpath/}"
  if [[ ! -s "$app/Frameworks/$framework" ]]; then
    echo "Framework ausente no app: $framework" >&2
    exit 1
  fi
  xcrun lipo "$app/Frameworks/$framework" -verify_arch arm64
  echo "Framework iPhone OK: $framework"
done <<< "$dependencies"
