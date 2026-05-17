import Foundation

enum RoastLevel: String, Codable, CaseIterable, Identifiable {
    case light, mediumLight = "medium_light", medium, mediumDark = "medium_dark", dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "Light"
        case .mediumLight: "Medium light"
        case .medium: "Medium"
        case .mediumDark: "Medium dark"
        case .dark: "Dark"
        }
    }
}

struct CoffeeBean: Codable, Identifiable, Hashable {
    let id: UUID
    var ownerID: UUID
    var name: String
    var roaster: String
    var origin: String?
    var process: String?
    var variety: String?
    var roastLevel: RoastLevel?
    var roastDate: Date?
    var tastingNotes: String?
    var archivedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, roaster, origin, process, variety
        case ownerID = "owner_id"
        case roastLevel = "roast_level"
        case roastDate = "roast_date"
        case tastingNotes = "tasting_notes"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var displayName: String { "\(roaster) \(name)" }
}
