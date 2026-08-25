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

    @Test func normalizeFoldsFullWidthLatinAndCaseWithoutResolvingToDatabaseIDs() {
        let normalizer = MenuNameNormalizer()

        let evidence = normalizer.normalize("ＰＯＲＫ")

        #expect(evidence.normalizedText == "pork")
        #expect(!evidence.normalizedText.contains("_"))
        #expect(evidence.changes.contains(.widthAndCaseFolded))
    }
}
