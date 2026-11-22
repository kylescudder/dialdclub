import Foundation
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

/// Diald's local brew reminders: recurring calendar notifications stored on
/// the device. Push registration is the shared `PushManager`.
@MainActor
final class BrewReminderManager: ObservableObject {
    static let shared = BrewReminderManager()

    @Published private(set) var localReminders: [BrewReminderSchedule] = []

    private static let localReminderIdentifierPrefix = "brew-reminder"
    private static let reminderStorageKey = "notifications.brewReminders"
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        localReminders = Self.storedLocalReminders()
    }

    func refreshLocalReminderState() async {
        localReminders = Self.storedLocalReminders()
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
                try await notificationCenter.add(request)
            } catch {
                Log.error(error, category: "notifications.local")
            }
        }
    }

    private func cancelScheduledLocalReminders() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix("\(Self.localReminderIdentifierPrefix)-") }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
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
}
