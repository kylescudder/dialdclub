import Foundation
import UIKit
import UserNotifications

struct BrewReminderSchedule: Codable, Equatable, Identifiable {
    var id: UUID
    var weekdays: [Int]
    var hour: Int
    var minute: Int

    init(
        id: UUID = UUID(),
        weekdays: [Int] = BrewReminderSchedule.defaultWeekdays,
        hour: Int = 8,
        minute: Int = 30
    ) {
        self.id = id
        self.weekdays = weekdays.sorted()
        self.hour = hour
        self.minute = minute
    }

    var timeDate: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    var timeText: String {
        Self.timeFormatter.string(from: timeDate)
    }

    var daysText: String {
        let sortedDays = weekdays.sorted()
        if sortedDays == Self.defaultWeekdays {
            return "Every day"
        }
        if sortedDays == [2, 3, 4, 5, 6] {
            return "Weekdays"
        }
        if sortedDays == [1, 7] {
            return "Weekends"
        }
        return sortedDays
            .compactMap { Self.weekdayShortName(for: $0) }
            .joined(separator: ", ")
    }

    var normalized: BrewReminderSchedule {
        var copy = self
        copy.weekdays = Array(Set(weekdays)).sorted()
        return copy
    }

    static let defaultWeekdays = [1, 2, 3, 4, 5, 6, 7]

    static func weekdayShortName(for weekday: Int) -> String? {
        guard (1...7).contains(weekday) else { return nil }
        return Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    static func weekdayName(for weekday: Int) -> String? {
        guard (1...7).contains(weekday) else { return nil }
        return Calendar.current.weekdaySymbols[weekday - 1]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var localReminders: [BrewReminderSchedule] = []
    weak var auth: AuthClient?

    private static let legacyLocalReminderIdentifier = "daily-brew-reminder"
    private static let localReminderIdentifierPrefix = "brew-reminder"
    private static let reminderStorageKey = "notifications.brewReminders"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task {
            await refreshAuthorizationStatus()
            await refreshLocalReminderState()
        }
    }

    func bind(auth: AuthClient) { self.auth = auth }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func refreshLocalReminderState() async {
        let stored = Self.storedLocalReminders()
        if !stored.isEmpty {
            localReminders = stored
            return
        }

        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let legacy = Self.migratedLegacyReminder(from: requests) else {
            localReminders = []
            return
        }

        await replaceLocalReminders([legacy])
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
        guard authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        await upload(apnsToken: token)
    }

    func didFailToRegister(error: Error) {
        Log.error(error, category: "notifications.register")
    }

    private func upload(apnsToken token: String) async {
        guard let auth, let userID = auth.currentUserID else { return }
        let payload: [String: String] = [
            "user_id": userID.uuidString.lowercased(),
            "apns_token": token,
            "device_name": UIDevice.current.name,
            "bundle_id": Bundle.main.bundleIdentifier ?? "club.diald",
            "environment": Self.apnsEnvironment
        ]
        do {
            try await auth.supabase
                .from("device_tokens")
                .upsert(payload, onConflict: "user_id,apns_token")
                .execute()
            Log.breadcrumb("apns token uploaded", category: "notifications")
        } catch {
            Log.error(error, category: "notifications.token")
        }
    }

    func replaceLocalReminders(_ reminders: [BrewReminderSchedule]) async {
        let normalized = reminders
            .map(\.normalized)
            .filter { !$0.weekdays.isEmpty }

        localReminders = normalized
        Self.storeLocalReminders(normalized)
        await cancelScheduledLocalReminders()

        for reminder in normalized {
            await schedule(reminder: reminder)
        }
    }

    func upsertLocalReminder(_ reminder: BrewReminderSchedule) async {
        var next = localReminders
        if let index = next.firstIndex(where: { $0.id == reminder.id }) {
            next[index] = reminder
        } else {
            next.append(reminder)
        }
        await replaceLocalReminders(next)
    }

    func deleteLocalReminder(_ reminder: BrewReminderSchedule) async {
        await replaceLocalReminders(localReminders.filter { $0.id != reminder.id })
    }

    private func schedule(reminder: BrewReminderSchedule) async {
        let content = UNMutableNotificationContent()
        content.title = "Diald"
        content.body = "Log the morning cup before the variables evaporate."
        content.sound = .default

        for weekday in reminder.weekdays {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = reminder.hour
            components.minute = reminder.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.identifier(for: reminder.id, weekday: weekday),
                content: content,
                trigger: trigger
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Log.error(error, category: "notifications.local")
            }
        }
    }

    private func cancelScheduledLocalReminders() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter {
                $0 == Self.legacyLocalReminderIdentifier
                    || $0.hasPrefix("\(Self.localReminderIdentifierPrefix)-")
            }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func identifier(for reminderID: UUID, weekday: Int) -> String {
        "\(localReminderIdentifierPrefix)-\(reminderID.uuidString)-\(weekday)"
    }

    private static func storedLocalReminders() -> [BrewReminderSchedule] {
        guard let data = UserDefaults.standard.data(forKey: reminderStorageKey),
              let reminders = try? JSONDecoder().decode([BrewReminderSchedule].self, from: data) else {
            return []
        }
        return reminders.map(\.normalized)
    }

    private static func storeLocalReminders(_ reminders: [BrewReminderSchedule]) {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: reminderStorageKey)
    }

    private static func migratedLegacyReminder(from requests: [UNNotificationRequest]) -> BrewReminderSchedule? {
        guard let request = requests.first(where: { $0.identifier == legacyLocalReminderIdentifier }),
              let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            return nil
        }
        return BrewReminderSchedule(
            weekdays: BrewReminderSchedule.defaultWeekdays,
            hour: trigger.dateComponents.hour ?? 8,
            minute: trigger.dateComponents.minute ?? 30
        )
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
