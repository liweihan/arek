#!/bin/sh
# Compiles AREK's core (code/Classes/Core: the popups and when the re-enable popup may be shown again) and runs every
# test of arekTests with SwiftPM, on Linux or on a Mac, without Xcode. The factory's boxes are Linux: this is how they
# run AREK's tests. Where there is no UIKit, scripts/stand-ins/UIKit.swift stands in for the few types the core uses;
# scripts/xcode.sh test runs the same tests against the real UIKit in an iPhone simulator (.github/workflows/ci.yml).
# The permissions (code/Classes/Permissions) need iOS's frameworks and are built by scripts/xcode.sh only.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
# The toolchain a box without one fetches (mise); afk.yml's environment names the same.
SWIFT_VERSION=6.4.3

work="$root/.build/core-tests"
rm -rf "$work/Sources" "$work/Tests"
mkdir -p "$work/Sources/UIKit" "$work/Sources/arek" "$work/Tests/arekTests"
cp "$root/scripts/stand-ins/UIKit.swift" "$work/Sources/UIKit/"
find "$root/code/Classes/Core" -name '*.swift' -exec cp {} "$work/Sources/arek/" \;
find "$root/arekTests" -name '*.swift' -exec cp {} "$work/Tests/arekTests/" \;
cat > "$work/Package.swift" <<'PACKAGE'
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "arek",
    targets: [
        .target(name: "UIKit"),
        .target(name: "arek", dependencies: ["UIKit"]),
        .testTarget(name: "arekTests", dependencies: ["arek", "UIKit"])
    ]
)
PACKAGE

cd "$work"
if command -v swift >/dev/null 2>&1; then
    swift test
else
    mise exec "swift@$SWIFT_VERSION" -- swift test
fi
