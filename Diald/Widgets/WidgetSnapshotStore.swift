import Foundation

struct BrewDashboardSnapshot: Codable, Hashable {
    var totalBrews: Int
    var averageRating: Double?
    var averageExtractionSeconds: Double?
    var favouriteMethodLabel: String?
    var latestTitle: String?
    var latestMethodLabel: String?
    var latestExtractionSeconds: Int?
    var latestRating: Int?
    var latestBrewedAt: Date?
    var updatedAt: Date
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.club.diald"
    static let dashboardWidgetKind = "DialdDashboardWidget"

    private static let dashboardKey = "diald.widget.dashboard"

    static func dashboard() -> BrewDashboardSnapshot? {
        AppGroupStore.load(BrewDashboardSnapshot.self, forKey: dashboardKey)
    }

    static func saveDashboard(
        totalBrews: Int,
        averageRating: Double?,
        averageExtractionSeconds: Double?,
        favouriteMethodLabel: String?,
        latestTitle: String?,
        latestMethodLabel: String?,
        latestExtractionSeconds: Int?,
        latestRating: Int?,
        latestBrewedAt: Date?
    ) {
        let snapshot = BrewDashboardSnapshot(
            totalBrews: totalBrews,
            averageRating: averageRating,
            averageExtractionSeconds: averageExtractionSeconds,
            favouriteMethodLabel: favouriteMethodLabel,
            latestTitle: latestTitle,
            latestMethodLabel: latestMethodLabel,
            latestExtractionSeconds: latestExtractionSeconds,
            latestRating: latestRating,
            latestBrewedAt: latestBrewedAt,
            updatedAt: Date()
        )
        AppGroupStore.save(snapshot, forKey: dashboardKey)
    }
}
