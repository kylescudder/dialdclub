import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var services: AppServices
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.sm) {
                    Image("AppLogoIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    Text("Diald")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Track extractions, beans, recipes, and the tiny changes that actually matter.")
                        .font(.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.xxl)

                VStack(spacing: Theme.Spacing.md) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    HStack {
                        Spacer()
                        Button("Forgot password?") { showForgotPassword = true }
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }

                if let error = services.auth.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: Theme.Spacing.md) {
                    PrimaryButton(title: "Sign in", isLoading: isBusy) {
                        Task { await signIn() }
                    }
                    .disabled(!isFormValid)

                    HStack {
                        Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                        Text("or").font(.footnote).foregroundStyle(Theme.Colors.textTertiary)
                        Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                    }

                    AppleSignInButton()
                        .frame(height: 50)

                    SecondaryButton(
                        title: "Continue with Google",
                        assetImage: "GoogleLogo",
                        iconTextSpacing: 12,
                        titleFont: .custom("Roboto-Medium", size: 17, relativeTo: .body)
                    ) {
                        Task {
                            isBusy = true
                            await services.auth.signInWithGoogle()
                            isBusy = false
                        }
                    }
                }

                if services.auth.requiresReauthentication {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Sign in with your original account to keep your offline changes, or sign out to use another account.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Sign out and discard local data", role: .destructive) {
                            showDiscardConfirmation = true
                        }
                    }
                }

                Button("Create an account") { showSignUp = true }
                    .font(.callout)
                    .padding(.top, Theme.Spacing.sm)
            }
            .disabled(isBusy)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Colors.background)
        .scrollDismissesKeyboard(.interactively)
        .alert("Discard local data and sign out?", isPresented: $showDiscardConfirmation) {
            Button("Discard and sign out", role: .destructive) {
                Task { await discardLocalAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes this account’s data from this device, including any changes that have not synced. Synced data stays in your account. You can then sign in with another account.")
        }
        .navigationDestination(isPresented: $showSignUp) { SignUpView() }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(initialEmail: email)
                .presentationDetents([.medium, .large])
        }
    }

    private var isFormValid: Bool {
        !email.isEmpty && password.count >= 6
    }

    private func discardLocalAccount() async {
        isBusy = true
        defer { isBusy = false }
        if await services.auth.signOut() {
            await services.sync.wipe()
            services.auth.lastError = nil
            email = ""
            password = ""
        }
    }

    private func signIn() async {
        isBusy = true
        defer { isBusy = false }
        await services.auth.signIn(email: email, password: password)
    }
}
