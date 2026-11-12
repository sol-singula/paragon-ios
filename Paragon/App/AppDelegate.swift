import UIKit
import UserNotifications

/// The app's two doors from the system: the APNs token for notifications,
/// and a tapped notification. PushKit (calls) is CallManager's.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // PushKit has to be listening before the app finishes launching, or a
        // call that woke the app is lost.
        if !Demo.on { CallManager.shared.start() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.gotToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.failed(error)
    }

    // A notification while Paragon is open still shows, like the desktop's.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // A new website lead (founder, 2026-11-11: the gold card "must pop up
        // instantly"): read the inbox now rather than at the next poll.
        let kind = notification.request.content.userInfo["kind"] as? String
        if kind?.hasPrefix("lead.") == true {
            await MainActor.run { InboxModel.shared.refreshSoon() }
        }
        return [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let keys: [String: String] = ["kind", "thread_id", "person_id"].reduce(into: [:]) { d, k in if let v = info[k] as? String { d[k] = v } }
        let title = ((info["aps"] as? [String: Any])?["alert"] as? [String: Any])?["title"] as? String
        await MainActor.run {
            Router.shared.open(push: keys, title: title)
            InboxModel.shared.refreshSoon()
        }
    }
}
