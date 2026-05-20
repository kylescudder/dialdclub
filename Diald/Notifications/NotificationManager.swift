import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static weak var shared: NotificationManager?

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let auth: AuthClient

    init(auth: AuthClient) {
        self.auth = auth
        super.init()
        Self.shared = self
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            Log.error(error, category: "notifications.authorization")
            return false
        }
    }

    func registerIfAuthorized() async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken data: Data) async {
        guard let userID = auth.currentUserID else { return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        let payload: [String: String] = [
            "user_id": userID.uuidString.lowercased(),
            "apns_token": token,
            "device_name": UIDevice.current.name,
            "bundle_id": Bundle.main.bundleIdentifier ?? "club.diald.app",
            "environment": Self.apnsEnvironment
        ]
        do {
            try await auth.supabase
                .from("device_tokens")
                .upsert(payload, onConflict: "user_id,apns_token")
                .execute()
        } catch {
            Log.error(error, category: "notifications.token")
        }
    }

    func scheduleLocalReminder(at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Diald"
        content.body = "Log the morning cup before the variables evaporate."
        content.sound = .default
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-brew-reminder", content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.error(error, category: "notifications.local")
        }
    }

    func cancelLocalReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-brew-reminder"])
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
