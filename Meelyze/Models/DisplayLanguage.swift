import Foundation

/// MVPが対応する表示言語（メニュー原文の日本語は含まない）。
enum DisplayLanguage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case english
    case traditionalChinese
    case simplifiedChinese
    case korean

    var id: String { rawValue }

    /// 各言語の自称（endonym）による表示名。言語選択画面（S02）で使用する。
    var endonymLabel: String {
        switch self {
        case .english:
            return "English"
        case .traditionalChinese:
            return "繁體中文"
        case .simplifiedChinese:
            return "简体中文"
        case .korean:
            return "한국어"
        }
    }
}
