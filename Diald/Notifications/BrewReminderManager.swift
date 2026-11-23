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
    private let reminderStorageKey: String
    private let defaults: UserDefaults
    private var generation = 0
    private let notificationCenter: UNUserNotificationCenter

    init(owner: UUID? = nil, legacyOwner: UUID? = nil, defaults: UserDefaults = .standard, notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        reminderStorageKey = "notifications.brewReminders.\(owner?.uuidString.lowercased() ?? "signed-out")"
        if let owner, owner == legacyOwner, defaults.data(forKey: reminderStorageKey) == nil,
           let legacy = defaults.data(forKey: "notifications.brewReminders") {
            defaults.set(legacy, forKey: reminderStorageKey)
            defaults.removeObject(forKey: "notifications.brewReminders")
        }
        localReminders = storedLocalReminders()
    }

    /// Stop notifications on sign-out without deleting saved schedules.
    func suspend() async {
        generation += 1
        await cancelScheduledLocalReminders()
    }

    func resume() async {
        await replaceLocalReminders(storedLocalReminders())
    }

    func refreshLocalReminderState() async {
        localReminders = storedLocalReminders()
    }

    func replaceLocalReminders(_ reminders: [BrewReminderSchedule]) async {
        generation += 1
        let expected = generation
        let normalized = reminders
            .map(\.normalized)
            .filter { !$0.weekdays.isEmpty }

        localReminders = normalized
        storeLocalReminders(normalized)
        await cancelScheduledLocalReminders()

        for reminder in normalized {
            guard generation == expected else { return }
            await schedule(reminder: reminder, generation: expected)
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

    private func schedule(reminder: BrewReminderSchedule, generation expected: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Diald"
        content.body = "Log the morning cup before the variables evaporate."
        content.sound = .default

        for weekday in reminder.weekdays {
            guard generation == expected else { return }
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
                if generation != expected { notificationCenter.removePendingNotificationRequests(withIdentifiers: [request.identifier]) }
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

    private func storedLocalReminders() -> [BrewReminderSchedule] {
        guard let data = defaults.data(forKey: reminderStorageKey),
              let reminders = try? JSONDecoder().decode([BrewReminderSchedule].self, from: data) else {
            return []
        }
        return reminders.map(\.normalized)
    }

    private func storeLocalReminders(_ reminders: [BrewReminderSchedule]) {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: reminderStorageKey)
    }
}
