//
//  ArekPopupTests.swift
//  arekTests
//
//  What `manage` shows for each permission status and popup type, through a presenter of the test's own (no window,
//  no UIApplication): every popup type is shown as a native alert, and a re-enable popup counts for its frequency only
//  once it is on screen.
//

import UIKit
import XCTest
@testable import arek

/// A permission whose status the test sets, and that counts how often iOS was asked.
final class ArekFakePermission: ArekBasePermission, ArekPermissionProtocol {
    var identifier: String = "ArekFakePermission"
    var currentStatus: ArekPermissionStatus = .notDetermined
    /// Whether the status arrives on a background queue, as a notification's or CloudKit's does.
    var answersInTheBackground = false
    var timesAsked = 0

    func status(completion: @escaping ArekPermissionResponse) {
        let status = self.currentStatus
        if self.answersInTheBackground {
            DispatchQueue.global().async { completion(status) }
        } else {
            completion(status)
        }
    }

    func askForPermission(completion: @escaping ArekPermissionResponse) {
        self.timesAsked += 1
        completion(.authorized)
    }
}

final class ArekPopupTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    /// The alerts handed to the presenter, in order.
    private var presented: [UIAlertController] = []
    /// Whether the presenter puts the alert on screen (false: there is no window to show it over).
    private var onScreen = true
    /// Whether the presenter keeps the alert on its way to the screen: its `shown` waits in `held` for the test.
    private var hold = false
    private var held: [(Bool) -> Void] = []
    /// Called with each alert the presenter is handed, and whether it was handed it on the main thread.
    private var onPresent: ((UIAlertController, Bool) -> Void)?

    override func setUp() {
        super.setUp()
        suiteName = "arekTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        presented = []
        onScreen = true
        hold = false
        held = []
        onPresent = nil
        ArekBasePermission.reEnablePopupsPending = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func permission(status: ArekPermissionStatus,
                            type: ArekPopupType = .native,
                            frequency: ArekPermissionFrequency = .Always,
                            presentInitialPopup: Bool = true,
                            presentReEnablePopup: Bool = true) -> ArekFakePermission {
        var configuration = ArekConfiguration(frequency: frequency,
                                              presentInitialPopup: presentInitialPopup,
                                              presentReEnablePopup: presentReEnablePopup)
        configuration.defaults = defaults
        let initial = ArekPopupData(title: "Initial title", message: "Initial message",
                                    allowButtonTitle: "Allow", denyButtonTitle: "Not now", type: type)
        let reEnable = ArekPopupData(title: "Re-enable title", message: "Re-enable message",
                                     allowButtonTitle: "Settings", denyButtonTitle: "Not now", type: type)
        let permission = ArekFakePermission(configuration: configuration,
                                            initialPopupData: initial,
                                            reEnablePopupData: reEnable)
        permission.currentStatus = status
        permission.presentAlert = { [unowned self] alert, shown in
            self.presented.append(alert)
            self.onPresent?(alert, Thread.isMainThread)
            if self.hold {
                self.held.append(shown)
            } else {
                shown(self.onScreen)
            }
        }
        return permission
    }

    private var lastPresented: Date? {
        return defaults.object(forKey: ArekConfiguration.lastPresentedKey("ArekFakePermission")) as? Date
    }

    // MARK: - Every popup type is a native alert

    /// Both popup types. ArekPopupType cannot be CaseIterable: Swift does not synthesize allCases for an enum with a
    /// deprecated case.
    private let everyPopupType: [ArekPopupType] = [.native, .codeido]

    func testEveryPopupTypeShowsTheInitialPopupAsANativeAlert() {
        for type in everyPopupType {
            presented = []
            let permission = self.permission(status: .notDetermined, type: type)
            var answer: ArekPermissionStatus?
            permission.manage { answer = $0 }

            XCTAssertEqual(presented.count, 1, "\(type)")
            let alert = presented.first
            XCTAssertEqual(alert?.preferredStyle, .alert, "\(type)")
            XCTAssertEqual(alert?.title, "Initial title", "\(type)")
            XCTAssertEqual(alert?.message, "Initial message", "\(type)")
            XCTAssertEqual(alert?.actions.map { $0.title ?? "" } ?? [], ["Not now", "Allow"], "\(type)")
            XCTAssertEqual(alert?.actions.map { $0.style } ?? [], [.cancel, .default], "\(type)")
            XCTAssertNil(answer, "\(type): the answer waits for a button")
            XCTAssertEqual(permission.timesAsked, 0, "\(type): iOS is asked only after Allow")
        }
    }

    func testEveryPopupTypeShowsTheReEnablePopupAsANativeAlert() {
        for type in everyPopupType {
            presented = []
            defaults.removePersistentDomain(forName: suiteName)
            let permission = self.permission(status: .denied, type: type)
            var answer: ArekPermissionStatus?
            permission.manage { answer = $0 }

            XCTAssertEqual(presented.count, 1, "\(type)")
            let alert = presented.first
            XCTAssertEqual(alert?.preferredStyle, .alert, "\(type)")
            XCTAssertEqual(alert?.title, "Re-enable title", "\(type)")
            XCTAssertEqual(alert?.message, "Re-enable message", "\(type)")
            XCTAssertEqual(alert?.actions.map { $0.title ?? "" } ?? [], ["Not now", "Settings"], "\(type)")
            XCTAssertEqual(answer, .denied, "\(type)")
        }
    }

    /// The README of 4.0.2 told developers to set `.codeido`; until 2026-11 that crashed the app (fatalError) on the
    /// first request of the permission and on every re-enable popup.
    func testCodeidoNoLongerCrashes() {
        let asked = self.permission(status: .notDetermined, type: .codeido)
        asked.manage { _ in }
        let denied = self.permission(status: .denied, type: .codeido)
        denied.manage { _ in }
        XCTAssertEqual(presented.map { $0.title ?? "" }, ["Initial title", "Re-enable title"])
    }

    // MARK: - What turns a popup off

    func testWithoutTheInitialPopupIOSIsAskedAtOnce() {
        let permission = self.permission(status: .notDetermined, presentInitialPopup: false)
        var answer: ArekPermissionStatus?
        permission.manage { answer = $0 }
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual(permission.timesAsked, 1)
        XCTAssertEqual(answer, .authorized)
    }

    func testWithoutTheReEnablePopupADeniedPermissionShowsNothing() {
        let permission = self.permission(status: .denied, presentReEnablePopup: false)
        var answer: ArekPermissionStatus?
        permission.manage { answer = $0 }
        XCTAssertTrue(presented.isEmpty)
        XCTAssertNil(lastPresented)
        XCTAssertEqual(answer, .denied)
    }

    func testAnAuthorizedPermissionShowsNothing() {
        let permission = self.permission(status: .authorized)
        var answer: ArekPermissionStatus?
        permission.manage { answer = $0 }
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual(answer, .authorized)
    }

    // MARK: - The re-enable popup's frequency, through manage

    func testTheReEnablePopupIsCountedOnceItIsOnScreen() {
        let permission = self.permission(status: .denied, frequency: .JustOnce)
        XCTAssertNil(lastPresented)
        permission.manage { _ in }
        XCTAssertNotNil(lastPresented)
        permission.manage { _ in }
        permission.manage { _ in }
        XCTAssertEqual(presented.count, 1, "JustOnce shows it once")
    }

    func testAReEnablePopupThatWasNotShownIsNotCounted() {
        let permission = self.permission(status: .denied, frequency: .JustOnce)
        onScreen = false
        permission.manage { _ in }
        XCTAssertNil(lastPresented, "no window: nothing was shown")
        onScreen = true
        permission.manage { _ in }
        XCTAssertNotNil(lastPresented)
        permission.manage { _ in }
        XCTAssertEqual(presented.count, 2, "tried, shown, then never again")
    }

    /// Two requests in a row, the second before UIKit has finished presenting the first popup, show one popup.
    func testARequestWhileTheReEnablePopupIsOnItsWayShowsNothing() {
        let permission = self.permission(status: .denied, frequency: .JustOnce)
        hold = true
        permission.manage { _ in }
        permission.manage { _ in }
        XCTAssertEqual(presented.count, 1)
        XCTAssertNil(lastPresented, "not on screen yet")

        held.removeFirst()(true)
        XCTAssertNotNil(lastPresented)
        permission.manage { _ in }
        XCTAssertEqual(presented.count, 1, "JustOnce shows it once")
    }

    func testAReEnablePopupThatCouldNotBeShownLetsTheNextRequestTryAgain() {
        let permission = self.permission(status: .denied, frequency: .JustOnce)
        hold = true
        permission.manage { _ in }
        held.removeFirst()(false)
        XCTAssertNil(lastPresented)

        permission.manage { _ in }
        XCTAssertEqual(presented.count, 2)
    }

    // MARK: - UIKit on the main thread

    func testAStatusFromABackgroundQueueShowsTheInitialPopupOnTheMainThread() {
        self.assertPopupOnTheMainThread(status: .notDetermined, title: "Initial title")
    }

    func testAStatusFromABackgroundQueueShowsTheReEnablePopupOnTheMainThread() {
        self.assertPopupOnTheMainThread(status: .denied, title: "Re-enable title")
    }

    private func assertPopupOnTheMainThread(status: ArekPermissionStatus, title: String,
                                            file: StaticString = #file, line: UInt = #line) {
        let permission = self.permission(status: status)
        permission.answersInTheBackground = true
        let presentedOnMain = expectation(description: "the popup is presented")
        onPresent = { alert, onMainThread in
            XCTAssertEqual(alert.title, title, file: file, line: line)
            XCTAssertTrue(onMainThread, "UIKit is used on the main thread only", file: file, line: line)
            presentedOnMain.fulfill()
        }
        permission.manage { _ in }
        wait(for: [presentedOnMain], timeout: 5)
    }

    func testTheInitialPopupIsNotCountedAsAReEnablePopup() {
        let permission = self.permission(status: .notDetermined, frequency: .JustOnce)
        permission.manage { _ in }
        XCTAssertNil(lastPresented)
    }

    // MARK: - Defaults

    func testTheDefaultFrequencyIsAlways() {
        let permission = ArekBasePermission(identifier: "ArekFakePermission")
        XCTAssertEqual(permission.configuration.frequency, .Always)
        XCTAssertTrue(permission.configuration.presentInitialPopup)
        XCTAssertTrue(permission.configuration.presentReEnablePopup)
        XCTAssertEqual(permission.initialPopupData.type, .native)
    }
}
