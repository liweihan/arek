#!/bin/sh
# Runs scripts/check-project.rb (arek.xcodeproj and arek.podspec build the same thing), installing the xcodeproj gem
# it reads the project with when the machine lacks it. Linux or a Mac; no Xcode needed.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
if ! ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
    gem install --user-install --no-document xcodeproj >/dev/null
fi
exec ruby "$root/scripts/check-project.rb"
