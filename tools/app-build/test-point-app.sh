#!/bin/bash
# Tests of point-app.sh on planted manifests (run by .github/workflows/app-build.yml on every PR; needs no Swift).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fails=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fails=1; fi; }
setup() {
  T=$(mktemp -d); mkdir -p "$T/app" "$T/candidate"; touch "$T/candidate/Package.swift"
  printf '%s\n' 'let package = Package(' '    dependencies: [' \
    '        .package(url: "https://github.com/EMSuite/DiffractoKit", from: "0.11.0"),' "$1" '    ],' ')' > "$T/app/Package.swift"
}

setup '        .package(url: "https://github.com/mac4DSTEM/MacEMUI", from: "0.13.0"),'
"$here/point-app.sh" "$T/app" "$T/candidate" "MacEMUI|EMSuiteUI" > /dev/null
check "old name: path dependency under the URL's identity" 'grep -q "\.package(path: \"\.\./MacEMUI\")," "$T/app/Package.swift"'
check "old name: candidate moved beside the app" '[ -f "$T/MacEMUI/Package.swift" ] && [ ! -e "$T/candidate" ]'
check "other dependencies untouched" 'grep -q "github.com/EMSuite/DiffractoKit\", from: \"0.11.0\"" "$T/app/Package.swift"'
rm -rf "$T"

setup '        .package(url: "https://github.com/EMSuite/EMSuiteUI", from: "0.14.0"),'
"$here/point-app.sh" "$T/app" "$T/candidate" "MacEMUI|EMSuiteUI" > /dev/null
check "new name" 'grep -q "\.package(path: \"\.\./EMSuiteUI\")," "$T/app/Package.swift" && [ -d "$T/EMSuiteUI" ]'
rm -rf "$T"

setup '        .package(url: "https://github.com/EMSuite/ImagoKit", from: "0.11.0"),'
check "refuses a manifest without the package" '! "$here/point-app.sh" "$T/app" "$T/candidate" "MacEMUI|EMSuiteUI" > /dev/null'
rm -rf "$T"
exit $fails
