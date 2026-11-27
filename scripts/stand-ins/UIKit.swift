// A stand-in for the few UIKit types AREK's core (code/Classes/Core) uses, so that the core compiles on Linux, where there
// is no UIKit. It mimics only what the core and its tests touch: an alert is never shown, `present` calls its completion
// at once. Two scripts compile against it, and the real UIKit is what the Mac checks use:
//   - scripts/test-core.sh runs every test of arekTests against it (scripts/xcode.sh test runs the same tests against the
//     real UIKit in an iPhone simulator, .github/workflows/ci.yml);
//   - scripts/check-package.sh compiles ArekCore with it and type-checks each permission against that module
//     (scripts/check-package-consumer.sh builds the products against the real UIKit, for the iOS simulator).
@_exported import Foundation

open class UIColor {}
open class UIFont {}

open class UIViewController {
    public init() {}
    open private(set) var presentedViewController: UIViewController?
    open func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        presentedViewController = viewController
        completion?()
    }
    open func dismiss(animated: Bool, completion: (() -> Void)? = nil) { completion?() }
}

open class UIAlertAction {
    public enum Style: Int { case `default`, cancel, destructive }
    open private(set) var title: String?
    open private(set) var style: Style
    let handler: ((UIAlertAction) -> Void)?
    public init(title: String?, style: Style, handler: ((UIAlertAction) -> Void)? = nil) {
        self.title = title
        self.style = style
        self.handler = handler
    }
}

open class UIAlertController: UIViewController {
    public enum Style: Int { case actionSheet, alert }
    open var title: String?
    open var message: String?
    open private(set) var actions: [UIAlertAction] = []
    public let preferredStyle: Style
    public init(title: String?, message: String?, preferredStyle: Style) {
        self.title = title
        self.message = message
        self.preferredStyle = preferredStyle
        super.init()
    }
    open func addAction(_ action: UIAlertAction) { actions.append(action) }
}

open class UIWindow {
    open var rootViewController: UIViewController?
}

open class UIApplication {
    public struct OpenExternalURLOptionsKey: Hashable { public let rawValue: String }
    public static let shared = UIApplication()
    public static let openSettingsURLString = "app-settings:"
    open var keyWindow: UIWindow?
    open func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {}
}
