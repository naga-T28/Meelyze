import Testing
import Foundation
@testable import Meelyze

struct MenuTextPreprocessorTests {
    @Test func preprocessRemovesPricesIntoAnalysisTextWithoutChangingRawTextOrGeometry() {
        let preprocessor = MenuTextPreprocessor()
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let segment = MenuUnderstandingSourceSegment(
            id: MenuUnderstandingSourceID("s1"),
            rawText: "ラフテー 980円",
            confidence: 0.77,
            boundingBox: box
        )

        let result = preprocessor.preprocess([segment])

        #expect(result.segments[0].rawText == "ラフテー 980円")
        #expect(result.segments[0].analysisText == "ラフテー")
        #expect(result.segments[0].boundingBox == box)
        #expect(result.segments[0].confidence == 0.77)
        #expect(result.evidence[0].sourceID == MenuUnderstandingSourceID("s1"))
        #expect(result.evidence[0].rawText == "ラフテー 980円")
        #expect(result.evidence[0].analysisText == "ラフテー")
        #expect(result.evidence[0].changes == [.priceRemoved, .whitespaceNormalized])
    }

    @Test func preprocessRemovesFourDigitYenPricesMenuNumbersAndNoiseSymbols() {
        let preprocessor = MenuTextPreprocessor()
        let segment = MenuUnderstandingSourceSegment(
            id: MenuUnderstandingSourceID("s1"),
            rawText: "No.12 ＊ ラフテー ￥1280",
            confidence: 0.88,
            boundingBox: .zero
        )

        let result = preprocessor.preprocess([segment])

        #expect(result.segments[0].rawText == "No.12 ＊ ラフテー ￥1280")
        #expect(result.segments[0].analysisText == "ラフテー")
        #expect(result.evidence[0].changes.contains(.priceRemoved))
        #expect(result.evidence[0].changes.contains(.menuNumberRemoved))
        #expect(result.evidence[0].changes.contains(.noiseSymbolRemoved))
    }

    @Test func preprocessLeavesAnalysisTextNilWhenNoChangeIsNeeded() {
        let preprocessor = MenuTextPreprocessor()
        let segment = MenuUnderstandingSourceSegment(
            id: MenuUnderstandingSourceID("s1"),
            rawText: "沖縄そば",
            confidence: 0.9,
            boundingBox: .zero
        )

        let result = preprocessor.preprocess([segment])

        #expect(result.segments[0].analysisText == nil)
        #expect(result.evidence[0].analysisText == nil)
        #expect(result.evidence[0].changes.isEmpty)
    }

    @Test func preprocessDoesNotRemoveBareMenuNumbersThatAreNotPrices() {
        let preprocessor = MenuTextPreprocessor()
        let segment = MenuUnderstandingSourceSegment(
            id: MenuUnderstandingSourceID("s1"),
            rawText: "前菜3種盛り",
            confidence: 0.9,
            boundingBox: .zero
        )

        let result = preprocessor.preprocess([segment])

        #expect(result.segments[0].analysisText == nil)
        #expect(result.evidence[0].rawText == "前菜3種盛り")
    }
}
