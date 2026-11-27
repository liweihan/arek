//
//  ArekArchiveSamples.swift
//  arekTests
//
//  What an older AREK stored under ennioma.arek.motion.requested, byte for byte. ArekMotion called
//  `NSKeyedArchiver.archivedData(withRootObject: status.rawValue)` (deprecated since iOS 12) and kept the Data in
//  UserDefaults. These are what that call returned on Apple's Foundation, captured on 2026-11-27 by a test that printed
//  them on GitHub's macOS (run 45961478968): macOS 26.7.2 and the iOS 26.5 simulator wrote the same bytes, and
//  `archivedData(withRootObject:requiringSecureCoding: true)` wrote the same bytes again. Frozen here so that nothing
//  that changes in Foundation, or in the code that now writes them, changes what a status written by an older AREK is
//  read as. Foundation only: scripts/test-core.sh runs the files that use these with SwiftPM on Linux too.
//

import Foundation
@testable import arek

enum ArekArchiveSamples {
    /// The key an older AREK stored its status under. Written out, not taken from ArekMotion: a key that changes forgets
    /// every answer already stored.
    static let key = "ennioma.arek.motion.requested"

    /// The archive of each status's raw value that the deprecated call made.
    static let writtenByOlderArek: [(status: ArekPermissionStatus, data: Data)] = [
        (.authorized, sample("YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGiCwxVJG51bGxaYXV0aG9yaXplZAgRGiQpMjdJTFFTVlwAAAAAAAABAQAAAAAAAAANAAAAAAAAAAAAAAAAAAAAZw==")),
        (.denied, sample("YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGiCwxVJG51bGxWZGVuaWVkCBEaJCkyN0lMUVNWXAAAAAAAAAEBAAAAAAAAAA0AAAAAAAAAAAAAAAAAAABj")),
        (.notDetermined, sample("YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGiCwxVJG51bGxdbm90RGV0ZXJtaW5lZAgRGiQpMjdJTFFTVlwAAAAAAAABAQAAAAAAAAANAAAAAAAAAAAAAAAAAAAAag==")),
        (.notAvailable, sample("YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGiCwxVJG51bGxcbm90QXZhaWxhYmxlCBEaJCkyN0lMUVNWXAAAAAAAAAEBAAAAAAAAAA0AAAAAAAAAAAAAAAAAAABp"))
    ]

    /// The same call with the number 1 as the root: an archive, but not of a string.
    static let aNumber = sample("YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGiCwxVJG51bGwQAQgRGiQpMjdJTFFTVlwAAAAAAAABAQAAAAAAAAANAAAAAAAAAAAAAAAAAAAAXg==")

    private static func sample(_ base64: String) -> Data {
        guard let data = Data(base64Encoded: base64) else { fatalError("not base64: \(base64)") }
        return data
    }
}
