import SwiftUI

enum Theme {
    enum Colors {
        static let accent = Color.accentColor
        static let background = Color(.systemGroupedBackground)
        static let surface = Color(.secondarySystemGroupedBackground)
        static let surfaceElevated = Color(.tertiarySystemGroupedBackground)
        static let separator = Color(.separator)
        static let textPrimary = Color(.label)
        static let textSecondary = Color(.secondaryLabel)
        static let textTertiary = Color(.tertiaryLabel)

        static let ink = textPrimary
        static let muted = textSecondary
        static let green = accent
        static let amber = Color(red: 0.76, green: 0.44, blue: 0.18)
        static let blue = Color(red: 0.10, green: 0.32, blue: 0.50)
        static let line = separator
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let iconRow: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }
}

extension View {
    func captionSecondary() -> some View {
        font(.caption).foregroundStyle(Theme.Colors.textSecondary)
    }

    func footnoteSecondary() -> some View {
        font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
    }
}
