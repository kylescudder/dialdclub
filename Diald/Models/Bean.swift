import Foundation
import PowerSync

enum RoastLevel: String, Codable, CaseIterable, Identifiable, Sendable {
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

struct CoffeeBean: Codable, Identifiable, Hashable, Sendable {
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

extension CoffeeBean {
    static func from(cursor: SqlCursor) -> CoffeeBean? {
        do {
            guard let id = UUID(uuidString: try cursor.getString(name: "id")),
                  let ownerID = UUID(uuidString: try cursor.getString(name: "owner_id")) else {
                return nil
            }
            let roastLevel = try cursor.getStringOptional(name: "roast_level")
                .flatMap(RoastLevel.init(rawValue:))
            return CoffeeBean(
                id: id,
                ownerID: ownerID,
                name: try cursor.getString(name: "name"),
                roaster: try cursor.getString(name: "roaster"),
                origin: try cursor.getStringOptional(name: "origin"),
                process: try cursor.getStringOptional(name: "process"),
                variety: try cursor.getStringOptional(name: "variety"),
                roastLevel: roastLevel,
                roastDate: parseISO8601Date(try cursor.getStringOptional(name: "roast_date")),
                tastingNotes: try cursor.getStringOptional(name: "tasting_notes"),
                archivedAt: parseISO8601Date(try cursor.getStringOptional(name: "archived_at")),
                createdAt: parseISO8601Date(try cursor.getStringOptional(name: "created_at")),
                updatedAt: parseISO8601Date(try cursor.getStringOptional(name: "updated_at")),
                deletedAt: parseISO8601Date(try cursor.getStringOptional(name: "deleted_at"))
            )
        } catch {
            return nil
        }
    }
}
