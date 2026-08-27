import SwiftUI

/// S09 料理詳細・判定根拠画面。OCR原文・正規化結果・DB照合結果・LLM由来の補助Evidence・unknown情報・
/// 最終判定の根拠を、DB由来／LLM由来を区別して表示する（Issue #20完了条件8・9）。
///
/// 判定結果自体（`RiskEvaluationResult.determination`）は再計算せず、Issue #17/#19が返した値を
/// そのまま表示する。S08から`NavigationStack` + `.navigationDestination(for:)`で遷移する
/// （`ResultOverlayView`参照）。「店員に確認」ボタン自体はIssue #21の担当のため、本Viewでは作らない。
struct DishDetailView: View {
    let item: MenuAnalysisItemResult
    let translatedDishName: String?
    let displayLanguage: DisplayLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RiskResultCardView(
                    style: .detailed,
                    japaneseDishName: item.reference.originalText,
                    translatedDishName: translatedDishName,
                    determination: overallDetermination,
                    matchedTargetNames: matchedTargetNames,
                    reasonText: overallReasonText,
                    displayLanguage: displayLanguage
                )

                SafetyNoticeView(variant: .persistentResultNotice, displayLanguage: displayLanguage)

                ForEach(Array(item.results.enumerated()), id: \.offset) { _, result in
                    targetSection(for: result)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("DishDetailView")
    }

    private var overallDetermination: RiskDetermination {
        item.overallDetermination ?? .undetermined
    }

    private var matchedTargetNames: [String] {
        item.results
            .filter { $0.determination == .likelyContains }
            .map { $0.target.localizedName(for: displayLanguage) }
    }

    private var overallReasonText: String? {
        guard overallDetermination == .undetermined else { return nil }
        return UndeterminedReason.from(item.results.flatMap(\.evidence))?.message(for: displayLanguage)
    }

    private func targetSection(for result: RiskEvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.target.localizedName(for: displayLanguage))
                    .font(.headline)
                Spacer()
                RiskBadgeView(determination: result.determination, displayLanguage: displayLanguage)
            }

            if result.evidence.isEmpty {
                // `RiskResultCardView`と同じ理由（TASK-053で判明: `.secondary`は`.font(.caption)`との
                // 組み合わせでライトモードのAAコントラスト基準を満たさない）で`.primary`を使う。
                Text(DishDetailText.noEvidence.value(for: displayLanguage))
                    .font(.caption)
                    .foregroundStyle(.primary)
            } else {
                ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, evidence in
                    EvidenceRowView(evidence: evidence, displayLanguage: displayLanguage)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DishDetailTargetSection")
    }
}

private enum DishDetailText {
    static let noEvidence = LocalizedText(
        english: "No supporting evidence available.",
        traditionalChinese: "沒有可供參考的根據。",
        simplifiedChinese: "没有可供参考的依据。",
        korean: "참고할 근거가 없습니다."
    )
}

#Preview {
    let reference = MenuUnderstandingItemReference(
        ordinal: 0,
        sourceReferences: [MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s0"), rawFragment: "ラフテー")],
        separator: ""
    )
    let evidence = RiskEvidence(
        kind: .dishDatabase,
        resolvedEntityType: .dish,
        resolvedEntity: MenuAliasResolvedEntity(id: "dish-1", canonicalName: "ラフテー"),
        isHiddenIngredient: true,
        hiddenIngredientCategory: .fatOrOil
    )
    let result = RiskEvaluationResult(target: .allergen(.pork), determination: .likelyContains, evidence: [evidence])
    let item = MenuAnalysisItemResult(
        evaluation: MenuItemRiskEvaluation(reference: reference, results: [result]),
        boundingBoxes: []
    )

    NavigationStack {
        DishDetailView(item: item, translatedDishName: "Braised Pork Belly", displayLanguage: .english)
    }
}
