import Testing
import Foundation
import CoreGraphics
@testable import Meelyze

struct BoundingBoxConverterTests {
    private let converter = BoundingBoxConverter()
    private let epsilon: CGFloat = 0.001

    @Test func fullImageBoxMapsToFullContainerWhenAspectRatiosMatch() {
        let result = converter.convert(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: CGSize(width: 1000, height: 1000),
            containerSize: CGSize(width: 500, height: 500)
        )

        #expect(approximatelyEqual(result, CGRect(x: 0, y: 0, width: 500, height: 500), epsilon: epsilon))
    }

    @Test func visionBottomLeftOriginIsFlippedToTopLeftOrigin() {
        // 正方形・スケール1:1（レターボックスなし）。Vision座標でy=0.7〜0.8（画像上部寄り）にある
        // Boxは、上下反転後は画像上端に近い位置（top-down y=0.2〜0.3）へ変換されるはず。
        let result = converter.convert(
            CGRect(x: 0.2, y: 0.7, width: 0.1, height: 0.1),
            imageSize: CGSize(width: 1000, height: 1000),
            containerSize: CGSize(width: 1000, height: 1000)
        )

        #expect(approximatelyEqual(result, CGRect(x: 200, y: 200, width: 100, height: 100), epsilon: epsilon))
    }

    @Test func landscapeImageInSquareContainerLettersboxesTopAndBottom() {
        // 画像2:1（横長）をコンテナ1:1へaspectFit → 幅基準でfitし、上下にレターボックスが生じる。
        let imageSize = CGSize(width: 2000, height: 1000)
        let containerSize = CGSize(width: 1000, height: 1000)

        let fullImage = converter.convert(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: imageSize,
            containerSize: containerSize
        )

        #expect(approximatelyEqual(fullImage, CGRect(x: 0, y: 250, width: 1000, height: 500), epsilon: epsilon))
    }

    @Test func portraitImageInSquareContainerLettersboxesLeftAndRight() {
        // 画像1:2（縦長）をコンテナ1:1へaspectFit → 高さ基準でfitし、左右にレターボックスが生じる。
        let imageSize = CGSize(width: 1000, height: 2000)
        let containerSize = CGSize(width: 1000, height: 1000)

        let fullImage = converter.convert(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: imageSize,
            containerSize: containerSize
        )

        #expect(approximatelyEqual(fullImage, CGRect(x: 250, y: 0, width: 500, height: 1000), epsilon: epsilon))
    }

    @Test func boxWithinLetterboxedImageAccountsForOffset() {
        // 上下レターボックスがある状態で、画像の左上隅（Vision: x=0, y=0.9, width=0.1, height=0.1）の
        // Boxが、レターボックス分のoffsetYを加味した位置へ変換されることを確認する。
        let imageSize = CGSize(width: 2000, height: 1000)
        let containerSize = CGSize(width: 1000, height: 1000)

        let result = converter.convert(
            CGRect(x: 0, y: 0.9, width: 0.1, height: 0.1),
            imageSize: imageSize,
            containerSize: containerSize
        )

        // displayedImage = (0, 250, 1000, 500). topLeftOriginNormalized.y = 1 - 0.9 - 0.1 = 0.0
        #expect(approximatelyEqual(result, CGRect(x: 0, y: 250, width: 100, height: 50), epsilon: epsilon))
    }

    @Test func zeroSizedImageReturnsZeroRectInsteadOfCrashingOrProducingNaN() {
        let result = converter.convert(
            CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1),
            imageSize: .zero,
            containerSize: CGSize(width: 500, height: 500)
        )

        #expect(result == .zero)
    }

    @Test func zeroSizedContainerReturnsZeroRect() {
        let result = converter.convert(
            CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1),
            imageSize: CGSize(width: 500, height: 500),
            containerSize: .zero
        )

        #expect(result == .zero)
    }

    @Test func convertUnionReturnsNilForEmptyInput() {
        let result = converter.convertUnion(
            [],
            imageSize: CGSize(width: 1000, height: 1000),
            containerSize: CGSize(width: 500, height: 500)
        )

        #expect(result == nil)
    }

    @Test func convertUnionCoversAllProvidedBoxes() {
        // 同一料理が2つのOCR領域（左側・右側）にまたがるケース。Union後の矩形は両方を内包する。
        let imageSize = CGSize(width: 1000, height: 1000)
        let containerSize = CGSize(width: 1000, height: 1000)

        let result = converter.convertUnion(
            [
                CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1),
                CGRect(x: 0.5, y: 0.8, width: 0.2, height: 0.1)
            ],
            imageSize: imageSize,
            containerSize: containerSize
        )

        guard let result else {
            Issue.record("Expected non-nil union result")
            return
        }
        // 左Box → (100, 100, 200, 100)。右Box → (500, 100, 200, 100)。Unionは(100,100)〜(700,200)。
        #expect(approximatelyEqual(result, CGRect(x: 100, y: 100, width: 600, height: 100), epsilon: epsilon))
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, epsilon: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) < epsilon
            && abs(lhs.minY - rhs.minY) < epsilon
            && abs(lhs.width - rhs.width) < epsilon
            && abs(lhs.height - rhs.height) < epsilon
    }
}
