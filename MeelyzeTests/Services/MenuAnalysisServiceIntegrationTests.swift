import Testing
import Foundation
import SwiftData
@testable import Meelyze

/// `MenuAnalysisService`を実SwiftData（`InitialMenuKnowledgeData.json`をインポート済み）・実
/// `MenuUnderstandingRequestBuilder`（TASK-037）・実`DefaultRiskEvaluationService`（Issue #17。
/// 前処理→Alias解決→DB Fact構築→Rule Engineを実結線）に対して動かす統合テスト。
///
/// `RiskEvaluationServiceIntegrationTests`（Issue #17）は`RiskEvaluationService`止まりで
/// OCR層を含まない。本テストはOCR結果（`OCRResult`）からTASK-038の`MenuAnalysisService`を通して
/// 呼び出すことで、Issue #19が新たに追加したBounding Box対応関係・縮退ロジックを、実際のDB照合・
/// Rule Engineと組み合わせて検証する。Apple Foundation Models自体はCI・多くのSimulatorで利用できない
/// ため、`MenuUnderstandingService`は既存の統合テストと同じくfakeで差し替える
/// （`task/TASK-040-analysis-pipeline-integration-tests.md`）。
@MainActor
struct MenuAnalysisServiceIntegrationTests {
    @Test func analyzeReturnsLikelyContainsForKnownPorkDishThroughTheFullPipeline() async throws {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)
        let sourceID = MenuUnderstandingSourceID("ocr-source-0")
        let item = makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        let service = try makeMenuAnalysisService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []), items: [item], availability: .available, failures: []
        ))
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: box)
        ])

        let result = await service.analyze(ocrResult, profile: profile(allergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 1)
        #expect(summary.items.first?.overallDetermination == .likelyContains)
        #expect(summary.items.first?.boundingBoxes == [box])
        #expect(summary.items.first?.results.first?.evidence.contains { $0.kind == .dishDatabase } == true)
    }

    @Test func analyzeReturnsNoRecordedMatchForKnownDishWithoutMatchingRecordThroughTheFullPipeline() async throws {
        let sourceID = MenuUnderstandingSourceID("ocr-source-0")
        let item = makeParsedItem(sourceID: sourceID, rawFragment: "沖縄そば", baseDishCandidates: ["沖縄そば"])
        let service = try makeMenuAnalysisService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []), items: [item], availability: .available, failures: []
        ))
        // 沖縄そばの初期データには卵アレルゲンの記録がない。0件検索を即座に「該当なし」にせず、
        // Rule Engineの決定論的な結果をそのまま伝播できることを確認する。
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.analyze(ocrResult, profile: profile(allergens: [.egg]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.first?.overallDetermination == .noRecordedMatch)
    }

    @Test func analyzeFallsBackToPerSegmentUndeterminedWhenFoundationModelsIsUnavailableThroughTheFullPipeline() async throws {
        let firstBox = CGRect(x: 0, y: 0, width: 0.2, height: 0.1)
        let secondBox = CGRect(x: 0, y: 0.2, width: 0.2, height: 0.1)
        let service = try makeMenuAnalysisService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []),
            items: [],
            availability: .unavailable(.appleIntelligenceNotEnabled),
            failures: [MenuUnderstandingFailure(
                scope: .request,
                reason: .modelUnavailable(.appleIntelligenceNotEnabled),
                retryability: .notRetryable
            )]
        ))
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: firstBox),
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: secondBox)
        ])

        let result = await service.analyze(ocrResult, profile: profile(allergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 2)
        #expect(summary.items.allSatisfy { $0.overallDetermination == .undetermined })
        #expect(summary.items[0].boundingBoxes == [firstBox])
        #expect(summary.items[1].boundingBoxes == [secondBox])
        // Foundation Models利用不可の事実は、フォールバックitemを生成しても失われず保持される。
        #expect(summary.failures.count == 1)
    }

    @Test func analyzeKeepsSuccessfulDishWhenAnotherDishFailsItemValidationThroughTheFullPipeline() async throws {
        let successBox = CGRect(x: 0, y: 0, width: 0.2, height: 0.1)
        let failedBox = CGRect(x: 0, y: 0.2, width: 0.2, height: 0.1)
        let successID = MenuUnderstandingSourceID("ocr-source-0")
        let failedID = MenuUnderstandingSourceID("ocr-source-1")
        let successItem = makeParsedItem(sourceID: successID, rawFragment: "ラフテー", ordinal: 0, baseDishCandidates: ["ラフテー"])
        let failedReference = MenuUnderstandingItemReference(
            ordinal: 1,
            sourceReferences: [MenuUnderstandingSourceReference(sourceID: failedID, rawFragment: "謎の一皿")],
            separator: "\n"
        )
        let service = try makeMenuAnalysisService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []),
            items: [successItem],
            availability: .available,
            failures: [MenuUnderstandingFailure(
                scope: .item(failedReference),
                reason: .itemValidationFailed(.explicitIngredientsNotInSource(["謎の食材"])),
                retryability: .notRetryable
            )]
        ))
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: successBox),
            RecognizedTextObservation(text: "謎の一皿", confidence: 0.9, boundingBox: failedBox)
        ])

        let result = await service.analyze(ocrResult, profile: profile(allergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 2)
        #expect(summary.items[0].overallDetermination == .likelyContains)
        #expect(summary.items[0].boundingBoxes == [successBox])
        #expect(summary.items[1].overallDetermination == .undetermined)
        #expect(summary.items[1].boundingBoxes == [failedBox])
        // item scopeの失敗は復元済みitemへ変換され、failuresへ二重に残さない。
        #expect(summary.failures.isEmpty)
    }

    @Test func analyzeReturnsNoRecognizableTextForEmptyOCRResultThroughTheFullPipeline() async throws {
        let service = try makeMenuAnalysisService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []), items: [], availability: .available, failures: []
        ))

        let result = await service.analyze(OCRResult(observations: []), profile: profile(allergens: [.pork]))

        #expect(result == .noRecognizableText)
    }

    @Test func viewModelReachesCompletedStateThroughTheFullRealStackIncludingProfileRepository() async throws {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)
        let sourceID = MenuUnderstandingSourceID("ocr-source-0")
        let item = makeParsedItem(sourceID: sourceID, rawFragment: "ラフテー", baseDishCandidates: ["ラフテー"])
        let menuAnalysisService = try makeMenuAnalysisService(result: MenuUnderstandingResult(
            request: MenuUnderstandingRequest(segments: []), items: [item], availability: .available, failures: []
        ))

        let profileRepository = SwiftDataProfileRepository(modelContext: try makeInMemoryContext())
        try profileRepository.save(profile(allergens: [.pork]))

        let viewModel = MenuAnalysisViewModel(menuAnalysisService: menuAnalysisService, profileRepository: profileRepository)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: box)
        ])

        await viewModel.analyze(ocrResult: ocrResult)

        let summary = try #require(completedSummary(from: viewModel.analysisState))
        #expect(summary.items.first?.overallDetermination == .likelyContains)
        #expect(summary.items.first?.boundingBoxes == [box])
    }

    // MARK: - Fixtures

    private func makeMenuAnalysisService(result: MenuUnderstandingResult) throws -> DefaultMenuAnalysisService {
        let repository = try makeSeededRepository()
        let understandingService = FakeMenuUnderstandingService(result: result)
        let riskEvaluationService = DefaultRiskEvaluationService(repository: repository, understandingService: understandingService)
        return DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
    }

    private func makeSeededRepository() throws -> SwiftDataMenuKnowledgeRepository {
        let repository = SwiftDataMenuKnowledgeRepository(modelContext: try makeInMemoryContext())
        _ = try InitialDataImportService(repository: repository)
            .importInitialDataIfNeeded(from: Data(contentsOf: initialMenuKnowledgeDataURL()))
        return repository
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self,
            Dish.self,
            DishAlias.self,
            Ingredient.self,
            IngredientAlias.self,
            DishIngredient.self,
            Allergen.self,
            Restriction.self,
            IngredientAllergen.self,
            IngredientRestriction.self,
            EvidenceSource.self,
            DataImportVersion.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func initialMenuKnowledgeDataURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Meelyze/Resources/InitialMenuKnowledgeData.json")
    }

    private func makeParsedItem(
        sourceID: MenuUnderstandingSourceID,
        rawFragment: String,
        ordinal: Int = 0,
        baseDishCandidates: [String],
        explicitIngredients: [String] = [],
        preparationMethods: [String] = [],
        modifiers: [String] = [],
        unknownTerms: [String] = []
    ) -> ParsedMenuItem {
        ParsedMenuItem(
            reference: MenuUnderstandingItemReference(
                ordinal: ordinal,
                sourceReferences: [MenuUnderstandingSourceReference(sourceID: sourceID, rawFragment: rawFragment)],
                separator: "\n"
            ),
            baseDishCandidates: baseDishCandidates,
            explicitIngredients: explicitIngredients,
            preparationMethods: preparationMethods,
            modifiers: modifiers,
            unknownTerms: unknownTerms
        )
    }

    private func profile(allergens: [AllergenItem] = [], restrictions: [DietaryRestrictionCategory] = []) -> UserProfile {
        UserProfile(allergenItems: allergens, dietaryRestrictionCategories: restrictions)
    }

    private func completedSummary(from result: MenuAnalysisResult) -> MenuAnalysisSummary? {
        guard case .completed(let summary) = result else { return nil }
        return summary
    }

    private func completedSummary(from state: MenuAnalysisViewModel.AnalysisState) -> MenuAnalysisSummary? {
        guard case .completed(let result) = state else { return nil }
        return completedSummary(from: result)
    }
}

/// `MenuUnderstandingService`のfake。渡された`request`を記録し、事前に設定した結果を返す。
private final class FakeMenuUnderstandingService: MenuUnderstandingService {
    private let result: MenuUnderstandingResult
    private(set) var capturedRequest: MenuUnderstandingRequest?

    init(result: MenuUnderstandingResult) {
        self.result = result
    }

    func availability() async -> MenuUnderstandingAvailability { .available }

    func analyze(_ request: MenuUnderstandingRequest) async -> MenuUnderstandingResult {
        capturedRequest = request
        return result
    }
}
