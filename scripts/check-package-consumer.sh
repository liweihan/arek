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

# consumer <name> <ArekCore + one permission product> <swift source>: builds it and prints the names of the frameworks
# that what it built links (Foundation, AVFoundation, ...), one on a line.
#
# What an app that adds the consumer links is what the consumer's own binary links and, from it, what the binaries it
# loads link: SwiftPM may build a permission's product into the consumer's binary (a static library) or as a framework
# of its own (a dynamic one, in PackageFrameworks, which the consumer names by an @rpath), and the iOS frameworks it
# imports are then on whichever binary holds it. So this starts at the consumer's binary and follows its @rpath
# dependencies to the binaries the build made, and reads no other binary of the build: one the consumer does not load
# (a helper the build made on the way) says nothing of what an app links.
linked_frameworks() {
    name=$1
    product=$2
    source=$3

    dir="$work/$name"
    products="$work/derived-$name/Build/Products"
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

    log="$work/build-$name.log"
    (
        cd "$dir"
        xcodebuild -scheme "$name" -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath "$work/derived-$name" CODE_SIGNING_ALLOWED=NO build > "$log" 2>&1
    ) || {
        # The build log is removed with the temporary directory: what a failed run leaves to read is printed here.
        echo "check-package-consumer: $name does not build. The errors of xcodebuild, and the end of its log:" >&2
        grep -E "error:" "$log" | head -20 >&2 || true
        echo "---" >&2
        tail -20 "$log" >&2
        echo "--- the schemes xcodebuild finds in the consumer's package:" >&2
        (cd "$dir" && xcodebuild -list 2>&1 | head -40) >&2 || true
        exit 1
    }

    # The consumer's binary: its framework, or its dynamic library.
    start=$(find "$products" \( -path "*/$name.framework/$name" -o -name "lib$name.dylib" \) -type f | head -1)
    if [ -z "$start" ]; then
        echo "check-package-consumer: the build of $name made no $name.framework (nor lib$name.dylib); what it made:" >&2
        find "$products" -maxdepth 5 >&2 || true
        exit 1
    fi

    # `otool -L` prints the binary's own name first and, for a binary of several architectures, a heading for each; the
    # libraries it loads are on the lines that begin with a tab. A binary it cannot read, or that loads nothing, fails
    # the check (a failure of otool must not read as "links no HealthKit"): the status of otool itself is read, not the
    # status of a pipeline that ends in a filter.
    pending="$work/pending-$name.txt"
    seen="$work/seen-$name.txt"
    linked="$work/linked-$name.txt"
    dependencies="$work/dependencies-$name.txt"
    echo "$start" > "$pending"
    : > "$seen"
    : > "$linked"
    while [ -s "$pending" ]; do
        binary=$(head -1 "$pending")
        sed 1d "$pending" > "$pending.rest"
        mv "$pending.rest" "$pending"
        if grep -qxF "$binary" "$seen"; then continue; fi
        echo "$binary" >> "$seen"

        if ! listing=$(otool -L "$binary" 2>&1); then
            echo "check-package-consumer: otool -L failed on $binary:" >&2
            echo "$listing" >&2
            exit 1
        fi
        echo "$listing" | grep "^[[:space:]]" | awk '{ print $1 }' > "$dependencies" || true
        if [ ! -s "$dependencies" ]; then
            echo "check-package-consumer: otool -L printed no library for $binary:" >&2
            echo "$listing" >&2
            exit 1
        fi

        while read -r dependency; do
            echo "$dependency" >> "$linked"
            case "$dependency" in
            @rpath/*.framework/*) found=$(find "$products" -path "*/${dependency#@rpath/}" -type f | head -1) ;;
            @rpath/*.dylib) found=$(find "$products" -name "${dependency##*/}" -type f | head -1) ;;
            *) found= ;;
            esac
            if [ -n "$found" ]; then
                echo "$found" >> "$pending"
            else
                case "$dependency" in
                @rpath/Arek*)
                    echo "check-package-consumer: $binary loads $dependency, which the build of $name did not make; what it made:" >&2
                    find "$products" -maxdepth 5 >&2 || true
                    exit 1
                    ;;
                esac
            fi
        done < "$dependencies"
    done

    sed -n 's#.*/\([A-Za-z0-9_]*\)\.framework/.*#\1#p' "$linked" | sort -u
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
links() { echo "$1" | grep -qx "$2"; }
echo "check-package-consumer: CameraConsumer (ArekCore + ArekCamera) links: $(echo "$camera" | tr '\n' ' ')"
echo "check-package-consumer: HealthConsumer (ArekCore + ArekHealth) links: $(echo "$health" | tr '\n' ' ')"
if ! links "$camera" AVFoundation; then
    echo "check-package-consumer: a consumer of ArekCamera does not link AVFoundation" >&2
    status=1
fi
if links "$camera" HealthKit; then
    echo "check-package-consumer: a consumer of ArekCamera links HealthKit" >&2
    status=1
fi
if ! links "$health" HealthKit; then
    echo "check-package-consumer: a consumer of ArekHealth does not link HealthKit, so this check cannot tell" >&2
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "check-package-consumer: ok (ArekCamera links AVFoundation and no HealthKit; ArekHealth links HealthKit)"
fi
exit "$status"
