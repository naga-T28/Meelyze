import Foundation
import CoreGraphics

/// OCR（Apple Vision）が返す正規化Bounding Box（原点左下、`[0,1]`範囲）を、SwiftUI上で画像を
/// `.aspectFit`（`scaledToFit()`相当）表示した際の実際の表示矩形（原点左上、コンテナ座標系）へ
/// 変換する。
///
/// Visionの正規化座標系は画像のピクセルサイズに依存しないため、SwiftUI側で画像を任意のコンテナへ
/// `.aspectFit`表示する際に生じるレターボックス（余白）を考慮しないと、Bounding Boxの表示位置が
/// 実際の料理名の位置とずれる（`docs/requirements.md` NFR-4.6, AC-1.1）。
struct BoundingBoxConverter {
    /// Visionの正規化Bounding Box（原点左下、`[0,1]`範囲）を1件、`imageSize`の画像を`containerSize`へ
    /// `.aspectFit`表示した場合のコンテナ座標系（原点左上）の矩形へ変換する。
    ///
    /// `imageSize`・`containerSize`のいずれかの辺が0以下の場合は`.zero`を返す（レイアウト確定前の
    /// 呼び出し等、無効な入力でクラッシュ・NaNを生じさせないため）。
    func convert(_ normalizedVisionRect: CGRect, imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard
            imageSize.width > 0, imageSize.height > 0,
            containerSize.width > 0, containerSize.height > 0
        else {
            return .zero
        }

        // Vision（原点左下・y上向き）→ 正規化された原点左上・y下向きへ変換する。
        let topLeftOriginNormalized = CGRect(
            x: normalizedVisionRect.minX,
            y: 1 - normalizedVisionRect.minY - normalizedVisionRect.height,
            width: normalizedVisionRect.width,
            height: normalizedVisionRect.height
        )

        let displayedImage = Self.aspectFitFrame(imageSize: imageSize, containerSize: containerSize)

        return CGRect(
            x: displayedImage.minX + topLeftOriginNormalized.minX * displayedImage.width,
            y: displayedImage.minY + topLeftOriginNormalized.minY * displayedImage.height,
            width: topLeftOriginNormalized.width * displayedImage.width,
            height: topLeftOriginNormalized.height * displayedImage.height
        )
    }

    /// 複数のVision正規化Bounding Box（同一料理が複数のOCR領域にまたがる場合）を、それらすべてを
    /// 内包する1つのコンテナ座標系の矩形へ変換する。`normalizedVisionRects`が空の場合は`nil`を返す。
    func convertUnion(_ normalizedVisionRects: [CGRect], imageSize: CGSize, containerSize: CGSize) -> CGRect? {
        guard !normalizedVisionRects.isEmpty else { return nil }
        return normalizedVisionRects
            .map { convert($0, imageSize: imageSize, containerSize: containerSize) }
            .reduce(nil as CGRect?) { union, rect in union?.union(rect) ?? rect }
    }

    /// `imageSize`の画像を`containerSize`のコンテナへ`.aspectFit`（アスペクト比を維持したまま最大表示）
    /// した場合に、画像が実際に占めるコンテナ座標系の矩形（レターボックスを含む余白を除いた領域）。
    private static func aspectFitFrame(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        let displayedSize: CGSize
        if imageAspect > containerAspect {
            // 画像の方が横長 → 幅を基準にfitし、上下にレターボックスが生じる。
            let width = containerSize.width
            displayedSize = CGSize(width: width, height: width / imageAspect)
        } else {
            // 画像の方が縦長（または同一比率） → 高さを基準にfitし、左右にレターボックスが生じる。
            let height = containerSize.height
            displayedSize = CGSize(width: height * imageAspect, height: height)
        }

        let offsetX = (containerSize.width - displayedSize.width) / 2
        let offsetY = (containerSize.height - displayedSize.height) / 2
        return CGRect(origin: CGPoint(x: offsetX, y: offsetY), size: displayedSize)
    }
}
