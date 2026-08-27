import Foundation

/// `VisionOCRService`が返す`RecognizedTextObservation`の検出順序は、reading orderを保証しない。
/// 実測では、画像全体を左右問わず絶対Y座標でおおよそ上から下へ走査した
/// 順序になっており、複数列レイアウトのメニュー（例: 「お食事」列と「一品料理・おつまみ」列）では
/// 左列と右列の項目が1件ずつ交互に混ざって出現する（`fix/FIX-010-ocr-reading-order-for-multi-column-menus.md`
/// で実測・記録）。
///
/// `MenuUnderstandingPrompt`はBounding Box情報を渡さずテキストのみをLLMへ渡すため、この交互混在
/// した順序のままでは「どの価格がどの料理のものか」をLLMが正しく推測できない。本ユーティリティは、
/// Bounding Boxの左端（`minX`）で列をクラスタリングし、列ごとにY降順（画像上で上から下、Visionの
/// 座標系は原点左下のためY大が上）へ並べ替えた上で列を左から右へ連結する、決定論的な並べ替えを行う。
///
/// 一般のドキュメントレイアウト解析アルゴリズムではなく、実測に基づいて調整したヒューリスティックで
/// ある点に注意する。単一列のメニューでは列分割が起きず単純なY降順ソートと等価になる。
enum OCRReadingOrderSorter {
    /// 同一の列とみなす、隣接するBounding Box左端（`minX`、正規化座標）間の許容ギャップ。
    /// デモメニュー画像（2列構成）の実測では、列内の最大ギャップが約0.061、列間のギャップが
    /// 約0.068だったため、その中間の0.06を閾値とする。
    private static let columnGapThreshold: CGFloat = 0.06

    /// `observations`を列単位でクラスタリングし、列ごとにY降順（上→下）へ並べ替えてから列を左から
    /// 右へ連結した配列を返す。同じBounding Box位置（同点）の要素は入力での出現順を保つ（安定ソート）。
    static func sorted(_ observations: [RecognizedTextObservation]) -> [RecognizedTextObservation] {
        guard observations.count > 1 else { return observations }

        let byLeftEdge = stableSorted(observations) { $0.boundingBox.minX < $1.boundingBox.minX }

        var columns: [[RecognizedTextObservation]] = []
        var current: [RecognizedTextObservation] = []
        var previousMinX: CGFloat?
        for observation in byLeftEdge {
            let minX = observation.boundingBox.minX
            if let previousMinX, minX - previousMinX > columnGapThreshold {
                columns.append(current)
                current = []
            }
            current.append(observation)
            previousMinX = minX
        }
        if !current.isEmpty {
            columns.append(current)
        }

        return columns.flatMap { column in
            stableSorted(column) { $0.boundingBox.midY > $1.boundingBox.midY }
        }
    }

    /// `Array.sorted(by:)`は安定性を仕様上保証しないため、元のindexを二次キーにして安定ソートにする。
    private static func stableSorted(
        _ elements: [RecognizedTextObservation],
        by areInIncreasingOrder: (RecognizedTextObservation, RecognizedTextObservation) -> Bool
    ) -> [RecognizedTextObservation] {
        elements.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
