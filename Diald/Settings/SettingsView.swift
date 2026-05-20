import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @State private var reminderEnabled = false
    @State private var reminderDate = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    Toggle("Morning brew reminder", isOn: $reminderEnabled)
                    DatePicker("Time", selection: $reminderDate, displayedComponents: .hourAndMinute)
                    Button("Apply reminder") {
                        Task {
                            if reminderEnabled {
                                await services.notifications.scheduleLocalReminder(at: reminderDate)
                            } else {
                                services.notifications.cancelLocalReminder()
                            }
                        }
                    }
                    Button("Enable push notifications") {
                        Task { _ = await services.notifications.requestAuthorization() }
                    }
                }

                Section("Account") {
                    Button("Sign out", role: .destructive) {
                        Task { await services.auth.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
