import Foundation

/// 正規化済みの料理名・食材名候補を、ローカルDBの正規名/aliasへ照合する。
struct MenuAliasResolver {
    private let repository: MenuKnowledgeRepository
    private let normalizer: MenuNameNormalizer

    init(repository: MenuKnowledgeRepository, normalizer: MenuNameNormalizer = MenuNameNormalizer()) {
        self.repository = repository
        self.normalizer = normalizer
    }

    func resolveDishCandidate(_ candidate: String) throws -> MenuAliasResolutionEvidence {
        let normalization = normalizer.normalize(candidate)
        let dishes = try repository.dishes(matchingName: normalization.normalizedText)
        return MenuAliasResolutionEvidence(
            entityType: .dish,
            inputText: candidate,
            normalization: normalization,
            status: Self.status(forMatchCount: dishes.count),
            matches: dishes.map { MenuAliasResolvedEntity(id: $0.id, canonicalName: $0.canonicalName) }
        )
    }

    func resolveIngredientCandidate(_ candidate: String) throws -> MenuAliasResolutionEvidence {
        let normalization = normalizer.normalize(candidate)
        let ingredients = try repository.ingredients(matchingName: normalization.normalizedText)
        return MenuAliasResolutionEvidence(
            entityType: .ingredient,
            inputText: candidate,
            normalization: normalization,
            status: Self.status(forMatchCount: ingredients.count),
            matches: ingredients.map { MenuAliasResolvedEntity(id: $0.id, canonicalName: $0.canonicalName) }
        )
    }

    func resolve(_ item: ParsedMenuItem, sourceEvidence: [MenuTextPreprocessingEvidence]) throws -> MenuItemNormalizationEvidence {
        let evidenceByID = Dictionary(uniqueKeysWithValues: sourceEvidence.map { ($0.sourceID, $0) })
        let itemSourceEvidence = item.reference.sourceReferences.compactMap { evidenceByID[$0.sourceID] }

        return MenuItemNormalizationEvidence(
            reference: item.reference,
            sourceEvidence: itemSourceEvidence,
            baseDishCandidateResolutions: try item.baseDishCandidates.map(resolveDishCandidate(_:)),
            explicitIngredientResolutions: try item.explicitIngredients.map(resolveIngredientCandidate(_:))
        )
    }

    private static func status(forMatchCount count: Int) -> MenuAliasResolutionStatus {
        switch count {
        case 0: return .unresolved
        case 1: return .resolved
        default: return .ambiguous
        }
    }
}
