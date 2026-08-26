import Foundation

/// Issue #16のAlias解決結果1件（料理名候補または明示食材の候補1つ）と、対象`UserProfile`が選択した
/// アレルゲン・食事制限から、`RiskRuleEngine`（TASK-032）が消費するimmutableな`RiskFact`を構築する。
///
/// `resolved`な候補のみ`MenuKnowledgeRepository`経由でDishIngredient/Ingredient/IngredientAllergen/
/// IngredientRestrictionを辿り、確定的な一致・不一致を`RiskFact.databaseMatches`へ変換する。
/// `unresolved` `ambiguous`な候補からは、確定的な「含まれる」「含まれない」Factを生成しない。
struct RiskFactBuilder {
    private let repository: MenuKnowledgeRepository

    init(repository: MenuKnowledgeRepository) {
        self.repository = repository
    }

    /// UserProfileが選択した`RiskTarget`ごとに、1件のAlias解決結果からFactを構築する。
    /// UserProfileが何も選択していなければ空配列を返す（対象外のノイズを増やさない）。
    ///
    /// DB取得自体が失敗した場合は例外を投げず、影響を受けるtargetだけ`.databaseUnavailable`の
    /// Factへ倒す。1候補のDB障害で呼び出し元の他候補の評価を止めないための設計。
    func buildFacts(
        for resolution: MenuAliasResolutionEvidence,
        sourceEvidence: [MenuTextPreprocessingEvidence],
        profile: UserProfile
    ) -> [RiskFact] {
        let targets = profile.selectedRiskTargets
        guard !targets.isEmpty else { return [] }

        switch resolution.status {
        case .unresolved:
            let evidence = RiskEvidence(
                kind: .unknown,
                sourceEvidence: sourceEvidence,
                normalization: resolution.normalization,
                inferredOrigin: .unresolvedTerm
            )
            return targets.map { RiskFact(target: $0, resolution: .unresolved, databaseMatches: [], evidence: [evidence]) }

        case .ambiguous:
            let evidence = RiskEvidence(
                kind: .unknown,
                sourceEvidence: sourceEvidence,
                normalization: resolution.normalization,
                inferredOrigin: .ambiguousCandidates(resolution.matches)
            )
            return targets.map { RiskFact(target: $0, resolution: .ambiguous, databaseMatches: [], evidence: [evidence]) }

        case .resolved:
            // MenuAliasResolver.status(forMatchCount:)の契約上、.resolvedはmatches.count == 1のはず。
            // 契約が破られていた場合も未解決として安全側に倒し、架空のCanonical Entityを捏造しない。
            guard let match = resolution.matches.first else {
                return targets.map { RiskFact(target: $0, resolution: .unresolved, databaseMatches: [], evidence: []) }
            }

            let matchesByTarget: [RiskTarget: [RiskFactDatabaseMatch]]
            do {
                matchesByTarget = try databaseMatchesByTarget(for: match, entityType: resolution.entityType)
            } catch {
                // Alias解決自体は一意に成功しているため、その解決先と正規化根拠はEvidenceへ残す。
                // 失敗したのはより深いDish/Ingredient関連の取得だけであることを`.databaseFetchFailed`で明示する。
                let provenance = Self.textProvenanceEvidence(
                    normalization: resolution.normalization,
                    entityType: resolution.entityType,
                    resolvedEntity: match,
                    sourceEvidence: sourceEvidence
                )
                let failure = RiskEvidence(
                    kind: .unknown,
                    sourceEvidence: sourceEvidence,
                    normalization: resolution.normalization,
                    resolvedEntityType: resolution.entityType,
                    resolvedEntity: match,
                    inferredOrigin: .databaseFetchFailed
                )
                return targets.map { RiskFact(target: $0, resolution: .databaseUnavailable, databaseMatches: [], evidence: [provenance, failure]) }
            }

            return targets.map { target in
                let databaseMatches = matchesByTarget[target] ?? []
                return RiskFact(
                    target: target,
                    resolution: .resolved,
                    databaseMatches: databaseMatches,
                    evidence: resolvedEvidence(
                        match: match,
                        entityType: resolution.entityType,
                        normalization: resolution.normalization,
                        sourceEvidence: sourceEvidence,
                        databaseMatches: databaseMatches
                    )
                )
            }
        }
    }

    /// 一意に解決されたCanonical Entityについて、DBを辿って対象ごとの一致を集計する。
    /// 料理の場合は`DishIngredient`（通常食材・隠れ食材の両方）を経由し、明示食材の場合は
    /// その食材自体のアレルゲン・食事制限を直接確認する（明示済みのためconfidenceは`.confirmed`固定・
    /// 隠れ食材ではない）。
    private func databaseMatchesByTarget(
        for match: MenuAliasResolvedEntity,
        entityType: MenuAliasEntityType
    ) throws -> [RiskTarget: [RiskFactDatabaseMatch]] {
        var result: [RiskTarget: [RiskFactDatabaseMatch]] = [:]

        switch entityType {
        case .dish:
            guard let dish = try repository.dish(id: match.id) else {
                throw RiskFactBuilderError.resolvedEntityNotFound(id: match.id)
            }
            // SwiftDataの@Relationship配列は格納順を保証しないため、id順に安定させてから走査する
            // （SwiftDataMenuKnowledgeRepository.dishes(matchingName:)等と同じ理由）。
            for link in dish.ingredients.sorted(by: { $0.ingredient.id < $1.ingredient.id }) {
                appendMatches(
                    for: link.ingredient,
                    confidence: link.confidence,
                    isHiddenIngredient: link.isHiddenIngredient,
                    hiddenIngredientCategory: link.hiddenIngredientCategory,
                    linkSourceIDs: link.sourceIds,
                    into: &result
                )
            }

        case .ingredient:
            guard let ingredient = try repository.ingredient(id: match.id) else {
                throw RiskFactBuilderError.resolvedEntityNotFound(id: match.id)
            }
            appendMatches(
                for: ingredient,
                confidence: .confirmed,
                isHiddenIngredient: false,
                hiddenIngredientCategory: nil,
                linkSourceIDs: [],
                into: &result
            )
        }

        return result
    }

    private func appendMatches(
        for ingredient: Ingredient,
        confidence: DishIngredientConfidence,
        isHiddenIngredient: Bool,
        hiddenIngredientCategory: HiddenIngredientCategory?,
        linkSourceIDs: [String],
        into result: inout [RiskTarget: [RiskFactDatabaseMatch]]
    ) {
        for allergenLink in ingredient.allergens.sorted(by: { $0.allergen.id < $1.allergen.id }) {
            // UserProfile.allergenItemsと同様、Allergen.idはAllergenItem.rawValueと対応する契約。
            // 未知のrawValueはこのアプリが選択肢として提示し得ないtargetなので、安全に読み飛ばす。
            guard let allergenItem = AllergenItem(rawValue: allergenLink.allergen.id) else { continue }
            result[.allergen(allergenItem), default: []].append(
                RiskFactDatabaseMatch(
                    ingredientID: ingredient.id,
                    confidence: confidence,
                    isHiddenIngredient: isHiddenIngredient,
                    hiddenIngredientCategory: hiddenIngredientCategory,
                    sourceIDs: Self.mergedSourceIDs(linkSourceIDs, allergenLink.sourceIds)
                )
            )
        }

        for restrictionLink in ingredient.restrictions.sorted(by: { $0.restriction.id < $1.restriction.id }) {
            result[.dietaryRestriction(restrictionLink.restriction.category), default: []].append(
                RiskFactDatabaseMatch(
                    ingredientID: ingredient.id,
                    confidence: confidence,
                    isHiddenIngredient: isHiddenIngredient,
                    hiddenIngredientCategory: hiddenIngredientCategory,
                    sourceIDs: Self.mergedSourceIDs(linkSourceIDs, restrictionLink.sourceIds)
                )
            )
        }
    }

    /// 料理↔食材の関連根拠と、食材↔アレルゲン/食事制限の関連根拠を、順序を保ったまま重複排除して結合する。
    private static func mergedSourceIDs(_ linkSourceIDs: [String], _ tagSourceIDs: [String]) -> [String] {
        var seen = Set<String>()
        return (linkSourceIDs + tagSourceIDs).filter { seen.insert($0).inserted }
    }

    /// 候補テキストがCanonical Entityへ解決されたことを示す、DB照合より手前の根拠。正規化で
    /// 文字列が変化していなければ「原文に直接記載されていた情報」（`.explicit`）、変化していれば
    /// 「Alias Dictionaryによって正規化された情報」（`.normalized`）として区別する
    /// （`docs/technology-selection.md`「9. Risk Aggregation / Evidence」）。
    private static func textProvenanceEvidence(
        normalization: MenuNameNormalizationEvidence,
        entityType: MenuAliasEntityType,
        resolvedEntity: MenuAliasResolvedEntity,
        sourceEvidence: [MenuTextPreprocessingEvidence]
    ) -> RiskEvidence {
        RiskEvidence(
            kind: normalization.changes.isEmpty ? .explicit : .normalized,
            sourceEvidence: sourceEvidence,
            normalization: normalization,
            resolvedEntityType: entityType,
            resolvedEntity: resolvedEntity
        )
    }

    private func resolvedEvidence(
        match: MenuAliasResolvedEntity,
        entityType: MenuAliasEntityType,
        normalization: MenuNameNormalizationEvidence,
        sourceEvidence: [MenuTextPreprocessingEvidence],
        databaseMatches: [RiskFactDatabaseMatch]
    ) -> [RiskEvidence] {
        let provenance = Self.textProvenanceEvidence(
            normalization: normalization, entityType: entityType, resolvedEntity: match, sourceEvidence: sourceEvidence
        )

        guard !databaseMatches.isEmpty else {
            return [
                provenance,
                RiskEvidence(
                    kind: .dishDatabase,
                    sourceEvidence: sourceEvidence,
                    normalization: normalization,
                    resolvedEntityType: entityType,
                    resolvedEntity: match
                )
            ]
        }

        return [provenance] + databaseMatches.map { databaseMatch in
            RiskEvidence(
                kind: .dishDatabase,
                sourceEvidence: sourceEvidence,
                normalization: normalization,
                resolvedEntityType: entityType,
                resolvedEntity: match,
                databaseSourceIDs: databaseMatch.sourceIDs,
                isHiddenIngredient: databaseMatch.isHiddenIngredient,
                hiddenIngredientCategory: databaseMatch.hiddenIngredientCategory
            )
        }
    }
}

enum RiskFactBuilderError: Error, Equatable {
    case resolvedEntityNotFound(id: String)
}
