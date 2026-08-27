import Foundation

/// OCRが検出したテキスト領域（`OCRResult`）を、Menu Understandingへの入力（`MenuUnderstandingRequest`）へ
/// 変換する。
///
/// 変換時に発行した`MenuUnderstandingSourceID`と元の`RecognizedTextObservation`（rawText・confidence・
/// Bounding Box）の対応関係を`Output.sourceMap`として保持し、パイプライン後段（Issue #19の
/// `MenuAnalysisService`）が最終結果からBounding Boxを復元できるようにする（FR-1.7）。
struct MenuUnderstandingRequestBuilder {
    /// `build(from:)`の結果。`request`と、`request`内の各`MenuUnderstandingSourceID`から元の
    /// `RecognizedTextObservation`を引ける`sourceMap`を同時に返す。
    struct Output: Equatable, Sendable {
        let request: MenuUnderstandingRequest
        let sourceMap: [MenuUnderstandingSourceID: RecognizedTextObservation]
    }

    init() {}

    /// `OCRResult.observations`から`MenuUnderstandingRequest`を構築する。
    ///
    /// - `MenuUnderstandingSourceID`は配列インデックスに基づいて採番する。`VisionOCRService`はreading
    ///   orderを保証せず同一テキストが複数箇所に出現しうるため、内容ハッシュではなくインデックスを使う
    ///   ことで、同一入力内での衝突を避ける（`MenuUnderstandingRequest`のIDはrequestが有効な間だけ
    ///   一意であればよく、実行間の安定性は不要）。
    /// - 前後の空白のみで構成される（意味のある文字を含まない）observationは、Menu Understandingの
    ///   解析対象になり得ないため`segments`・`sourceMap`の両方から除外する。
    /// - `ocrResult.isEmpty`（または全observationが空白のみ）の場合は`segments`が空の`request`を返す。
    ///   これを「解析不能」として扱うかどうかの判断は、呼び出し側（`MenuAnalysisService`、TASK-038）の
    ///   責務とする。
    func build(from ocrResult: OCRResult) -> Output {
        var segments: [MenuUnderstandingSourceSegment] = []
        var sourceMap: [MenuUnderstandingSourceID: RecognizedTextObservation] = [:]

        for (index, observation) in ocrResult.observations.enumerated() {
            guard !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let id = MenuUnderstandingSourceID("ocr-source-\(index)")
            sourceMap[id] = observation
            segments.append(
                MenuUnderstandingSourceSegment(
                    id: id,
                    rawText: observation.text,
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox
                )
            )
        }

        return Output(request: MenuUnderstandingRequest(segments: segments), sourceMap: sourceMap)
    }
}
