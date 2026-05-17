import Foundation
import Supabase

@MainActor
final class BeansRepository: ObservableObject {
    @Published private(set) var beans: [CoffeeBean] = []
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
            beans = try await auth.supabase
                .from("beans")
                .select()
                .eq("owner_id", value: userID.uuidString.lowercased())
                .is("deleted_at", value: nil)
                .order("updated_at", ascending: false)
                .execute()
                .value
        } catch {
            Log.error(error, category: "beans.refresh")
        }
    }

    func create(name: String, roaster: String, origin: String?, process: String?, roastLevel: RoastLevel?) async {
        guard let userID = auth.currentUserID else { return }
        struct Payload: Encodable {
            let owner_id: String
            let name: String
            let roaster: String
            let origin: String?
            let process: String?
            let roast_level: RoastLevel?
        }
        do {
            let payload = Payload(
                owner_id: userID.uuidString.lowercased(),
                name: name,
                roaster: roaster,
                origin: origin?.nilIfBlank,
                process: process?.nilIfBlank,
                roast_level: roastLevel
            )
            try await auth.supabase.from("beans").insert(payload).execute()
            await refresh()
        } catch {
            Log.error(error, category: "beans.create")
        }
    }

    func softDelete(_ bean: CoffeeBean) async {
        do {
            try await auth.supabase
                .from("beans")
                .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: bean.id.uuidString.lowercased())
                .execute()
            await refresh()
        } catch {
            Log.error(error, category: "beans.delete")
        }
    }
}
