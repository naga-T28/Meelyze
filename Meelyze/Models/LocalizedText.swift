import Foundation

/// MVP対象4言語（英語・繁体字中国語・簡体字中国語・韓国語）分のUI文言をまとめて保持する値。
///
/// 表示言語選択（S02）より前の画面（S01/S02）は選択言語が未確定のため英語で固定表示し、
/// S02以降の画面はこの型を使って選択済み`DisplayLanguage`に応じた文言を表示する。
struct LocalizedText {
    let english: String
    let traditionalChinese: String
    let simplifiedChinese: String
    let korean: String

    func value(for language: DisplayLanguage) -> String {
        switch language {
        case .english:
            return english
        case .traditionalChinese:
            return traditionalChinese
        case .simplifiedChinese:
            return simplifiedChinese
        case .korean:
            return korean
        }
    }
}
