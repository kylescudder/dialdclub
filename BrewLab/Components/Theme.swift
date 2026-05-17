import SwiftUI

enum Theme {
    enum Colors {
        static let background = Color(red: 0.97, green: 0.95, blue: 0.91)
        static let surface = Color.white
        static let ink = Color(red: 0.13, green: 0.10, blue: 0.08)
        static let muted = Color(red: 0.45, green: 0.39, blue: 0.33)
        static let green = Color(red: 0.12, green: 0.42, blue: 0.27)
        static let amber = Color(red: 0.76, green: 0.44, blue: 0.18)
        static let blue = Color(red: 0.10, green: 0.32, blue: 0.50)
        static let line = Color.black.opacity(0.08)
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }
}
