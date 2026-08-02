import SwiftUI

struct ResetPasswordSheet: View {
    @EnvironmentObject private var services: AppServices

    @State private var password = ""
    @State private var confirm = ""
    @State private var isBusy = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Choose a new password to finish signing in.")
                        .font(.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                        .padding()
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    SecureField("Confirm new password", text: $confirm)
                        .textContentType(.newPassword)
                        .padding()
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    if let error = localError ?? services.auth.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    PrimaryButton(title: "Save new password", isLoading: isBusy) {
                        Task { await save() }
                    }
                    .disabled(!isFormValid || isBusy)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Set a new password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") {
                        Task {
                            if await services.auth.signOut() {
                                await services.sync.wipe()
                                services.auth.isPasswordRecovery = false
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled()
        }
    }

    private var isFormValid: Bool {
        password.count >= 6 && password == confirm
    }

    private func save() async {
        isBusy = true
        defer { isBusy = false }
        localError = nil
        guard password == confirm else {
            localError = "Passwords don't match."
            return
        }
        if await services.auth.updatePassword(newPassword: password) {
            await services.sync.wipe()
        }
    }
}
