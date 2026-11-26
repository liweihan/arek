#!/bin/sh
# Builds the arek framework, or runs its XCTest target arekTests in an iPhone simulator, on a Mac with Xcode:
#
#   sh scripts/xcode.sh build    build the framework for the iOS simulator
#   sh scripts/xcode.sh test     run arekTests (every test of arekTests/, UIKit ones included) in the first available
#                                iPhone simulator
#
# .github/workflows/ci.yml runs both on GitHub's macOS machines; the factory's Linux boxes run scripts/test-core.sh.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

case "${1:-}" in
build)
    exec xcodebuild -project arek.xcodeproj -scheme arek -configuration Debug \
        -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
    ;;
test)
    simulator=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(part) for part in runtime.split(".SimRuntime.iOS-")[1].split("-") if part.isdigit()]
for runtime in sorted((r for r in devices if ".SimRuntime.iOS-" in r), key=version, reverse=True):
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("no available iPhone simulator")
')
    exec xcodebuild -project arek.xcodeproj -scheme arek -configuration Debug \
        -destination "platform=iOS Simulator,id=$simulator" CODE_SIGNING_ALLOWED=NO test
    ;;
*)
    echo "usage: sh scripts/xcode.sh build|test" >&2
    exit 64
    ;;
esac
