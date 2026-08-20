import Foundation
import SwiftData

/// 食品表示上のアレルゲンを表すマスタ。
///
/// `id`は`AllergenItem.rawValue`と揃え、ユーザーが選択したアレルギー情報と照合できるようにする。
@Model
final class Allergen {
    @Attribute(.unique) var id: String
    var japaneseName: String

    init(id: String, japaneseName: String) {
        self.id = id
        self.japaneseName = japaneseName
    }
}
