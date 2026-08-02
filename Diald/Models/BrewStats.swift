import Foundation

struct BrewStats: Codable, Hashable, Sendable {
    var totalBrews: Int
    var averageRating: Double?
    var averageExtractionSeconds: Double?
    var favouriteMethod: BrewMethod?

    enum CodingKeys: String, CodingKey {
        case totalBrews = "total_brews"
        case averageRating = "average_rating"
        case averageExtractionSeconds = "average_extraction_seconds"
        case favouriteMethod = "favourite_method"
    }
}
