//
//  ArekEvents.swift
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
import EventKit

open class ArekEvents: ArekBasePermission, ArekPermissionProtocol {
    open var identifier: String = "ArekEvents"
    
    public init() {
        super.init(identifier: self.identifier)
    }
    
    public override init(configuration: ArekConfiguration? = nil, initialPopupData: ArekPopupData? = nil, reEnablePopupData: ArekPopupData? = nil) {
        super.init(configuration: configuration, initialPopupData: initialPopupData, reEnablePopupData: reEnablePopupData)
    }
    
    open func status(completion: @escaping ArekPermissionResponse) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .restricted, .denied:
                return completion(.denied)
            case .notDetermined:
                return completion(.notDetermined)
            case .writeOnly:
                // iOS 17: the app may add events but not read the calendar.
                return completion(.denied)
            default:
                // Full access is one value under two names, .fullAccess since iOS 17 and .authorized before: compared
                // so that this compiles whichever of them the SDK makes the case. Any other status is one a later SDK
                // added.
                return completion(status == .authorized ? .authorized : .notDetermined)
            }
    }
    
    open func askForPermission(completion: @escaping ArekPermissionResponse) {
            let answer: EKEventStoreRequestAccessCompletionHandler = { granted, error in
                if let error = error {
                    print("[🚨 Arek 🚨] 📆 permission not determined 🤔, error \(error)")
                    return completion(.notDetermined)
                }
                
                if granted {
                    print("[🚨 Arek 🚨] 📆 permission authorized by user ✅")
                    return completion(.authorized)
                }
                print("[🚨 Arek 🚨] 📆 permission denied by user ⛔️")
                return completion(.denied)
            }
            // From iOS 17, requestAccess(to:) asks nothing of an app built with a current SDK and answers an error.
            if #available(iOS 17.0, *) {
                EKEventStore().requestFullAccessToEvents(completion: answer)
            } else {
                EKEventStore().requestAccess(to: .event, completion: answer)
            }
    }
}
