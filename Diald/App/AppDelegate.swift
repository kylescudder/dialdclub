import UIKit

/// Tiny AppDelegate adapter so `application:didRegisterForRemoteNotificationsWithDeviceToken:`
/// can reach `NotificationManager`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await NotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationManager.shared.didFailToRegister(error: error)
    }
}
