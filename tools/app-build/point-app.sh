#!/bin/bash
# point-app.sh <app checkout> <candidate checkout> <name|name...>
# Points the app's Package.swift dependency on this package at the candidate checkout by path. The app names the package
# by the last part of its URL (its identity); a path dependency takes its identity from the directory's name, so the
# candidate is moved beside the app under that name. Used by .github/workflows/app-build.yml; runs the same on a Mac.
set -euo pipefail
app=$1 candidate=$2 names=$3
manifest="$app/Package.swift"
pattern="\.package\(url: \"https://github\.com/[^/\"]+/($names)\"[^)]*\)"
line=$(grep -E "$pattern" "$manifest" || true)
[ "$(grep -cE "$pattern" "$manifest" || true)" = 1 ] || { echo "point-app: expected one dependency matching $names in $manifest, found:"; echo "$line"; exit 1; }
identity=$(sed -E "s#.*/($names)\".*#\1#" <<<"$line")
target="$(dirname "$app")/$identity"
if [ "$(cd "$candidate" && pwd)" != "$(mkdir -p "$target" && cd "$target" && pwd)" ]; then
  rmdir "$target" 2>/dev/null || { echo "point-app: $target exists"; exit 1; }
  mv "$candidate" "$target"
fi
sed -E -i.orig "s#$pattern#.package(path: \"../$identity\")#" "$manifest"
rm -f "$manifest.orig"
echo "point-app: $(grep -nE "\.package\(path: \"\.\./$identity\"\)" "$manifest")"
