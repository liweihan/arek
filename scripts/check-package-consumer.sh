#!/bin/sh
# Builds minimal apps-side modules that depend on AREK's SwiftPM products, for the iOS simulator, and reads what they
# link. Needs a Mac with Xcode: the iOS SDK is what the permissions compile against.
#
#   sh scripts/check-package-consumer.sh
#
# What it proves, by the compiler and the linker and not by the sources:
#   - a module that depends on ArekCore and ArekCamera only builds: Camera, a module of its own, uses the core across the
#     module boundary and an app names the core's types (`import ArekCore`);
#   - what that module links has AVFoundation in it, and no HealthKit: an app that adds only ArekCamera is not
#     rejected by the App Store for linking HealthKit it does not use (README, "Swift Package Manager");
#   - the same check with ArekHealth does link HealthKit, so that the absence above means something.
#
# Each consumer is a dynamic library of a package of its own, in a temporary directory, that depends on this checkout.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

if [ "$(uname -s)" != "Darwin" ] || ! command -v xcodebuild >/dev/null 2>&1; then
    echo "check-package-consumer: needs a Mac with Xcode (xcodebuild); scripts/check-package.sh is what Linux can run" >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# The package is named after its directory by SwiftPM: "arek", whatever the checkout is called.
ln -s "$root" "$work/arek"

# consumer <name> <ArekCore + one permission product> <swift source>: builds it and prints the frameworks it links.
linked_frameworks() {
    name=$1
    product=$2
    source=$3

    dir="$work/$name"
    mkdir -p "$dir/Sources/$name"
    cat > "$dir/Package.swift" <<PACKAGE
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "$name",
    platforms: [.iOS(.v12)],
    products: [.library(name: "$name", type: .dynamic, targets: ["$name"])],
    dependencies: [.package(path: "../arek")],
    targets: [
        .target(name: "$name", dependencies: [
            .product(name: "ArekCore", package: "arek"),
            .product(name: "$product", package: "arek")
        ])
    ]
)
PACKAGE
    printf '%s\n' "$source" > "$dir/Sources/$name/$name.swift"

    (
        cd "$dir"
        xcodebuild -scheme "$name" -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath "$work/derived-$name" CODE_SIGNING_ALLOWED=NO build > "$work/build-$name.log" 2>&1
    ) || {
        echo "check-package-consumer: $name does not build (an excerpt; the build log is removed with the temporary directory):" >&2
        grep -E "error:" "$work/build-$name.log" | head -20 >&2 || tail -20 "$work/build-$name.log" >&2
        exit 1
    }

    binary=$(find "$work/derived-$name/Build/Products" -path "*/$name.framework/$name" -type f | head -1)
    if [ -z "$binary" ]; then
        echo "check-package-consumer: the build of $name made no $name.framework" >&2
        exit 1
    fi
    otool -L "$binary" | sed 1d | awk '{ print $1 }'
}

camera=$(linked_frameworks CameraConsumer ArekCamera '
import ArekCamera
import ArekCore

public func requestCamera(completion: @escaping (ArekPermissionStatus) -> Void) {
    let camera = ArekCamera(configuration: ArekConfiguration(frequency: .OnceADay, presentInitialPopup: true, presentReEnablePopup: true),
                            initialPopupData: ArekPopupData(title: "Camera", message: "Why"))
    camera.manage(completion: completion)
}
')

health=$(linked_frameworks HealthConsumer ArekHealth '
import ArekHealth
import ArekCore

public func healthPermission() -> ArekHealth {
    return ArekHealth()
}
')

status=0
if ! echo "$camera" | grep -q "AVFoundation.framework"; then
    echo "check-package-consumer: a consumer of ArekCamera does not link AVFoundation; what it links:" >&2
    echo "$camera" >&2
    status=1
fi
if echo "$camera" | grep -q "HealthKit.framework"; then
    echo "check-package-consumer: a consumer of ArekCamera links HealthKit; what it links:" >&2
    echo "$camera" >&2
    status=1
fi
if ! echo "$health" | grep -q "HealthKit.framework"; then
    echo "check-package-consumer: a consumer of ArekHealth does not link HealthKit, so this check cannot tell; what it links:" >&2
    echo "$health" >&2
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "check-package-consumer: ok (ArekCamera links AVFoundation and no HealthKit; ArekHealth links HealthKit)"
fi
exit "$status"
