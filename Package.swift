// swift-tools-version:5.3
//
// AREK for Swift Package Manager: one library product for each permission.
//
// `ArekCore` holds what every permission shares (the popups, the configuration, the base class). A permission product
// holds one permission and depends on `ArekCore`, so an app links only the iOS frameworks of the permissions it adds:
// the App Store sees every permission API that gets linked (ArekHealth brings HealthKit in, and an app that does not
// use HealthKit is rejected). Add the products you use, and no others.
//
// The split is the one of arek.podspec: each product is the subspec of the same name, with the same source files.
// `sh scripts/check-package.sh` checks that the two agree.
//
// The iOS frameworks a permission needs are not listed here: the permission's own `import` links them.

import PackageDescription

/// A permission's product (and target) is named "Arek" + its name; `sources` are relative to code/Classes/Permissions.
let permissions: [(name: String, sources: [String])] = [
    ("Bluetooth", ["Bluetooth"]),
    ("Camera", ["ArekCamera.swift"]),
    ("CloudKit", ["ArekCloudKit.swift"]),
    ("Contacts", ["ArekContacts.swift"]),
    ("Events", ["ArekEvents.swift"]),
    ("Health", ["ArekHealth.swift"]),
    ("Location", ["Location"]),
    ("MediaLibrary", ["ArekMediaLibrary.swift"]),
    ("Microphone", ["ArekMicrophone.swift"]),
    ("Motion", ["ArekMotion.swift"]),
    ("Notifications", ["ArekNotifications.swift"]),
    ("Photos", ["ArekPhoto.swift"]),
    ("Reminders", ["ArekReminders.swift"]),
    ("Siri", ["ArekSiri.swift"]),
    ("SpeechRecognizer", ["ArekSpeechRecognizer.swift"])
]

let package = Package(
    name: "arek",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "ArekCore", targets: ["ArekCore"])
    ] + permissions.map { permission in
        .library(name: "Arek\(permission.name)", targets: ["Arek\(permission.name)"])
    },
    targets: [
        .target(
            name: "ArekCore",
            path: "code/Classes/Core"
        )
    ] + permissions.map { permission in
        .target(
            name: "Arek\(permission.name)",
            dependencies: ["ArekCore"],
            path: "code/Classes/Permissions",
            sources: permission.sources
        )
    }
)
