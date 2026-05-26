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

    func update(_ brew: BrewSession, with draft: BrewDraft) async {
        struct Payload: Encodable {
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
            let updated_at: Date

            enum CodingKeys: String, CodingKey {
                case bean_id
                case method
                case title
                case dose_grams
                case yield_grams
                case water_grams
                case grind_setting
                case water_temperature_c
                case extraction_seconds
                case rating
                case notes
                case brewed_at
                case updated_at
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(bean_id, forKey: .bean_id)
                if bean_id == nil { try container.encodeNil(forKey: .bean_id) }
                try container.encode(method, forKey: .method)
                try container.encode(title, forKey: .title)
                try container.encode(dose_grams, forKey: .dose_grams)
                try container.encodeIfPresent(yield_grams, forKey: .yield_grams)
                if yield_grams == nil { try container.encodeNil(forKey: .yield_grams) }
                try container.encodeIfPresent(water_grams, forKey: .water_grams)
                if water_grams == nil { try container.encodeNil(forKey: .water_grams) }
                try container.encodeIfPresent(grind_setting, forKey: .grind_setting)
                if grind_setting == nil { try container.encodeNil(forKey: .grind_setting) }
                try container.encodeIfPresent(water_temperature_c, forKey: .water_temperature_c)
                if water_temperature_c == nil { try container.encodeNil(forKey: .water_temperature_c) }
                try container.encode(extraction_seconds, forKey: .extraction_seconds)
                try container.encodeIfPresent(rating, forKey: .rating)
                if rating == nil { try container.encodeNil(forKey: .rating) }
                try container.encodeIfPresent(notes, forKey: .notes)
                if notes == nil { try container.encodeNil(forKey: .notes) }
                try container.encode(brewed_at, forKey: .brewed_at)
                try container.encode(updated_at, forKey: .updated_at)
            }
        }
        do {
            let payload = Payload(
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
                brewed_at: draft.brewedAt,
                updated_at: Date()
            )
            try await auth.supabase
                .from("brew_sessions")
                .update(payload)
                .eq("id", value: brew.id.uuidString.lowercased())
                .execute()
            await refresh()
        } catch {
            Log.error(error, category: "brews.update")
        }
    }

    func createdExtractionCount() async -> Int {
        guard let userID = auth.currentUserID else { return 0 }
        struct Row: Decodable {
            let id: UUID
        }
        do {
            let rows: [Row] = try await auth.supabase
                .from("brew_sessions")
                .select("id")
                .eq("owner_id", value: userID.uuidString.lowercased())
                .is("deleted_at", value: nil)
                .limit(AppServices.freeExtractionLimit + 1)
                .execute()
                .value
            return rows.count
        } catch {
            Log.error(error, category: "brews.count")
            return brews.count
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

    init() {}

    init(brew: BrewSession) {
        beanID = brew.beanID
        method = brew.method
        title = brew.title
        doseGrams = brew.doseGrams
        yieldGrams = brew.yieldGrams
        waterGrams = brew.waterGrams
        grindSetting = brew.grindSetting ?? ""
        waterTemperatureC = brew.waterTemperatureC
        extractionSeconds = brew.extractionSeconds
        rating = brew.rating
        notes = brew.notes ?? ""
        brewedAt = brew.brewedAt
    }
}
