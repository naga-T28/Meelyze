import Testing
@testable import Meelyze

/// `RiskLLMSignalExtractor`が、`ParsedMenuItem`のLLM由来テキストから選択済み`RiskTarget`の
/// Positiveシグナルのみを、安全に（誤検知を避けつつ）抽出できることを確認するテスト。
struct RiskLLMSignalExtractorTests {
    private let extractor = RiskLLMSignalExtractor()

    @Test func extractSignalsFindsMatchInExplicitIngredients() {
        let item = makeItem(explicitIngredients: ["卵"])

        let signals = extractor.extractSignals(from: item, sourceEvidence: [], targets: [.allergen(.egg)])

        #expect(signals.count == 1)
        #expect(signals.first?.target == .allergen(.egg))
        #expect(signals.first?.polarity == .positive)
        #expect(signals.first?.sourceText == "卵")
    }

    @Test func extractSignalsFindsMatchInPreparationMethods() {
        let item = makeItem(preparationMethods: ["卵とじ"])

        let signals = extractor.extractSignals(from: item, sourceEvidence: [], targets: [.allergen(.egg)])

        #expect(signals.count == 1)
        #expect(signals.first?.sourceText == "卵とじ")
    }

    @Test func extractSignalsFindsMatchInModifiers() {
        let item = makeItem(modifiers: ["卵増し"])

        let signals = extractor.extractSignals(from: item, sourceEvidence: [], targets: [.allergen(.egg)])

        #expect(signals.count == 1)
        #expect(signals.first?.sourceText == "卵増し")
    }

    @Test func extractSignalsMatchesBothPeanutKeywordVariants() {
        let usingKanji = makeItem(explicitIngredients: ["落花生油"])
        let usingKatakana = makeItem(explicitIngredients: ["ピーナッツバター"])

        #expect(extractor.extractSignals(from: usingKanji, sourceEvidence: [], targets: [.allergen(.peanut)]).count == 1)
        #expect(extractor.extractSignals(from: usingKatakana, sourceEvidence: [], targets: [.allergen(.peanut)]).count == 1)
    }

    @Test func extractSignalsMatchesAcrossHiraganaKatakanaFormDifferences() {
        // targetの表示名はひらがな「えび」だが、実際のOCRメニューはカタカナ表記になりやすい。
        let item = makeItem(explicitIngredients: ["エビ天ぷら"])

        let signals = extractor.extractSignals(from: item, sourceEvidence: [], targets: [.allergen(.shrimp)])

        #expect(signals.count == 1)
    }

    @Test func extractSignalsIgnoresBaseDishCandidates() {
        // 「沖縄そば」は小麦麺ベース（そば粉不使用）だが、料理名自体に対象語「そば」を含む。
        // baseDishCandidatesは対象外のため、料理名だけではシグナルを生成しない。
        let item = makeItem(baseDishCandidates: ["沖縄そば"])

        let signals = extractor.extractSignals(from: item, sourceEvidence: [], targets: [.allergen(.buckwheat)])

        #expect(signals.isEmpty)
    }

    @Test func extractSignalsReturnsEmptyWhenNoTextMatchesAnyTarget() {
        let item = makeItem(explicitIngredients: ["キャベツ"], preparationMethods: ["塩茹で"], modifiers: ["大盛り"])

        let signals = extractor.extractSignals(from: item, sourceEvidence: [], targets: [.allergen(.egg), .allergen(.pork)])

        #expect(signals.isEmpty)
    }

    @Test func extractSignalsNeverGeneratesNegativePolarity() {
        let items = [
            makeItem(explicitIngredients: ["卵", "豚肉", "落花生"]),
            makeItem(preparationMethods: ["卵とじ", "揚げ物"]),
            makeItem(modifiers: ["エビ抜き", "大盛り"]),
            makeItem(baseDishCandidates: ["沖縄そば"], explicitIngredients: ["そば粉"]),
        ]
        let targets: [RiskTarget] = [.allergen(.egg), .allergen(.pork), .allergen(.peanut), .allergen(.shrimp), .allergen(.buckwheat)]

        for item in items {
            let signals = extractor.extractSignals(from: item, sourceEvidence: [], targets: targets)
            #expect(!signals.contains { $0.polarity == .negative })
        }
    }

    // MARK: - Fixtures

    private func makeItem(
        baseDishCandidates: [String] = [],
        explicitIngredients: [String] = [],
        preparationMethods: [String] = [],
        modifiers: [String] = []
    ) -> ParsedMenuItem {
        ParsedMenuItem(
            reference: MenuUnderstandingItemReference(
                ordinal: 0,
                sourceReferences: [MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "text")],
                separator: "\n"
            ),
            baseDishCandidates: baseDishCandidates,
            explicitIngredients: explicitIngredients,
            preparationMethods: preparationMethods,
            modifiers: modifiers,
            unknownTerms: []
        )
    }
}
