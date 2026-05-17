import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var services: AppServices
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.Colors.green)
                    Text("BrewLab")
                        .font(.largeTitle.bold())
                    Text("Track extractions, beans, recipes, and the tiny changes that actually matter.")
                        .font(.callout)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                }

                Card {
                    VStack(spacing: Theme.Spacing.md) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if isCreatingAccount {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        SecureField("Password", text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)

                        PrimaryButton(
                            title: isCreatingAccount ? "Create account" : "Sign in",
                            systemImage: "arrow.right",
                            isLoading: isBusy
                        ) {
                            Task { await submit() }
                        }

                        Button(isCreatingAccount ? "I already have an account" : "Create an account") {
                            isCreatingAccount.toggle()
                        }
                        .font(.footnote.weight(.medium))

                        SignInWithAppleButton(.continue) { request in
                            services.auth.beginAppleSignIn(request: request)
                        } onCompletion: { result in
                            Task { await services.auth.completeAppleSignIn(result: result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 46)

                        Button {
                            Task { await services.auth.signInWithGoogle() }
                        } label: {
                            Label("Continue with Google", systemImage: "g.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let error = services.auth.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .background(Theme.Colors.background)
        }
    }

    private func submit() async {
        isBusy = true
        defer { isBusy = false }
        if isCreatingAccount {
            await services.auth.signUp(email: email, password: password, username: username)
        } else {
            await services.auth.signIn(email: email, password: password)
        }
    }
}
