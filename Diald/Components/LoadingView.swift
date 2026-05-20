import SwiftUI

struct LoadingView: View {
    var message = "Dialling in..."

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            LottieAnimationView(name: "brew_spinner.lottie")
                .frame(width: 96, height: 96)
                .fixedSize()
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.Colors.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}
