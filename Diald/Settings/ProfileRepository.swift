import Foundation

@MainActor
final class ProfileRepository: ObservableObject {
    @Published private(set) var profile: Profile?
    @Published private(set) var isLoading = false

    private let auth: AuthClient

    init(auth: AuthClient) {
        self.auth = auth
    }

    func refresh() async {
        guard let userID = auth.currentUserID else {
            profile = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await auth.supabase
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString.lowercased())
                .is("deleted_at", value: nil)
                .single()
                .execute()
                .value
        } catch {
            Log.error(error, category: "profile.refresh")
        }
    }

    func updateDisplayName(_ name: String) async {
        guard let userID = auth.currentUserID else { return }
        do {
            try await auth.supabase
                .from("profiles")
                .update(["display_name": name])
                .eq("id", value: userID.uuidString.lowercased())
                .execute()
            await refresh()
        } catch {
            Log.error(error, category: "profile.updateDisplayName")
        }
    }
}
