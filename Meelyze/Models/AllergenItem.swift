import Foundation

/// 特定原材料9品目・特定原材料に準ずるもの20品目（計29品目）のカタログ。
///
/// 出典: 消費者庁「食物アレルギー表示に関する情報」（令和8年4月1日施行の食品表示基準改正を反映）。
/// 2023年3月にくるみ、2026年4月にカシューナッツが特定原材料（表示義務）へ追加され、特定原材料に
/// 準ずるものは2024年3月にまつたけを削除してマカダミアナッツを追加、2026年4月にカシューナッツが
/// 特定原材料へ移った分の後任としてピスタチオを追加した（8+20=28品目から9+20=29品目へ拡大）。
/// 品目は今後も法令改正により変わり得るため、着手時点で消費者庁の最新公表資料を再確認すること
/// （`task/README-issue11.md`「前提となる設計判断」参照）。
enum AllergenItem: String, CaseIterable, Identifiable, Hashable, Sendable {
    // 特定原材料（表示義務9品目）
    case egg
    case milk
    case wheat
    case buckwheat
    case peanut
    case shrimp
    case crab
    case walnut
    case cashewNut

    // 特定原材料に準ずるもの（表示推奨20品目、五十音順）
    case almond
    case abalone
    case squid
    case salmonRoe
    case orange
    case kiwiFruit
    case beef
    case sesame
    case salmon
    case mackerel
    case soybean
    case chicken
    case banana
    case pork
    case pistachio
    case macadamiaNut
    case peach
    case yam
    case apple
    case gelatin

    var id: String { rawValue }

    /// 特定原材料（表示義務9品目）であれば`true`、特定原材料に準ずるもの（表示推奨20品目）であれば`false`。
    var isMandatory: Bool {
        switch self {
        case .egg, .milk, .wheat, .buckwheat, .peanut, .shrimp, .crab, .walnut, .cashewNut:
            return true
        default:
            return false
        }
    }

    /// 特定原材料9品目（表示義務）。
    static var mandatoryItems: [AllergenItem] {
        allCases.filter(\.isMandatory)
    }

    /// 特定原材料に準ずるもの20品目（表示推奨）。
    static var recommendedItems: [AllergenItem] {
        allCases.filter { !$0.isMandatory }
    }

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

    private var localizedNames: LocalizedAllergenNames {
        switch self {
        case .egg:
            return LocalizedAllergenNames(japanese: "卵", english: "Egg", traditionalChinese: "蛋", simplifiedChinese: "蛋", korean: "계란")
        case .milk:
            return LocalizedAllergenNames(japanese: "乳", english: "Milk", traditionalChinese: "乳製品", simplifiedChinese: "乳制品", korean: "우유")
        case .wheat:
            return LocalizedAllergenNames(japanese: "小麦", english: "Wheat", traditionalChinese: "小麥", simplifiedChinese: "小麦", korean: "밀")
        case .buckwheat:
            return LocalizedAllergenNames(japanese: "そば", english: "Buckwheat", traditionalChinese: "蕎麥", simplifiedChinese: "荞麦", korean: "메밀")
        case .peanut:
            return LocalizedAllergenNames(japanese: "落花生（ピーナッツ）", english: "Peanut", traditionalChinese: "花生", simplifiedChinese: "花生", korean: "땅콩")
        case .shrimp:
            return LocalizedAllergenNames(japanese: "えび", english: "Shrimp", traditionalChinese: "蝦", simplifiedChinese: "虾", korean: "새우")
        case .crab:
            return LocalizedAllergenNames(japanese: "かに", english: "Crab", traditionalChinese: "蟹", simplifiedChinese: "蟹", korean: "게")
        case .walnut:
            return LocalizedAllergenNames(japanese: "くるみ", english: "Walnut", traditionalChinese: "核桃", simplifiedChinese: "核桃", korean: "호두")
        case .cashewNut:
            return LocalizedAllergenNames(japanese: "カシューナッツ", english: "Cashew nut", traditionalChinese: "腰果", simplifiedChinese: "腰果", korean: "캐슈넛")
        case .almond:
            return LocalizedAllergenNames(japanese: "アーモンド", english: "Almond", traditionalChinese: "杏仁", simplifiedChinese: "杏仁", korean: "아몬드")
        case .abalone:
            return LocalizedAllergenNames(japanese: "あわび", english: "Abalone", traditionalChinese: "鮑魚", simplifiedChinese: "鲍鱼", korean: "전복")
        case .squid:
            return LocalizedAllergenNames(japanese: "いか", english: "Squid", traditionalChinese: "魷魚", simplifiedChinese: "鱿鱼", korean: "오징어")
        case .salmonRoe:
            return LocalizedAllergenNames(japanese: "いくら", english: "Salmon roe", traditionalChinese: "鮭魚卵", simplifiedChinese: "鲑鱼卵", korean: "연어알")
        case .orange:
            return LocalizedAllergenNames(japanese: "オレンジ", english: "Orange", traditionalChinese: "柳橙", simplifiedChinese: "橙子", korean: "오렌지")
        case .kiwiFruit:
            return LocalizedAllergenNames(japanese: "キウイフルーツ", english: "Kiwi fruit", traditionalChinese: "奇異果", simplifiedChinese: "猕猴桃", korean: "키위")
        case .beef:
            return LocalizedAllergenNames(japanese: "牛肉", english: "Beef", traditionalChinese: "牛肉", simplifiedChinese: "牛肉", korean: "소고기")
        case .sesame:
            return LocalizedAllergenNames(japanese: "ごま", english: "Sesame", traditionalChinese: "芝麻", simplifiedChinese: "芝麻", korean: "참깨")
        case .salmon:
            return LocalizedAllergenNames(japanese: "さけ", english: "Salmon", traditionalChinese: "鮭魚", simplifiedChinese: "鲑鱼", korean: "연어")
        case .mackerel:
            return LocalizedAllergenNames(japanese: "さば", english: "Mackerel", traditionalChinese: "鯖魚", simplifiedChinese: "鲭鱼", korean: "고등어")
        case .soybean:
            return LocalizedAllergenNames(japanese: "大豆", english: "Soybean", traditionalChinese: "大豆", simplifiedChinese: "大豆", korean: "대두")
        case .chicken:
            return LocalizedAllergenNames(japanese: "鶏肉", english: "Chicken", traditionalChinese: "雞肉", simplifiedChinese: "鸡肉", korean: "닭고기")
        case .banana:
            return LocalizedAllergenNames(japanese: "バナナ", english: "Banana", traditionalChinese: "香蕉", simplifiedChinese: "香蕉", korean: "바나나")
        case .pork:
            return LocalizedAllergenNames(japanese: "豚肉", english: "Pork", traditionalChinese: "豬肉", simplifiedChinese: "猪肉", korean: "돼지고기")
        case .pistachio:
            return LocalizedAllergenNames(japanese: "ピスタチオ", english: "Pistachio", traditionalChinese: "開心果", simplifiedChinese: "开心果", korean: "피스타치오")
        case .macadamiaNut:
            return LocalizedAllergenNames(japanese: "マカダミアナッツ", english: "Macadamia nut", traditionalChinese: "夏威夷豆", simplifiedChinese: "夏威夷果", korean: "마카다미아")
        case .peach:
            return LocalizedAllergenNames(japanese: "もも", english: "Peach", traditionalChinese: "桃子", simplifiedChinese: "桃子", korean: "복숭아")
        case .yam:
            return LocalizedAllergenNames(japanese: "やまいも", english: "Yam", traditionalChinese: "山藥", simplifiedChinese: "山药", korean: "마")
        case .apple:
            return LocalizedAllergenNames(japanese: "りんご", english: "Apple", traditionalChinese: "蘋果", simplifiedChinese: "苹果", korean: "사과")
        case .gelatin:
            return LocalizedAllergenNames(japanese: "ゼラチン", english: "Gelatin", traditionalChinese: "明膠", simplifiedChinese: "明胶", korean: "젤라틴")
        }
    }
}

private struct LocalizedAllergenNames {
    let japanese: String
    let english: String
    let traditionalChinese: String
    let simplifiedChinese: String
    let korean: String
}
