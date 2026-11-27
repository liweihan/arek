//
//  ArekMotionStatusStoreTests.swift
//  arekTests
//
//  ArekMotion's own read and write of the status it keeps in UserDefaults.standard, through `motionRequested`: what an
//  older AREK stored under its key is read, a status written now lands under the same key in the same bytes, and a key
//  with nothing, or with something that is no status, reads as `.notDetermined`. ArekMotion is built on iOS only
//  (CoreMotion): this file is empty elsewhere, and runs with scripts/xcode.sh test.
//

#if os(iOS)
import Foundation
import XCTest
@testable import arek

final class ArekMotionStatusStoreTests: XCTestCase {
    private var defaults: UserDefaults { return UserDefaults.standard }

    override func setUp() {
        super.setUp()
        defaults.removeObject(forKey: ArekArchiveSamples.key)
    }

    override func tearDown() {
        defaults.removeObject(forKey: ArekArchiveSamples.key)
        super.tearDown()
    }

    func testReadsWhatAnOlderArekStoredUnderItsKey() {
        let motion = ArekMotion()
        for (status, data) in ArekArchiveSamples.writtenByOlderArek {
            defaults.set(data, forKey: ArekArchiveSamples.key)
            XCTAssertEqual(motion.motionRequested, status, "\(status)")
        }
    }

    func testNothingStoredIsNotDetermined() {
        XCTAssertNil(defaults.object(forKey: ArekArchiveSamples.key))
        XCTAssertEqual(ArekMotion().motionRequested, .notDetermined)
    }

    func testWhatIsStoredButIsNoStatusIsNotDetermined() throws {
        let motion = ArekMotion()
        let authorized = try XCTUnwrap(ArekArchiveSamples.writtenByOlderArek.first { $0.status == .authorized }?.data)
        let damaged: [(String, Any)] = [
            ("a cut short archive", authorized.prefix(authorized.count / 2) as Data),
            ("bytes that are no archive", Data("authorized".utf8)),
            ("no bytes", Data()),
            ("a string and not data", "authorized"),
            ("an archive of a number", ArekArchiveSamples.aNumber),
            ("an archive of a string that is no status",
             try NSKeyedArchiver.archivedData(withRootObject: "granted", requiringSecureCoding: true))
        ]
        for (what, value) in damaged {
            defaults.set(value, forKey: ArekArchiveSamples.key)
            XCTAssertEqual(motion.motionRequested, .notDetermined, what)
        }
    }

    func testWritesUnderTheKeyOfAnOlderArekWhatAnOlderArekWrote() {
        let motion = ArekMotion()
        for (status, data) in ArekArchiveSamples.writtenByOlderArek {
            motion.motionRequested = status
            XCTAssertEqual(defaults.data(forKey: ArekArchiveSamples.key), data, "\(status)")
        }
    }

    func testWhatIsWrittenIsReadByAnotherInstance() {
        ArekMotion().motionRequested = .denied
        XCTAssertEqual(ArekMotion().motionRequested, .denied)
        ArekMotion().motionRequested = .authorized
        XCTAssertEqual(ArekMotion().motionRequested, .authorized)
    }
}
#endif
