import Testing
import Foundation
@testable import Meelyze

struct MenuAliasResolverTests {
    @Test func resolveDishCandidateReturnsResolvedWhenOneAliasMatches() throws {
        let repository = FakeMenuKnowledgeRepository()
        repository.dishesByName["ゴーヤーチャンプルー"] = [
            Dish(id: "goya_chanpuru", canonicalName: "ゴーヤーチャンプルー", region: "okinawa"),
        ]
        let resolver = MenuAliasResolver(repository: repository)

        let evidence = try resolver.resolveDishCandidate("ゴーヤー・チャンプルー")

        #expect(evidence.entityType == .dish)
        #expect(evidence.status == .resolved)
        #expect(evidence.normalization.normalizedText == "ゴーヤーチャンプルー")
        #expect(evidence.matches.map(\.id) == ["goya_chanpuru"])
    }

    @Test func resolveIngredientCandidateClassifiesUnresolvedAndAmbiguous() throws {
        let repository = FakeMenuKnowledgeRepository()
        repository.ingredientsByName["豆腐"] = [
            Ingredient(id: "okinawan_tofu", canonicalName: "沖縄豆腐"),
            Ingredient(id: "regular_tofu", canonicalName: "豆腐"),
        ]
        let resolver = MenuAliasResolver(repository: repository)

        let ambiguous = try resolver.resolveIngredientCandidate("豆腐")
        let unresolved = try resolver.resolveIngredientCandidate("島らっきょう")

        #expect(ambiguous.status == .ambiguous)
        #expect(ambiguous.matches.map(\.id) == ["okinawan_tofu", "regular_tofu"])
        #expect(unresolved.status == .unresolved)
        #expect(unresolved.matches.isEmpty)
    }

    @Test func resolveItemCarriesSourceEvidenceAndDoesNotMakeSafetyJudgments() throws {
        let repository = FakeMenuKnowledgeRepository()
        repository.dishesByName["ラフテー"] = [Dish(id: "rafute", canonicalName: "ラフテー", region: "okinawa")]
        repository.ingredientsByName["豚肉"] = [Ingredient(id: "pork", canonicalName: "豚肉")]
        let resolver = MenuAliasResolver(repository: repository)
        let sourceID = MenuUnderstandingSourceID("s1")
        let reference = MenuUnderstandingItemReference(
            ordinal: 0,
            sourceReferences: [MenuUnderstandingSourceReference(sourceID: sourceID, rawFragment: "ラフテー 豚肉")],
            separator: "\n"
        )
        let item = ParsedMenuItem(
            reference: reference,
            baseDishCandidates: ["ラフテー"],
            explicitIngredients: ["豚肉"],
            preparationMethods: [],
            modifiers: [],
            unknownTerms: []
        )
        let sourceEvidence = MenuTextPreprocessingEvidence(
            sourceID: sourceID,
            rawText: "ラフテー 豚肉 980円",
            analysisText: "ラフテー 豚肉",
            confidence: 0.8,
            boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
            changes: [.priceRemoved]
        )

        let evidence = try resolver.resolve(item, sourceEvidence: [sourceEvidence])

        #expect(evidence.reference.originalText == "ラフテー 豚肉")
        #expect(evidence.sourceEvidence.map(\.sourceID) == [sourceID])
        #expect(evidence.baseDishCandidateResolutions.map(\.status) == [.resolved])
        #expect(evidence.explicitIngredientResolutions.map(\.status) == [.resolved])
    }
}

private final class FakeMenuKnowledgeRepository: MenuKnowledgeRepository {
    var dishesByName: [String: [Dish]] = [:]
    var ingredientsByName: [String: [Ingredient]] = [:]

    func dish(id: String) throws -> Dish? { nil }
    func dishes(matchingName name: String) throws -> [Dish] { dishesByName[name] ?? [] }
    func ingredient(id: String) throws -> Ingredient? { nil }
    func allergen(id: String) throws -> Allergen? { nil }
    func restriction(id: String) throws -> Restriction? { nil }
    func evidenceSource(id: String) throws -> EvidenceSource? { nil }
    func ingredients(matchingName name: String) throws -> [Ingredient] { ingredientsByName[name] ?? [] }
    func upsertDish(_ dish: Dish) throws {}
    func upsertIngredient(_ ingredient: Ingredient) throws {}
    func upsertAllergen(_ allergen: Allergen) throws {}
    func upsertRestriction(_ restriction: Restriction) throws {}
    func upsertEvidenceSource(_ source: EvidenceSource) throws {}
    func upsertDishIngredient(
        dishId: String,
        ingredientId: String,
        confidence: DishIngredientConfidence,
        isHiddenIngredient: Bool,
        hiddenIngredientCategory: HiddenIngredientCategory?,
        sourceIds: [String]
    ) throws {}
    func upsertIngredientAllergen(ingredientId: String, allergenId: String, sourceIds: [String]) throws {}
    func upsertIngredientRestriction(ingredientId: String, restrictionId: String, sourceIds: [String]) throws {}
    func hasImportedDataVersion(_ id: String) throws -> Bool { false }
    func markDataVersionImported(_ id: String) throws {}
}
