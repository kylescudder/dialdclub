import Foundation
import Supabase

@MainActor
final class BrewsRepository: ObservableObject {
    @Published private(set) var brews: [BrewSession] = []
    @Published private(set) var isLoading = false

    private let auth: AuthClient

    init(auth: AuthClient) {
        self.auth = auth
    }

    func refresh() async {
        guard let userID = auth.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            brews = try await auth.supabase
                .from("brew_sessions")
                .select()
                .eq("owner_id", value: userID.uuidString.lowercased())
                .is("deleted_at", value: nil)
                .order("brewed_at", ascending: false)
                .limit(80)
                .execute()
                .value
        } catch {
            Log.error(error, category: "brews.refresh")
        }
    }

    func create(_ draft: BrewDraft) async {
        guard let userID = auth.currentUserID else { return }
        struct Payload: Encodable {
            let owner_id: String
            let bean_id: String?
            let method: BrewMethod
            let title: String
            let dose_grams: Double
            let yield_grams: Double?
            let water_grams: Double?
            let grind_setting: String?
            let water_temperature_c: Double?
            let extraction_seconds: Int
            let rating: Int?
            let notes: String?
            let brewed_at: Date
        }
        do {
            let payload = Payload(
                owner_id: userID.uuidString.lowercased(),
                bean_id: draft.beanID?.uuidString.lowercased(),
                method: draft.method,
                title: draft.title,
                dose_grams: draft.doseGrams,
                yield_grams: draft.yieldGrams,
                water_grams: draft.waterGrams,
                grind_setting: draft.grindSetting.nilIfBlank,
                water_temperature_c: draft.waterTemperatureC,
                extraction_seconds: draft.extractionSeconds,
                rating: draft.rating,
                notes: draft.notes.nilIfBlank,
                brewed_at: draft.brewedAt
            )
            try await auth.supabase.from("brew_sessions").insert(payload).execute()
            await refresh()
        } catch {
            Log.error(error, category: "brews.create")
        }
    }

    func softDelete(_ brew: BrewSession) async {
        do {
            try await auth.supabase
                .from("brew_sessions")
                .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: brew.id.uuidString.lowercased())
                .execute()
            await refresh()
        } catch {
            Log.error(error, category: "brews.delete")
        }
    }
}

struct BrewDraft {
    var beanID: UUID?
    var method: BrewMethod = .espresso
    var title = "Dial-in"
    var doseGrams = 18.0
    var yieldGrams: Double? = 36.0
    var waterGrams: Double?
    var grindSetting = ""
    var waterTemperatureC: Double? = 93
    var extractionSeconds = 30
    var rating: Int? = 4
    var notes = ""
    var brewedAt = Date()
}
