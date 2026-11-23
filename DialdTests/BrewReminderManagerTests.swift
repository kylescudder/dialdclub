import Foundation
import XCTest
@testable import Diald

/// Diald's local brew reminders are stored on-device and never touch push
/// registration (`PushManager` owns that).
@MainActor
final class BrewReminderManagerTests: XCTestCase {
    private let storageKey = "notifications.brewReminders.signed-out"
    private var previous: Data?

    override func setUp() async throws {
        previous = UserDefaults.standard.data(forKey: storageKey)
    }

    override func tearDown() async throws {
        if let previous {
            UserDefaults.standard.set(previous, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    func testReplacingRemindersNormalizesAndDropsEmptySchedules() async {
        let manager = BrewReminderManager()
        let weekdays = BrewReminderSchedule(weekdays: [6, 2, 2, 4], hour: 7, minute: 15)
        let empty = BrewReminderSchedule(weekdays: [], hour: 9, minute: 0)

        await manager.replaceLocalReminders([weekdays, empty])

        XCTAssertEqual(manager.localReminders.map(\.weekdays), [[2, 4, 6]])
        let reloaded = BrewReminderManager()
        XCTAssertEqual(reloaded.localReminders, manager.localReminders)

        await manager.replaceLocalReminders([])
        XCTAssertTrue(manager.localReminders.isEmpty)
        XCTAssertTrue(BrewReminderManager().localReminders.isEmpty)
    }

    func testAccountSchedulesAreRetainedWithoutBeingShared() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let first = UUID(), second = UUID()
        let schedule = BrewReminderSchedule(weekdays: [2], hour: 9, minute: 15)
        let original = BrewReminderManager(owner: first, defaults: defaults)
        await original.replaceLocalReminders([schedule])
        await original.suspend()
        let other = BrewReminderManager(owner: second, defaults: defaults)
        XCTAssertTrue(other.localReminders.isEmpty)
        let returning = BrewReminderManager(owner: first, defaults: defaults)
        XCTAssertEqual(returning.localReminders, [schedule])
        await returning.replaceLocalReminders([])
    }

    func testScheduleDescribesCommonWeekdaySets() {
        XCTAssertEqual(BrewReminderSchedule().daysText, "Every day")
        XCTAssertEqual(BrewReminderSchedule(weekdays: [2, 3, 4, 5, 6]).daysText, "Weekdays")
        XCTAssertEqual(BrewReminderSchedule(weekdays: [7, 1]).daysText, "Weekends")
    }
}
