import Foundation
import SwiftData

/// 初期データImportの実行済みバージョンを記録するモデル。
///
/// 同じJSONを複数回読み込んでも、料理・食材・関連を重複登録しないために使う。
@Model
final class DataImportVersion {
    @Attribute(.unique) var id: String
    var importedAt: Date

    init(id: String, importedAt: Date = Date()) {
        self.id = id
        self.importedAt = importedAt
    }
}
