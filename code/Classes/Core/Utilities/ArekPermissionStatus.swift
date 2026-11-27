//
//  ArekPermissionStatus.swift
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

public enum ArekPermissionStatus: String {
    case authorized
    case denied
    case notDetermined
    case notAvailable
}

// MARK: - What is kept in UserDefaults

extension ArekPermissionStatus {
    /// The bytes AREK keeps in UserDefaults for a status that has to survive a launch (ArekMotion's): the status's raw
    /// value as the root of a keyed archive, the same shape AREK has always written
    /// (`NSKeyedArchiver.archivedData(withRootObject: status.rawValue)`), now with secure coding on. A secure archive of
    /// a string is the same bytes as an insecure one, so a status written by this code is still read by an older AREK.
    ///
    /// nil below iOS 11, which has no non-deprecated archiver (iOS 12 is the lowest AREK is built for; Xcode 15 and
    /// later cannot target less), and when the archive cannot be made.
    internal var archivedData: Data? {
        if #available(iOS 11.0, *) {
            return try? NSKeyedArchiver.archivedData(withRootObject: rawValue, requiringSecureCoding: true)
        }
        return nil
    }

    /// The status of bytes `archivedData` made, or an older AREK did (`NSKeyedArchiver.archivedData(withRootObject:)`
    /// of the raw value). nil for anything else: no archive, a damaged one, a root of another class, a string that is
    /// no status, and below iOS 11.
    internal init?(archivedData data: Data) {
        guard #available(iOS 11.0, *) else { return nil }
        // do/catch and not `try?`: before Swift 5 `try?` on an optional gives an optional of an optional.
        let value: NSString?
        do {
            value = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data)
        } catch {
            return nil
        }
        guard let text = value, let status = ArekPermissionStatus(rawValue: String(text)) else { return nil }
        self = status
    }
}
