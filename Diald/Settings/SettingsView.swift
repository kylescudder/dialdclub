import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showFinalDeleteConfirm = false
    @State private var deleteError: String?
    @State private var isDeleting = false
    @State private var successCount = 0
    @State private var errorCount = 0
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Profile") {
                if let profile = services.profile.profile {
                    HStack {
                        Text("Display name")
                        Spacer()
                        Text(profile.displayName ?? "Not set")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                } else if services.profile.isLoading {
                    ProgressView()
                }
                NavigationLink("Edit display name") {
                    EditDisplayNameView(initial: services.profile.profile?.displayName ?? "")
                }
            }

            Section {
                if services.notifications.localReminders.isEmpty {
                    Text("No brew reminders")
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    ForEach(services.notifications.localReminders) { reminder in
                        NavigationLink {
                            ReminderEditorView(reminder: reminder)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.timeText)
                                    .font(.headline.monospacedDigit())
                                Text(reminder.daysText)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        Task {
                            let reminders = services.notifications.localReminders
                            for index in offsets {
                                await services.notifications.deleteLocalReminder(reminders[index])
                            }
                        }
                    }
                }
                NavigationLink {
                    ReminderEditorView(reminder: BrewReminderSchedule())
                } label: {
                    Label("Add reminder", systemImage: "plus.circle")
                }
                NotificationSettingsRow()
            } header: {
                Text("Notifications")
            } footer: {
                Text("Set different brew reminder times for office days, weekends, or any weekly routine.")
            }

            Section {
                LabeledContent(
                    "Plan",
                    value: services.billing.isSubscribed ? "Supporter Monthly" : "Free"
                )
                if services.billing.isSubscribed {
                    Button("Manage subscription") {
                        Task { await services.billing.manageSubscriptions() }
                    }
                } else {
                    Button("Upgrade to Supporter Monthly") {
                        showPaywall = true
                    }
                }
                Button("Restore purchases") {
                    Task { await services.billing.restorePurchases() }
                }
                if let message = services.billing.lastError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Subscription")
            } footer: {
                Text("Free accounts can log up to \(AppServices.freeExtractionLimit) lifetime extractions; deleted extractions still count. Manage subscription opens Apple's system sheet, where you can cancel or change the subscription.")
            }

            Section("AI provider") {
                NavigationLink("OpenAI / Anthropic access") {
                    AIProviderSettingsView()
                }
                LabeledContent("Selected", value: services.aiSettings.provider.label)
                LabeledContent("API key", value: services.aiSettings.hasActiveAPIKey ? "Configured" : "Not configured")
            }

            Section("Account") {
                if case let .signedIn(_, email) = services.auth.state, let email {
                    LabeledContent("Signed in as", value: email)
                }
                Button("Sign out", role: .destructive) {
                    showSignOutConfirm = true
                }
                Button("Delete account", role: .destructive) {
                    showDeleteConfirm = true
                }
                .disabled(isDeleting)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Link("View Diald on GitHub", destination: URL(string: "https://github.com/kylescudder/dialdclub")!)
            }
        }
        .navigationTitle("Settings")
        .task {
            await services.notifications.refreshLocalReminderState()
        }
        .alert("Sign out of Diald?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await services.auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete your Diald account?", isPresented: $showDeleteConfirm) {
            Button("Continue", role: .destructive) {
                showFinalDeleteConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your beans, brews, reminders, devices, and account. This cannot be undone.")
        }
        .alert("Are you absolutely sure?", isPresented: $showFinalDeleteConfirm) {
            Button("Delete forever", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your data will be deleted immediately.")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        ), presenting: deleteError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .sensoryFeedback(.success, trigger: successCount)
        .sensoryFeedback(.error, trigger: errorCount)
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await services.auth.deleteAccount()
            successCount += 1
        } catch {
            deleteError = error.localizedDescription
            errorCount += 1
        }
    }

}

private struct NotificationSettingsRow: View {
    @ObservedObject private var notifications = NotificationManager.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch notifications.authorizationStatus {
        case .authorized, .ephemeral, .provisional:
            Label("Push notifications allowed", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label("Push notifications disabled in iOS Settings", systemImage: "xmark.seal")
                    .foregroundStyle(.red)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        case .notDetermined:
            Button("Turn on push notifications") {
                Task { await notifications.requestAuthorization() }
            }
        @unknown default:
            Text("Push notification status unknown")
        }
    }
}

private struct ReminderEditorView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: BrewReminderSchedule
    @State private var time: Date
    @State private var saveCount = 0

    init(reminder: BrewReminderSchedule) {
        self._reminder = State(initialValue: reminder)
        self._time = State(initialValue: reminder.timeDate)
    }

    var body: some View {
        Form {
            Section("Time") {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
            }

            Section("Repeat") {
                ForEach(BrewReminderSchedule.defaultWeekdays, id: \.self) { weekday in
                    Button {
                        toggle(weekday)
                    } label: {
                        HStack {
                            Text(BrewReminderSchedule.weekdayName(for: weekday) ?? "")
                            Spacer()
                            if reminder.weekdays.contains(weekday) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .navigationTitle("Brew reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        reminder.hour = components.hour ?? reminder.hour
                        reminder.minute = components.minute ?? reminder.minute
                        await services.notifications.upsertLocalReminder(reminder.normalized)
                        saveCount += 1
                        dismiss()
                    }
                }
                .disabled(reminder.weekdays.isEmpty)
            }
        }
        .sensoryFeedback(.success, trigger: saveCount)
    }

    private func toggle(_ weekday: Int) {
        if reminder.weekdays.contains(weekday) {
            reminder.weekdays.removeAll { $0 == weekday }
        } else {
            reminder.weekdays.append(weekday)
            reminder.weekdays.sort()
        }
    }
}

private struct EditDisplayNameView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var didSeed = false
    @State private var isSaving = false
    @State private var saveCount = 0

    init(initial: String) {
        self._name = State(initialValue: initial)
        self._didSeed = State(initialValue: !initial.isEmpty)
    }

    var body: some View {
        Form {
            TextField("Display name", text: $name)
                .textContentType(.name)
        }
        .navigationTitle("Display name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        isSaving = true
                        await services.profile.updateDisplayName(name.trimmingCharacters(in: .whitespaces))
                        isSaving = false
                        saveCount += 1
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .task(id: services.profile.profile?.displayName) {
            if !didSeed, let value = services.profile.profile?.displayName, !value.isEmpty {
                name = value
                didSeed = true
            }
        }
    }
}
