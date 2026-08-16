import Foundation
import SwiftData

/// SwiftDataの`ModelContext`を通じて`UserProfile`を1件のみ保持・upsertする実装。
///
/// 複数プロファイルはMVP非対応（FR-5.4）のため、`save(_:)`実行時に他のレコードが残っていれば削除し、
/// 常に単一レコードへ収束させる。
final class SwiftDataProfileRepository: ProfileRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func currentProfile() throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func save(_ profile: UserProfile) throws {
        let existingProfiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        for existing in existingProfiles where existing !== profile {
            modelContext.delete(existing)
        }
        if profile.modelContext == nil {
            modelContext.insert(profile)
        }
        try modelContext.save()
    }
}
