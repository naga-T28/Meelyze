import Foundation

/// MVP対象の食事制限区分。
///
/// `docs/requirements.md`用語集の「食事制限 (Dietary Restriction)」は「ハラール、ベジタリアン、ヴィーガン、
/// ノンアルコール等」を例示するのみで確定リストではない。本カタログはMVP時点の採用候補であり、
/// 対象区分の増減は本Enumの更新のみで対応する（`task/README-issue11.md`「前提となる設計判断」参照）。
enum DietaryRestrictionCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case halal
    case vegetarian
    case vegan
    case nonAlcoholic

    var id: String { rawValue }

    /// メニュー原文の言語である日本語表示名。
    var japaneseName: String { localizedNames.japanese }

    /// MVP対象の表示言語における表示名。
    func localizedName(for language: DisplayLanguage) -> String {
        switch language {
        case .english:
            return localizedNames.english
        case .traditionalChinese:
            return localizedNames.traditionalChinese
        case .simplifiedChinese:
            return localizedNames.simplifiedChinese
        case .korean:
            return localizedNames.korean
        }
    }

    private var localizedNames: LocalizedRestrictionNames {
        switch self {
        case .halal:
            return LocalizedRestrictionNames(japanese: "ハラール", english: "Halal", traditionalChinese: "清真", simplifiedChinese: "清真", korean: "할랄")
        case .vegetarian:
            return LocalizedRestrictionNames(japanese: "ベジタリアン", english: "Vegetarian", traditionalChinese: "素食", simplifiedChinese: "素食", korean: "채식")
        case .vegan:
            return LocalizedRestrictionNames(japanese: "ヴィーガン", english: "Vegan", traditionalChinese: "純素", simplifiedChinese: "纯素", korean: "비건")
        case .nonAlcoholic:
            return LocalizedRestrictionNames(japanese: "ノンアルコール", english: "Non-alcohol", traditionalChinese: "無酒精", simplifiedChinese: "无酒精", korean: "무알코올")
        }
    }
}

private struct LocalizedRestrictionNames {
    let japanese: String
    let english: String
    let traditionalChinese: String
    let simplifiedChinese: String
    let korean: String
}
