import Foundation

/// 1回の撮影・OCR実行結果全体を表す。`observations`は認識文字列とBounding Boxの対応関係を1件ずつ
/// 維持したまま保持する。
///
/// `observations`が空の場合は、Visionが文字を1件も抽出できなかったこと（`docs/ui-design.md`のE01）を
/// 表す。1件以上保持していれば、含まれる要素が低Confidenceであっても全体失敗として扱わない。この
/// 「0件か1件以上か」の判定は呼び出し側（`ScanViewModel`等）の責務であり、本モデルは対応関係を保った
/// 配列を保持するのみに留める。OCR処理そのものを完了できない場合（不正な画像データ等）は本モデルでは
/// 表現せず、`OCRService`が`OCRError`をthrowすることで区別する。
struct OCRResult: Equatable, Sendable {
    let observations: [RecognizedTextObservation]

    init(observations: [RecognizedTextObservation]) {
        self.observations = observations
    }

    /// Visionが文字を1件も抽出できなかったことを表す。
    var isEmpty: Bool { observations.isEmpty }
}
