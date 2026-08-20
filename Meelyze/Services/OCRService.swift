import Foundation

/// 画像データから文字列を認識するProtocol。ViewModelはこのProtocol経由でのみOCRにアクセスし、
/// Visionを直接importしない（`docs/technology-selection.md`§4〜5）。認識言語ヒントを日本語（`ja-JP`）
/// 優先に固定した実装であることを前提とする（FR-1.2、TASK-021の`VisionOCRService`が満たす）。
protocol OCRService: Sendable {
    /// 画像データから文字列を認識し、`OCRResult`として返す。
    ///
    /// Visionが1件以上のテキスト領域を検出できた場合は、Confidenceの高低に関わらずすべて
    /// `OCRResult.observations`へ含める（低Confidenceの部分認識を全体失敗にしない、
    /// `docs/ui-design.md`のE01定義）。1件も検出できなかった場合は空の`observations`を持つ
    /// `OCRResult`を返す。画像データ自体を解釈できない、またはOCR処理そのものを完了できない場合は
    /// `OCRError`をthrowする。「0件抽出」と「OCR処理失敗」は、それぞれ空の`OCRResult`とthrowという
    /// 別の表現で区別する。
    func recognizeText(in imageData: Data) async throws -> OCRResult
}

/// OCR処理そのものを完了できなかった場合のエラー。「1件も抽出できなかった」（`OCRResult.isEmpty`）とは
/// 区別する。
enum OCRError: Error, Equatable, Sendable {
    /// 画像データを解釈できなかった場合（破損データ、非対応フォーマット等）。
    case invalidImageData
    /// Vision要求の実行自体が失敗した場合。
    case recognitionRequestFailed
}
