import Foundation
import PowerSync

enum BrewMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case espresso, v60, aeropress, chemex, clever, moka, frenchPress = "french_press", other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .espresso: "Espresso"
        case .v60: "V60"
        case .aeropress: "AeroPress"
        case .chemex: "Chemex"
        case .clever: "Clever"
        case .moka: "Moka"
        case .frenchPress: "French press"
        case .other: "Other"
        }
    }
}

struct BrewSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var ownerID: UUID
    var beanID: UUID?
    var method: BrewMethod
    var title: String
    var doseGrams: Double
    var yieldGrams: Double?
    var waterGrams: Double?
    var grindSetting: String?
    var waterTemperatureC: Double?
    var extractionSeconds: Int
    var rating: Int?
    var acidity: Int?
    var sweetness: Int?
    var body: Int?
    var clarity: Int?
    var notes: String?
    var brewedAt: Date
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, method, title, rating, acidity, sweetness, body, clarity, notes
        case ownerID = "owner_id"
        case beanID = "bean_id"
        case doseGrams = "dose_grams"
        case yieldGrams = "yield_grams"
        case waterGrams = "water_grams"
        case grindSetting = "grind_setting"
        case waterTemperatureC = "water_temperature_c"
        case extractionSeconds = "extraction_seconds"
        case brewedAt = "brewed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var ratioText: String {
        guard let yieldGrams, doseGrams > 0 else { return "n/a" }
        return String(format: "1:%.1f", yieldGrams / doseGrams)
    }

    var timeText: String {
        "\(extractionSeconds / 60):" + String(format: "%02d", extractionSeconds % 60)
    }
}

extension BrewSession {
    static func from(cursor: SqlCursor) -> BrewSession? {
        do {
            guard let id = UUID(uuidString: try cursor.getString(name: "id")),
                  let ownerID = UUID(uuidString: try cursor.getString(name: "owner_id")),
                  let method = BrewMethod(rawValue: try cursor.getString(name: "method")),
                  let brewedAt = parseISO8601Date(try cursor.getStringOptional(name: "brewed_at")) else {
                return nil
            }
            let beanID = try cursor.getStringOptional(name: "bean_id").flatMap(UUID.init(uuidString:))
            return BrewSession(
                id: id,
                ownerID: ownerID,
                beanID: beanID,
                method: method,
                title: try cursor.getString(name: "title"),
                doseGrams: try cursor.getDouble(name: "dose_grams"),
                yieldGrams: try cursor.getDoubleOptional(name: "yield_grams"),
                waterGrams: try cursor.getDoubleOptional(name: "water_grams"),
                grindSetting: try cursor.getStringOptional(name: "grind_setting"),
                waterTemperatureC: try cursor.getDoubleOptional(name: "water_temperature_c"),
                extractionSeconds: try cursor.getInt(name: "extraction_seconds"),
                rating: try cursor.getIntOptional(name: "rating"),
                acidity: try cursor.getIntOptional(name: "acidity"),
                sweetness: try cursor.getIntOptional(name: "sweetness"),
                body: try cursor.getIntOptional(name: "body"),
                clarity: try cursor.getIntOptional(name: "clarity"),
                notes: try cursor.getStringOptional(name: "notes"),
                brewedAt: brewedAt,
                createdAt: parseISO8601Date(try cursor.getStringOptional(name: "created_at")),
                updatedAt: parseISO8601Date(try cursor.getStringOptional(name: "updated_at")),
                deletedAt: parseISO8601Date(try cursor.getStringOptional(name: "deleted_at"))
            )
        } catch {
            return nil
        }
    }
}
