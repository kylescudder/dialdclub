import SwiftUI

/// Diald-only design tokens layered on the shared `Theme`.
extension Theme {
    /// Lottie animation shown by `LoadingView`.
    static let loadingAnimation = "brew_spinner.lottie"

    /// `Card`: compact, sized to its content, with a separator border.
    enum CardStyle {
        static let padding = Theme.Spacing.md
        static let cornerRadius = Theme.Radius.md
        static let fillsWidth = false
        static let showsBorder = true
    }
}

extension Theme.Colors {
    static let amber = Color(red: 0.76, green: 0.44, blue: 0.18)
    static let blue = Color(red: 0.10, green: 0.32, blue: 0.50)
}
