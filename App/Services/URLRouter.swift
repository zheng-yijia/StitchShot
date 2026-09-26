import Foundation
import StitchCore

enum AppRoute: String {
    case stitch
    case scroll
    case inbox
    case settings
}

enum URLRouter {
    static let switchTabNotification = Notification.Name("StitchShot.SwitchTab")

    private static let pendingRouteKey = "pendingRoute"

    static func handle(_ url: URL) {
        guard url.scheme == AppConstants.urlScheme else { return }
        if url.host == "x-callback-url" {
            AutomationService.handle(url)
            return
        }
        guard let host = url.host, let route = AppRoute(rawValue: host) else { return }
        post(route)
    }

    static func post(_ route: AppRoute) {
        NotificationCenter.default.post(name: switchTabNotification, object: route)
    }

    /// App Intents / 控制中心经共享 UserDefaults 传递目标页，主 App 激活时消费。
    static func setPendingRoute(_ route: AppRoute) {
        AppConstants.sharedDefaults.set(route.rawValue, forKey: pendingRouteKey)
    }

    static func consumePendingRoute() -> AppRoute? {
        guard let raw = AppConstants.sharedDefaults.string(forKey: pendingRouteKey) else { return nil }
        AppConstants.sharedDefaults.removeObject(forKey: pendingRouteKey)
        return AppRoute(rawValue: raw)
    }
}
