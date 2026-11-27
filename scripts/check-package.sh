#!/bin/sh
# Checks that Package.swift and arek.podspec split AREK the same way, and that each permission compiles as a module of
# its own against ArekCore (scripts/check-package.rb says what it checks), with the package as SwiftPM describes it.
# Linux or a Mac; no Xcode needed: swiftc type-checks the permissions against a UIKit stand-in and empty frameworks.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
# The toolchain a box without one fetches (mise); afk.yml's environment names the same.
SWIFT_VERSION=6.4.3

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
if command -v swift >/dev/null 2>&1; then
    swift package describe --type json > "$tmp/package.json"
    AREK_SWIFTC=swiftc
else
    mise exec "swift@$SWIFT_VERSION" -- swift package describe --type json > "$tmp/package.json"
    AREK_SWIFTC="mise exec swift@$SWIFT_VERSION -- swiftc"
fi
export AREK_SWIFTC
ruby "$root/scripts/check-package.rb" "$tmp/package.json"
