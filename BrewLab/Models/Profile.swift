import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String?
    var displayName: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
