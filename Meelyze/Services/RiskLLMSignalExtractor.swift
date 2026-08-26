import Foundation

/// `ParsedMenuItem`のLLM由来テキスト（明示食材・調理法・修飾表現）から、選択済み`RiskTarget`の
/// Positiveシグナルを抽出する。DBの照合を経ていないテキストレベルの部分一致に基づく補助的な検出であり、
/// Positiveのみを生成する（安全根拠として使わないという設計原則上、Negativeはこの型からは一切生成しない）。
///
/// `baseDishCandidates`（料理名候補）は対象に含めない。DB未解決の料理名候補は既存の`RiskFact`
/// （`.unresolved`）経路が独立してすべての選択済みtargetをundeterminedへ倒すため、LLM signalを
/// 追加する安全上の価値が薄い一方、DB解決済みの料理名に対象語が偶然含まれる誤検知
/// （例: 「そば」アレルギーで小麦麺ベースの「沖縄そば」を誤検知する）の方が大きいため。
struct RiskLLMSignalExtractor {
    init() {}

    /// 1項目分の候補テキストと選択済みtargetから、該当するPositiveシグナルを返す。
    func extractSignals(
        from item: ParsedMenuItem,
        sourceEvidence: [MenuTextPreprocessingEvidence],
        targets: [RiskTarget]
    ) -> [RiskLLMSignal] {
        let normalizer = MenuNameNormalizer()
        let searchableTexts = (item.explicitIngredients + item.preparationMethods + item.modifiers)
            .map { (raw: $0, normalized: normalizer.normalize($0).normalizedText) }
        guard !searchableTexts.isEmpty else { return [] }

        return targets.compactMap { target in
            // ひらがな/カタカナの表記差（例: 対象名「えび」とOCR原文「エビ」）を吸収するため、
            // キーワード側も同じNormalizerへ通してから比較する。
            let keywords = target.japaneseMatchKeywords.map { normalizer.normalize($0).normalizedText }
            guard let matched = searchableTexts.first(where: { pair in keywords.contains { pair.normalized.contains($0) } }) else {
                return nil
            }
            return RiskLLMSignal(target: target, polarity: .positive, sourceText: matched.raw, sourceEvidence: sourceEvidence)
        }
    }
}
