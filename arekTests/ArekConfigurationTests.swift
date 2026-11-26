//
//  ArekConfigurationTests.swift
//  arekTests
//
//  How often the re-enable popup may be shown again, for each ArekPermissionFrequency, against a clock and a store of
//  the test's own. Foundation only: scripts/test-core.sh runs this file with SwiftPM on Linux too.
//

import Foundation
import XCTest
@testable import arek

final class ArekConfigurationTests: XCTestCase {
    private let identifier = "ArekTestPermission"
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var calendar = Calendar(identifier: .gregorian)
    private var clock = Date()

    override func setUp() {
        super.setUp()
        suiteName = "arekTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // A zone eight hours behind UTC, so a calendar day and 24 hours from the epoch's midnight differ.
        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!
        clock = at(day: 26, hour: 10, minute: 0)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    /// 2026-11-<day> <hour>:<minute> in the test's calendar.
    private func at(day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        let components = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: components)!
    }

    private func configuration(_ frequency: ArekPermissionFrequency, presentReEnablePopup: Bool = true) -> ArekConfiguration {
        var configuration = ArekConfiguration(frequency: frequency,
                                              presentInitialPopup: true,
                                              presentReEnablePopup: presentReEnablePopup)
        configuration.defaults = defaults
        configuration.calendar = calendar
        configuration.now = { [unowned self] in self.clock }
        return configuration
    }

    /// Shows the popup now (records it, as Arek does once it is on screen).
    private func present(_ configuration: ArekConfiguration) {
        configuration.reEnablePopupPresented(identifier: identifier)
    }

    private func canPresent(_ configuration: ArekConfiguration) -> Bool {
        return configuration.canPresentReEnablePopup(identifier: identifier)
    }

    // MARK: - Every frequency

    func testEveryFrequencyShowsThePopupTheFirstTime() {
        for frequency in ArekPermissionFrequency.allCases {
            XCTAssertTrue(canPresent(configuration(frequency)), "\(frequency) never shown before")
        }
    }

    func testNoFrequencyShowsThePopupWhenItIsTurnedOff() {
        for frequency in ArekPermissionFrequency.allCases {
            let configuration = self.configuration(frequency, presentReEnablePopup: false)
            XCTAssertFalse(canPresent(configuration), "\(frequency), never shown")
            present(configuration)
            clock = at(day: 26, hour: 10, minute: 0).addingTimeInterval(365 * 24 * 3600)
            XCTAssertFalse(canPresent(configuration), "\(frequency), a year later")
            clock = at(day: 26, hour: 10, minute: 0)
        }
    }

    func testEveryFrequencyButAlwaysWaitsRightAfterThePopupWasShown() {
        for frequency in ArekPermissionFrequency.allCases {
            defaults.removePersistentDomain(forName: suiteName)
            let configuration = self.configuration(frequency)
            present(configuration)
            XCTAssertEqual(canPresent(configuration), frequency == .Always, "\(frequency), the same second")
        }
    }

    // MARK: - Each frequency at its edges

    func testAlwaysShowsThePopupEveryTime() {
        let configuration = self.configuration(.Always)
        present(configuration)
        XCTAssertTrue(canPresent(configuration))
        present(configuration)
        XCTAssertTrue(canPresent(configuration))
    }

    func testJustOnceShowsThePopupOnlyOnce() {
        let configuration = self.configuration(.JustOnce)
        XCTAssertTrue(canPresent(configuration))
        present(configuration)
        XCTAssertFalse(canPresent(configuration))
        clock = at(day: 26, hour: 10, minute: 0).addingTimeInterval(365 * 24 * 3600)
        XCTAssertFalse(canPresent(configuration), "a year later")
    }

    func testEveryHourWaitsAWholeHour() {
        let configuration = self.configuration(.EveryHour)
        clock = at(day: 26, hour: 10, minute: 59)
        present(configuration)

        clock = at(day: 26, hour: 11, minute: 1)
        XCTAssertFalse(canPresent(configuration), "a new clock hour, two minutes later")
        clock = at(day: 26, hour: 11, minute: 58, second: 59)
        XCTAssertFalse(canPresent(configuration), "one second short of an hour")
        clock = at(day: 26, hour: 11, minute: 59)
        XCTAssertTrue(canPresent(configuration), "an hour later")
        clock = at(day: 28, hour: 3, minute: 0)
        XCTAssertTrue(canPresent(configuration), "days later")
    }

    func testOnceADayWaitsForTheNextCalendarDay() {
        let configuration = self.configuration(.OnceADay)
        clock = at(day: 26, hour: 0, minute: 1)
        present(configuration)

        clock = at(day: 26, hour: 23, minute: 59)
        XCTAssertFalse(canPresent(configuration), "later the same day")
        clock = at(day: 27, hour: 0, minute: 0)
        XCTAssertTrue(canPresent(configuration), "the next day, one minute later than a day's end")
        clock = at(day: 30, hour: 12, minute: 0)
        XCTAssertTrue(canPresent(configuration), "days later")
    }

    func testOnceADayCountsDaysInTheUsersTimeZone() {
        let configuration = self.configuration(.OnceADay)
        // 23:30 and 00:30 local are the same UTC day (07:30 and 08:30 UTC) and yet two days for the user.
        clock = at(day: 26, hour: 23, minute: 30)
        present(configuration)
        clock = at(day: 27, hour: 0, minute: 30)
        XCTAssertTrue(canPresent(configuration))
    }

    func testOnceAWeekWaitsSevenDays() {
        let configuration = self.configuration(.OnceAWeek)
        present(configuration)

        clock = at(day: 27, hour: 10, minute: 0)
        XCTAssertFalse(canPresent(configuration), "the next day")
        clock = at(day: 26, hour: 10, minute: 0).addingTimeInterval(7 * 24 * 3600 - 1)
        XCTAssertFalse(canPresent(configuration), "one second short of a week")
        clock = at(day: 26, hour: 10, minute: 0).addingTimeInterval(7 * 24 * 3600)
        XCTAssertTrue(canPresent(configuration), "a week later")
        clock = at(day: 26, hour: 10, minute: 0).addingTimeInterval(30 * 24 * 3600)
        XCTAssertTrue(canPresent(configuration), "a month later")
    }

    func testAClockMovedBackShowsThePopupAgain() {
        for frequency in [ArekPermissionFrequency.EveryHour, .OnceADay, .OnceAWeek] {
            defaults.removePersistentDomain(forName: suiteName)
            clock = at(day: 26, hour: 10, minute: 0)
            let configuration = self.configuration(frequency)
            present(configuration)
            clock = at(day: 25, hour: 9, minute: 0)
            XCTAssertTrue(canPresent(configuration), "\(frequency), the clock a day and an hour back")
        }
    }

    // MARK: - What is recorded

    func testEachPermissionCountsItsOwnPopup() {
        let configuration = self.configuration(.JustOnce)
        present(configuration)
        XCTAssertFalse(configuration.canPresentReEnablePopup(identifier: identifier))
        XCTAssertTrue(configuration.canPresentReEnablePopup(identifier: "ArekAnotherPermission"))
    }

    func testThePopupsDateOutlivesTheConfiguration() {
        present(configuration(.OnceAWeek))
        XCTAssertEqual(defaults.object(forKey: ArekConfiguration.lastPresentedKey(identifier)) as? Date, clock)
        // A configuration made later (the app launched again) reads the same date.
        XCTAssertFalse(canPresent(configuration(.OnceAWeek)))
    }
}
