//
//  ArekPermissionStatusArchiveTests.swift
//  arekTests
//
//  The bytes ArekMotion keeps in UserDefaults for a status: the ones an older AREK wrote with
//  `NSKeyedArchiver.archivedData(withRootObject:)` (deprecated since iOS 12; ArekArchiveSamples holds what that call
//  returned on Apple's Foundation) are still read, what is written now is read back, and whatever else may be there is no
//  status. ArekMotionStatusStoreTests does the same through ArekMotion itself. Foundation only: scripts/test-core.sh runs
//  this file with SwiftPM on Linux too.
//

import Foundation
import XCTest
@testable import arek

final class ArekPermissionStatusArchiveTests: XCTestCase {
    private let everyStatus: [ArekPermissionStatus] = [.authorized, .denied, .notDetermined, .notAvailable]

    /// What an older AREK does with the bytes: `NSKeyedUnarchiver.unarchiveObject(with:)`, which takes any class.
    private func readByOlderArek(_ data: Data) throws -> String? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? String
    }

    // MARK: - What an older AREK stored is still read

    /// Each status on its own, so that a read that falls back to `.notDetermined` cannot pass for `.notDetermined`.
    func testReadsTheArchivesTheDeprecatedCallWrote() {
        XCTAssertEqual(ArekArchiveSamples.writtenByOlderArek.map { $0.status }, everyStatus)
        for (status, data) in ArekArchiveSamples.writtenByOlderArek {
            XCTAssertEqual(ArekPermissionStatus(archivedData: data), status, "\(status)")
        }
    }

    /// The reader reads the old archives as the older AREK itself did.
    func testTheSamplesAreWhatAnOlderArekReadsAsTheStatus() throws {
        for (status, data) in ArekArchiveSamples.writtenByOlderArek {
            XCTAssertEqual(try readByOlderArek(data), status.rawValue, "\(status)")
        }
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

    #if !os(Linux)
    /// On Apple's Foundation the secure archive of a string is the same bytes as the one the deprecated call made, so an
    /// older AREK reads what is written now and the data does not change shape. (swift-corelibs-foundation, on Linux, lays
    /// an archive out in its own order: only what the two readers make of an archive can be compared there.)
    func testWhatIsWrittenNowIsByteForByteWhatTheDeprecatedCallWrote() throws {
        for (status, data) in ArekArchiveSamples.writtenByOlderArek {
            XCTAssertEqual(status.archivedData, data, "\(status)")
        }
    }
    #endif

    // MARK: - Anything else on the key is no status

    func testNoBytesIsNoStatus() {
        XCTAssertNil(ArekPermissionStatus(archivedData: Data()))
    }

    func testBytesThatAreNoArchiveAreNoStatus() {
        XCTAssertNil(ArekPermissionStatus(archivedData: Data("authorized".utf8)))
        XCTAssertNil(ArekPermissionStatus(archivedData: Data([0x00, 0xFF, 0x10, 0x42, 0x7F])))
    }

    func testACutShortArchiveIsNoStatus() {
        for (status, data) in ArekArchiveSamples.writtenByOlderArek {
            XCTAssertNil(ArekPermissionStatus(archivedData: data.prefix(data.count / 2)), "\(status)")
        }
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
        XCTAssertNil(ArekPermissionStatus(archivedData: ArekArchiveSamples.aNumber))
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
