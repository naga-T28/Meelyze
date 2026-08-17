import Foundation

/// S02 表示言語選択画面（`LanguageSelectionView`）の選択状態を保持する。
///
/// MVP対象4言語（英語・繁体字中国語・簡体字中国語・韓国語）から1つを選ぶ必須項目として扱い、
/// 未選択の間はPrimary CTAを無効化する。
@Observable
final class LanguageSelectionViewModel {
    private(set) var selectedLanguage: DisplayLanguage?

    let availableLanguages: [DisplayLanguage] = DisplayLanguage.allCases

    /// 未選択の間はPrimary CTAを無効化するための判定。
    var canProceed: Bool { selectedLanguage != nil }

    func select(_ language: DisplayLanguage) {
        selectedLanguage = language
    }

    func isSelected(_ language: DisplayLanguage) -> Bool {
        selectedLanguage == language
    }
}
