import Foundation

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Date {
    var iso8601: String {
        ISO8601DateFormatter.dialdFractional.string(from: self)
    }
}

func parseISO8601Date(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    return ISO8601DateFormatter.dialdFractional.date(from: value)
        ?? ISO8601DateFormatter.dialdInternetDateTime.date(from: value)
        ?? ISO8601DateFormatter.dialdFullDate.date(from: value)
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let dialdInternetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) static let dialdFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let dialdFullDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
