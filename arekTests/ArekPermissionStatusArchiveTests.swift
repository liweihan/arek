//
//  ArekPermissionStatusArchiveTests.swift
//  arekTests
//
//  What ArekMotion keeps in UserDefaults (ennioma.arek.motion.requested): a status read from what an older AREK wrote
//  (NSKeyedArchiver.archivedData(withRootObject:), deprecated since iOS 12), a status written now, and whatever else
//  that key may hold. Foundation only: scripts/test-core.sh runs this file with SwiftPM on Linux too.
//

import Foundation
import XCTest
@testable import arek

final class ArekPermissionStatusArchiveTests: XCTestCase {
    private let everyStatus: [ArekPermissionStatus] = [.authorized, .denied, .notDetermined, .notAvailable]

    // MARK: - Helpers

    /// What an older AREK wrote for a status: a keyed archive of its raw value, without secure coding, which is what
    /// `NSKeyedArchiver.archivedData(withRootObject:)` made.
    private func writtenByOlderArek(_ status: ArekPermissionStatus) throws -> Data {
        return try NSKeyedArchiver.archivedData(withRootObject: status.rawValue, requiringSecureCoding: false)
    }

    /// What an older AREK does with the bytes: `NSKeyedUnarchiver.unarchiveObject(with:)`, which takes any class.
    private func readByOlderArek(_ data: Data) throws -> String? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? String
    }

    /// An archive (the layout of the ones an older AREK stored on a phone: $archiver, $objects with $null and the
    /// string, $top.root, $version 100000), made by plistlib, with that string as its root. Frozen, so that a change
    /// of what NSKeyedArchiver writes cannot change what these tests read.
    private func archive(base64: String) throws -> Data {
        return try XCTUnwrap(Data(base64Encoded: base64))
    }

    private let olderAuthorized = "YnBsaXN0MDDUAQIDBAUGCQxZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKiBwhVJG51bGxaYXV0aG9yaXplZNEKC1Ryb290gAESAAGGoAgRGyQpMkRHTVhbYGIAAAAAAAABAQAAAAAAAAANAAAAAAAAAAAAAAAAAAAAZw=="
    private let olderDenied = "YnBsaXN0MDDUAQIDBAUGCQxZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKiBwhVJG51bGxWZGVuaWVk0QoLVHJvb3SAARIAAYagCBEbJCkyREdNVFdcXgAAAAAAAAEBAAAAAAAAAA0AAAAAAAAAAAAAAAAAAABj"
    private let olderNotDetermined = "YnBsaXN0MDDUAQIDBAUGCQxZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKiBwhVJG51bGxdbm90RGV0ZXJtaW5lZNEKC1Ryb290gAESAAGGoAgRGyQpMkRHTVteY2UAAAAAAAABAQAAAAAAAAANAAAAAAAAAAAAAAAAAAAAag=="
    private let olderNotAvailable = "YnBsaXN0MDDUAQIDBAUGCQxZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKiBwhVJG51bGxcbm90QXZhaWxhYmxl0QoLVHJvb3SAARIAAYagCBEbJCkyREdNWl1iZAAAAAAAAAEBAAAAAAAAAA0AAAAAAAAAAAAAAAAAAABp"
    /// The same layout with the number 1 as its root.
    private let olderNumber = "YnBsaXN0MDDUAQIDBAUGCQxZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKiBwhVJG51bGwQAdEKC1Ryb290gAESAAGGoAgRGyQpMkRHTU9SV1kAAAAAAAABAQAAAAAAAAANAAAAAAAAAAAAAAAAAAAAXg=="

    // MARK: - What an older AREK stored is still read

    func testReadsEveryStatusAnOlderArekWrote() throws {
        for status in everyStatus {
            let data = try writtenByOlderArek(status)
            XCTAssertEqual(ArekPermissionStatus(archivedData: data), status, "\(status)")
        }
    }

    func testReadsTheFrozenArchivesOfAnOlderArek() throws {
        XCTAssertEqual(ArekPermissionStatus(archivedData: try archive(base64: olderAuthorized)), .authorized)
        XCTAssertEqual(ArekPermissionStatus(archivedData: try archive(base64: olderDenied)), .denied)
        XCTAssertEqual(ArekPermissionStatus(archivedData: try archive(base64: olderNotDetermined)), .notDetermined)
        XCTAssertEqual(ArekPermissionStatus(archivedData: try archive(base64: olderNotAvailable)), .notAvailable)
    }

    // MARK: - What is written now round-trips, and an older AREK reads it too

    func testEveryStatusRoundTrips() throws {
        for status in everyStatus {
            let data = try XCTUnwrap(status.archivedData, "\(status)")
            XCTAssertEqual(ArekPermissionStatus(archivedData: data), status, "\(status)")
        }
    }

    func testWhatIsWrittenNowIsReadByAnOlderArek() throws {
        for status in everyStatus {
            let data = try XCTUnwrap(status.archivedData, "\(status)")
            XCTAssertEqual(try readByOlderArek(data), status.rawValue, "\(status)")
        }
    }

    func testRoundTripsThroughUserDefaultsUnderTheKeyOfAnOlderArek() throws {
        let suiteName = "arekTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "ennioma.arek.motion.requested"

        defaults.set(try writtenByOlderArek(.denied), forKey: key)
        XCTAssertEqual(defaults.data(forKey: key).flatMap { ArekPermissionStatus(archivedData: $0) }, .denied)

        defaults.set(try XCTUnwrap(ArekPermissionStatus.authorized.archivedData), forKey: key)
        XCTAssertEqual(defaults.data(forKey: key).flatMap { ArekPermissionStatus(archivedData: $0) }, .authorized)
    }

    // MARK: - Anything else on the key is no status

    func testNoBytesIsNoStatus() {
        XCTAssertNil(ArekPermissionStatus(archivedData: Data()))
    }

    func testBytesThatAreNoArchiveAreNoStatus() {
        XCTAssertNil(ArekPermissionStatus(archivedData: Data("authorized".utf8)))
        XCTAssertNil(ArekPermissionStatus(archivedData: Data([0x00, 0xFF, 0x10, 0x42, 0x7F])))
    }

    func testACutShortArchiveIsNoStatus() throws {
        let data = try XCTUnwrap(ArekPermissionStatus.authorized.archivedData)
        XCTAssertNil(ArekPermissionStatus(archivedData: data.prefix(data.count / 2)))
    }

    func testAPropertyListThatIsNoArchiveIsNoStatus() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["root": "authorized"], format: .binary, options: 0)
        XCTAssertNil(ArekPermissionStatus(archivedData: plist))
    }

    func testAnArchiveOfAStringThatIsNoStatusIsNoStatus() throws {
        for text in ["", "granted", "Authorized", "authorized ", "restricted"] {
            let data = try NSKeyedArchiver.archivedData(withRootObject: text, requiringSecureCoding: true)
            XCTAssertNil(ArekPermissionStatus(archivedData: data), "\"\(text)\"")
        }
    }

    func testAnArchiveWhoseRootIsNotAStringIsNoStatus() throws {
        XCTAssertNil(ArekPermissionStatus(archivedData: try archive(base64: olderNumber)))
        let number = try NSKeyedArchiver.archivedData(withRootObject: NSNumber(value: 1), requiringSecureCoding: true)
        XCTAssertNil(ArekPermissionStatus(archivedData: number))
    }

    #if !os(Linux)
    /// A root that is an object of a class (here an array) and not a plist value. On iOS the unarchiver throws for a
    /// class it was not told to allow; swift-corelibs-foundation (Linux) stops the process with a fatalError instead,
    /// so only the iOS run (scripts/xcode.sh test) can have this case.
    func testAnArchiveWhoseRootIsAnArrayIsNoStatus() throws {
        let list = try NSKeyedArchiver.archivedData(withRootObject: ["authorized"], requiringSecureCoding: true)
        XCTAssertNil(ArekPermissionStatus(archivedData: list))
    }
    #endif
}
