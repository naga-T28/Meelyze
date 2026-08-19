import Foundation
import SwiftData

/// 料理・食材・判定タグの根拠となる情報源。
@Model
final class EvidenceSource {
    @Attribute(.unique) var id: String
    var name: String
    var urlString: String
    var checkedAt: String
    var notes: String

    init(id: String, name: String, urlString: String, checkedAt: String, notes: String = "") {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.checkedAt = checkedAt
        self.notes = notes
    }
}
