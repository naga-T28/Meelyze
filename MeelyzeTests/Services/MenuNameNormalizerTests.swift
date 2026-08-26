import Testing
@testable import Meelyze

struct MenuNameNormalizerTests {
    @Test func normalizeTrimsAndRemovesSeparatorsForAliasLookup() {
        let normalizer = MenuNameNormalizer()

        let evidence = normalizer.normalize(" ゴーヤー・チャンプルー ")

        #expect(evidence.originalText == " ゴーヤー・チャンプルー ")
        #expect(evidence.normalizedText == "ゴーヤーチャンプルー")
        #expect(evidence.changes.contains(.trimmed))
        #expect(evidence.changes.contains(.separatorsRemoved))
    }

    @Test func normalizeConvertsHiraganaToKatakana() {
        let normalizer = MenuNameNormalizer()

        let evidence = normalizer.normalize("らふてー")

        #expect(evidence.normalizedText == "ラフテー")
        #expect(evidence.changes.contains(.hiraganaConvertedToKatakana))
    }

    @Test func normalizeCorrectsRepresentativeOCRLongSoundConfusion() {
        let normalizer = MenuNameNormalizer()

        let evidence = normalizer.normalize("ラフテ一")

        #expect(evidence.normalizedText == "ラフテー")
        #expect(evidence.changes.contains(.ocrLongSoundNormalized))
    }

    @Test func normalizeDoesNotOverCorrectLegitimateKanjiOne() {
        let normalizer = MenuNameNormalizer()
        // 助数詞・「第◯」・単独の数詞・複合語中の「一」はいずれも辞書に存在しないため、
        // 長音記号「ー」へ誤変換されてはならない。「メニュー一」は、廃止した位置推測ヒューリスティックが
        // 「メニューー」へ誤変換していた実バグの回帰アンカー。
        let cases: [(input: String, expectedNormalizedText: String)] = [
            ("ビール一杯", "ビール一杯"),
            ("第一だし", "第一ダシ"),
            ("一つ", "一ツ"),
            ("一品料理", "一品料理"),
            ("メニュー一", "メニュー一"),
        ]

        for testCase in cases {
            let evidence = normalizer.normalize(testCase.input)
            #expect(evidence.normalizedText == testCase.expectedNormalizedText, "\(testCase.input)")
            #expect(!evidence.changes.contains(.ocrLongSoundNormalized), "\(testCase.input)")
        }
    }

    @Test func normalizeFoldsFullWidthLatinAndCaseWithoutResolvingToDatabaseIDs() {
        let normalizer = MenuNameNormalizer()

        let evidence = normalizer.normalize("ＰＯＲＫ")

        #expect(evidence.normalizedText == "pork")
        #expect(!evidence.normalizedText.contains("_"))
        #expect(evidence.changes.contains(.widthAndCaseFolded))
    }
}
