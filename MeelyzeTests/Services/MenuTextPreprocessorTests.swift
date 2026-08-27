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

    @Test func preprocessRemovesLeadingAndTrailingDecorativeStars() {
        let preprocessor = MenuTextPreprocessor()
        let segment = MenuUnderstandingSourceSegment(
            id: MenuUnderstandingSourceID("s1"),
            rawText: "★本日のおすすめ☆",
            confidence: 0.9,
            boundingBox: .zero
        )

        let result = preprocessor.preprocess([segment])

        #expect(result.segments[0].analysisText == "本日のおすすめ")
        #expect(result.evidence[0].changes.contains(.noiseSymbolRemoved))
    }

    @Test func preprocessKeepsStarsThatAreMeaningfulInsideTheDishName() {
        let preprocessor = MenuTextPreprocessor()
        let segment = MenuUnderstandingSourceSegment(
            id: MenuUnderstandingSourceID("s1"),
            rawText: "牛肉★炙り",
            confidence: 0.9,
            boundingBox: .zero
        )

        let result = preprocessor.preprocess([segment])

        #expect(result.segments[0].analysisText == nil)
        #expect(result.evidence[0].changes.isEmpty)
    }

    @Test func preprocessRemovesRepresentativePriceFormatsIncludingUppercaseYen() {
        let preprocessor = MenuTextPreprocessor()
        // 代表的な価格表現のテスト表。対応外通貨は別テストで非対応を明示する。
        let supportedPrices: [(rawText: String, expectedAnalysisText: String)] = [
            ("ラフテー ¥980", "ラフテー"),
            ("ラフテー ￥980", "ラフテー"),
            ("ラフテー 980円", "ラフテー"),
            ("ラフテー 1,280円", "ラフテー"),
            ("ラフテー 980yen", "ラフテー"),
            ("ラフテー 980YEN", "ラフテー")
        ]

        for testCase in supportedPrices {
            let segment = MenuUnderstandingSourceSegment(
                id: MenuUnderstandingSourceID("s1"),
                rawText: testCase.rawText,
                confidence: 0.9,
                boundingBox: .zero
            )

            let result = preprocessor.preprocess([segment])

            #expect(result.segments[0].analysisText == testCase.expectedAnalysisText, "\(testCase.rawText)")
            #expect(result.evidence[0].changes.contains(.priceRemoved), "\(testCase.rawText)")
        }
    }

    @Test func preprocessDoesNotTreatUnsupportedCurrenciesAsRemoved() {
        let preprocessor = MenuTextPreprocessor()
        // $やUSD等の対応外通貨表記を、暗黙に「対応済み」として扱わないことを明示する回帰テスト。
        let unsupportedPrices = ["ラフテー $9.80", "ラフテー 9.80USD"]

        for rawText in unsupportedPrices {
            let segment = MenuUnderstandingSourceSegment(
                id: MenuUnderstandingSourceID("s1"),
                rawText: rawText,
                confidence: 0.9,
                boundingBox: .zero
            )

            let result = preprocessor.preprocess([segment])

            #expect(!result.evidence[0].changes.contains(.priceRemoved), "\(rawText)")
            #expect(result.segments[0].analysisText == nil, "\(rawText)")
        }
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

    // MARK: - hasNoAnalyzableContent (FIX-013)

    @Test func hasNoAnalyzableContentIsTrueForPriceOnlyText() {
        let preprocessor = MenuTextPreprocessor()

        #expect(preprocessor.hasNoAnalyzableContent("500円"))
        #expect(preprocessor.hasNoAnalyzableContent("¥1,280"))
        #expect(preprocessor.hasNoAnalyzableContent("  980円  "))
    }

    @Test func hasNoAnalyzableContentIsTrueForMenuNumberOrNoiseSymbolOnlyText() {
        let preprocessor = MenuTextPreprocessor()

        #expect(preprocessor.hasNoAnalyzableContent("No.12"))
        #expect(preprocessor.hasNoAnalyzableContent("★☆"))
    }

    @Test func hasNoAnalyzableContentIsFalseWhenDishNameRemains() {
        let preprocessor = MenuTextPreprocessor()

        #expect(!preprocessor.hasNoAnalyzableContent("ラフテー 980円"))
        #expect(!preprocessor.hasNoAnalyzableContent("沖縄そば"))
        #expect(!preprocessor.hasNoAnalyzableContent("★本日のおすすめ☆"))
    }
}
