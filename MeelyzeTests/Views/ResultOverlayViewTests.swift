import Testing
import CoreGraphics
@testable import Meelyze

/// `OverlayTagFontMetrics`（FIX-014、FIX-015で`.scaleEffect`からフォントサイズ計算方式へ変更）が、
/// メニュー写真内の実際の文字サイズに応じたフォントサイズを正しく計算することを検証する。
/// `ResultOverlayView`自体のレイアウト・アクセシビリティ結線は他の多くのViewと同じくPreview・
/// 実機/Simulator確認・UI Testで検証する（`RiskResultCardViewTests`と同じ既存方針）。
struct ResultOverlayViewTests {
    @Test func fontSizeIsBaselineAtReferenceLineHeight() {
        let fontSize = OverlayTagFontMetrics.fontSize(forLineHeights: [OverlayTagFontMetrics.referenceLineHeight])
        #expect(fontSize == OverlayTagFontMetrics.baselineFontSize)
    }

    @Test func fontSizeShrinksProportionallyForSmallDenseMenuText() {
        // 基準値の75%の高さ → 75%のフォントサイズ（下限10ptより上に収まる範囲で比例縮小を検証する。
        // 基準値の半分（7.5pt相当）は下限10ptを下回りクランプされてしまうため、
        // クランプ自体は`fontSizeClampsToMinimumForExtremelyTinyText`で別途検証する）。
        let fontSize = OverlayTagFontMetrics.fontSize(forLineHeights: [OverlayTagFontMetrics.referenceLineHeight * 0.75])
        #expect(approximatelyEqual(fontSize, OverlayTagFontMetrics.baselineFontSize * 0.75))
    }

    @Test func fontSizeGrowsProportionallyForLargeMenuText() {
        let fontSize = OverlayTagFontMetrics.fontSize(forLineHeights: [OverlayTagFontMetrics.referenceLineHeight * 1.2])
        #expect(approximatelyEqual(fontSize, OverlayTagFontMetrics.baselineFontSize * 1.2))
    }

    @Test func fontSizeClampsToMinimumForExtremelyTinyText() {
        let fontSize = OverlayTagFontMetrics.fontSize(forLineHeights: [1])
        #expect(fontSize == OverlayTagFontMetrics.minimumFontSize)
    }

    @Test func fontSizeClampsToMaximumForExtremelyLargeText() {
        let fontSize = OverlayTagFontMetrics.fontSize(forLineHeights: [500])
        #expect(fontSize == OverlayTagFontMetrics.maximumFontSize)
    }

    @Test func fontSizeUsesTallestLineNotUnionHeightForMultiLineItems() {
        // 2行にまたがる項目でも、UNION矩形の合計高さではなく個々の行の最大値を代表値として使う
        // （合計を使うと行数に比例して過大評価し、複数行の料理名だけタグが不自然に肥大化するため）。
        let fontSize = OverlayTagFontMetrics.fontSize(forLineHeights: [
            OverlayTagFontMetrics.referenceLineHeight, OverlayTagFontMetrics.referenceLineHeight
        ])
        #expect(fontSize == OverlayTagFontMetrics.baselineFontSize)
    }

    @Test func fontSizeDefaultsToBaselineForEmptyOrInvalidInput() {
        #expect(OverlayTagFontMetrics.fontSize(forLineHeights: []) == OverlayTagFontMetrics.baselineFontSize)
        #expect(OverlayTagFontMetrics.fontSize(forLineHeights: [0]) == OverlayTagFontMetrics.baselineFontSize)
        #expect(OverlayTagFontMetrics.fontSize(forLineHeights: [-5]) == OverlayTagFontMetrics.baselineFontSize)
    }

    /// 浮動小数点の乗算・除算経由の比較のための許容誤差付き比較（`BoundingBoxConverterTests`と同じ方針）。
    private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat, epsilon: CGFloat = 0.001) -> Bool {
        abs(lhs - rhs) < epsilon
    }
}
