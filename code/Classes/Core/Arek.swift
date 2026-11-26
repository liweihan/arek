//
//  Arek.swift
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
import UIKit

public typealias ArekPermissionResponse = (ArekPermissionStatus) -> Void

public protocol ArekPermissionProtocol: class {
    var identifier: String { get }
    /**
     This is the key method to know if a permission has been authorized or denied.
     
     Parameter completion: this closure is invoked with the current permission status (ArekPermissionStatus)
     */
    func status(completion: @escaping ArekPermissionResponse)

    /**
     This is the key method to manage the request for a permission.
     
     The behaviour is based on the ArekConfiguration set in the permission during the initialization phase.
     
     
     Parameter completion: this closure is invoked with the current permission status (ArekPermissionStatus)
     */
    func manage(completion: @escaping ArekPermissionResponse)
    func askForPermission(completion: @escaping ArekPermissionResponse)
}

/**
 ArekBasePermission is a root class and each permission inherit from it.
 
 Don't instantiate ArekBasePermission directly.
 */
open class ArekBasePermission {
    var configuration: ArekConfiguration = ArekConfiguration(frequency: .Always, presentInitialPopup: true, presentReEnablePopup: true)
    var initialPopupData: ArekPopupData = ArekPopupData()
    var reEnablePopupData: ArekPopupData = ArekPopupData()

    /**
     Shows one of AREK's alerts and calls `onScreen` once it is on screen. Where there is nothing to show it over
     (no key window), nothing is shown and `onScreen` is never called. Tests replace it.
     */
    var presentAlert: (_ alert: UIAlertController, _ onScreen: @escaping () -> Void) -> Void = ArekBasePermission.presentOverTopViewController
    
    public init(identifier: String) {
        let data = ArekLocalizationManager(permission: identifier)
        
        self.initialPopupData = ArekPopupData(title: data.initialTitle,
                                             message: data.initialMessage,
                                             image: data.image,
                                             allowButtonTitle: data.allowButtonTitle,
                                             denyButtonTitle: data.denyButtonTitle,
                                             styling: nil)
        
        self.reEnablePopupData = ArekPopupData(title: data.reEnableTitle,
                                              message:  data.reEnableMessage,
                                              image: data.image,
                                              allowButtonTitle: data.allowButtonTitle,
                                              denyButtonTitle: data.denyButtonTitle,
                                              styling: nil)
    }

    /**
     Base init shared among each permission provided by Arek
     
     - Parameters:
         - configuration: ArekConfiguration object used to define the behaviour of the pre-iOS popup and the re-enable permission popup
         - initialPopupData: title and message related to pre-iOS popup
         - reEnablePopupData: title and message related to re-enable permission popup
     */
    public init(configuration: ArekConfiguration? = nil,
                initialPopupData: ArekPopupData? = nil,
                reEnablePopupData: ArekPopupData? = nil) {
        
        self.configuration = configuration ?? self.configuration
        self.initialPopupData = initialPopupData ?? self.initialPopupData
        self.reEnablePopupData = reEnablePopupData ?? self.reEnablePopupData
    }
    
    private func manageInitialPopup(completion: @escaping ArekPermissionResponse) {
        if self.configuration.presentInitialPopup {
            self.presentInitialPopup(title: self.initialPopupData.title,
                                     message: self.initialPopupData.message,
                                     allowButtonTitle: self.initialPopupData.allowButtonTitle,
                                     denyButtonTitle: self.initialPopupData.denyButtonTitle,
                                     completion: completion)
        } else {
            (self as? ArekPermissionProtocol)?.askForPermission(completion: completion)
        }
    }
    
    /// Every popup type is shown as a native alert: PMAlertController (`.codeido`) was removed from AREK.
    private func presentInitialPopup(title: String,
                                     message: String,
                                     allowButtonTitle: String,
                                     denyButtonTitle: String,
                                     completion: @escaping ArekPermissionResponse) {
        ArekBasePermission.noteNativeOnly(self.initialPopupData)
        self.presentInitialNativePopup(title: title,
                                       message: message,
                                       allowButtonTitle: allowButtonTitle,
                                       denyButtonTitle: denyButtonTitle,
                                       completion: completion)
    }
    
    private func presentInitialNativePopup(title: String,
                                           message: String,
                                           allowButtonTitle: String,
                                           denyButtonTitle: String,
                                           completion: @escaping ArekPermissionResponse) {
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let allow = UIAlertAction(title: allowButtonTitle, style: .default) { _ in
            (self as? ArekPermissionProtocol)?.askForPermission(completion: completion)
            alert.dismiss(animated: true, completion: nil)
        }
        
        let deny = UIAlertAction(title: denyButtonTitle, style: .cancel) { _ in
            completion(.denied)
            alert.dismiss(animated: true, completion: nil)
        }
        
        alert.addAction(deny)
        alert.addAction(allow)
        
        self.presentAlert(alert) {}
    }
    
    private func presentReEnablePopup() {
        guard let permission = self as? ArekPermissionProtocol else { return }
        
        if self.configuration.canPresentReEnablePopup(identifier: permission.identifier) {
            self.presentReEnablePopup(identifier: permission.identifier,
                                      title: self.reEnablePopupData.title,
                                      message: self.reEnablePopupData.message,
                                      allowButtonTitle: self.reEnablePopupData.allowButtonTitle,
                                      denyButtonTitle: self.reEnablePopupData.denyButtonTitle)
        } else {
            print("[🚨 Arek 🚨] for \(self) present re-enable not allowed")
        }
    }

    /// Every popup type is shown as a native alert: PMAlertController (`.codeido`) was removed from AREK.
    private func presentReEnablePopup(identifier: String,
                                      title: String,
                                      message: String,
                                      allowButtonTitle: String,
                                      denyButtonTitle: String) {
        ArekBasePermission.noteNativeOnly(self.reEnablePopupData)
        self.presentReEnableNativePopup(identifier: identifier,
                                        title: title,
                                        message: message,
                                        allowButtonTitle: allowButtonTitle,
                                        denyButtonTitle: denyButtonTitle)
    }
    
    private func presentReEnableNativePopup(identifier: String,
                                            title: String,
                                            message: String,
                                            allowButtonTitle: String,
                                            denyButtonTitle: String) {
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let allow = UIAlertAction(title: allowButtonTitle, style: .default) { _ in
            alert.dismiss(animated: true, completion: nil)
            
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        let deny = UIAlertAction(title: denyButtonTitle, style: .cancel) { _ in
            alert.dismiss(animated: true, completion: nil)
        }
        
        alert.addAction(deny)
        alert.addAction(allow)
        
        // The frequency counts from the moment the popup is on screen: one that was never shown is never counted.
        let configuration = self.configuration
        self.presentAlert(alert) {
            configuration.reEnablePopupPresented(identifier: identifier)
        }
    }

    /// Shows `alert` over the key window's top view controller, on the main queue.
    static func presentOverTopViewController(_ alert: UIAlertController, onScreen: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard var topController = UIApplication.shared.keyWindow?.rootViewController else { return }
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            topController.present(alert, animated: true, completion: onScreen)
        }
    }

    /// A native alert has no image and no styling: say so where a developer asked for PMAlertController or styling.
    private static func noteNativeOnly(_ data: ArekPopupData) {
        if data.type != .native || data.styling != nil {
            print("[🚨 Arek 🚨] PMAlertController support was removed: this popup is shown as a native alert, without image or styling")
        }
    }
    
    open func manage(completion: @escaping ArekPermissionResponse) {
        (self as? ArekPermissionProtocol)?.status { status in
            self.managePermission(status: status, completion: completion)
        }
    }
    
    internal func managePermission(status: ArekPermissionStatus, completion: @escaping ArekPermissionResponse) {
        switch status {
        case .notDetermined:
            self.manageInitialPopup(completion: completion)

        case .denied:
            self.presentReEnablePopup()
            return completion(.denied)

        case .authorized:
            return completion(.authorized)

        case .notAvailable:
            return completion(.notAvailable)
        }
    }
}
