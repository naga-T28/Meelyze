import Foundation

/// OCR原文（日本語）の料理名を、利用者の表示言語へ翻訳するService。表示専用であり、翻訳結果を
/// 判定ロジック・Evidenceへ一切混入させない（`docs/requirements.md` FR-4.4, AC-3.3の原則を
/// dish name表示にも適用する）。
///
/// 翻訳データ未準備・翻訳失敗・Framework利用不可時は`nil`を返す。呼び出し側（S08/S09）は`nil`の場合
/// 日本語原文のみを表示し、画面をブロックしない。
@MainActor
protocol DishNameTranslationService {
    func translate(_ japaneseText: String, to language: DisplayLanguage) async -> String?
}
