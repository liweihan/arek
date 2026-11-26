//
//  ArekConfiguration.swift
//  Arek
//
//  Copyright (c) 2016 Ennio Masi
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

public struct ArekConfiguration {
    var frequency: ArekPermissionFrequency = .Always
    var presentInitialPopup: Bool = true
    var presentReEnablePopup: Bool = true

    /// Where the date the re-enable popup was last shown is kept, one entry for each permission's identifier.
    var defaults: UserDefaults = .standard
    /// The calendar `.OnceADay` counts its days in: the user's own, so a day ends at their midnight.
    var calendar: Calendar = .current
    /// What time it is now; tests set their own.
    var now: () -> Date = { Date() }

    private let week = 60.0*60.0*24.0*7.0
    private let hour = 60.0*60.0

    public init(frequency: ArekPermissionFrequency,
                presentInitialPopup: Bool,
                presentReEnablePopup: Bool) {
        self.frequency = frequency
        self.presentInitialPopup = presentInitialPopup
        self.presentReEnablePopup = presentReEnablePopup
    }

    /**
     Records that the re-enable popup of a permission is on screen now; `canPresentReEnablePopup(identifier:)`
     counts its frequency from this date. Called once the popup has been presented, so a popup that could not be
     shown (no window to show it over) or was not allowed is never counted.
     */
    func reEnablePopupPresented(identifier: String) {
        self.defaults.set(self.now(), forKey: ArekConfiguration.lastPresentedKey(identifier))
    }

    /**
     Whether the re-enable popup of a permission may be shown now.

     A permission whose popup was never shown may always show it once. After that:
     - `.Always`: every time.
     - `.EveryHour`: once at least an hour has passed since it was last shown.
     - `.OnceADay`: once the calendar day has changed since it was last shown (the user's calendar and time zone).
     - `.OnceAWeek`: once at least seven days have passed since it was last shown.
     - `.JustOnce`: never again.

     A last date later than now means the device's clock was moved back; the popup may then be shown again.
     */
    func canPresentReEnablePopup(identifier: String) -> Bool {
        if !self.presentReEnablePopup {
            return false
        }

        guard let lastDate = self.lastDateForPermission(identifier: identifier) else {
            return true
        }

        let now = self.now()
        let elapsed = now.timeIntervalSince(lastDate)

        switch self.frequency {
        case .Always:
            return true
        case .EveryHour:
            return elapsed < 0 || elapsed >= hour
        case .OnceADay:
            return !self.calendar.isDate(lastDate, inSameDayAs: now)
        case .OnceAWeek:
            return elapsed < 0 || elapsed >= week
        case .JustOnce:
            return false
        }
    }

    private func lastDateForPermission(identifier: String) -> Date? {
        return self.defaults.object(forKey: ArekConfiguration.lastPresentedKey(identifier)) as? Date
    }

    static func lastPresentedKey(_ identifier: String) -> String {
        return "arek.reEnablePopup.lastPresented.\(identifier)"
    }
}
