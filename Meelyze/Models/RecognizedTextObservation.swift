import Foundation

/// OCRが検出した1件のテキスト領域を表す。認識文字列・Confidence・Bounding Boxを1件ずつ対応付けて
/// 保持する（Visionの`VNRecognizedText.confidence` `VNRectangleObservation.boundingBox`相当）。
struct RecognizedTextObservation: Equatable, Sendable {
    /// 認識された文字列（上位候補）。
    let text: String

    /// 認識の信頼度（0.0〜1.0）。
    let confidence: Float

    /// 画像上の正規化座標（原点は左下、幅・高さは画像サイズに対する比率）。
    let boundingBox: CGRect
}
