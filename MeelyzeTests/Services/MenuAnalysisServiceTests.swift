import Testing
import Foundation
@testable import Meelyze

/// `MenuAnalysisService`が、TASK-037の変換結果を`RiskEvaluationService`へ渡し、その結果を
/// 元のOCR Bounding Boxと結び付けること、およびFoundation Models利用不可・料理単位の部分失敗時の
/// 縮退ルールを検証する。`RiskEvaluationService`自体（Issue #17の前処理→Menu Understanding→
/// Alias解決→DB Fact構築→Rule Engine）はfakeで差し替え、本Serviceが追加する結線・縮退ロジックだけを
/// 対象にする。
struct MenuAnalysisServiceTests {
    @Test func analyzeReturnsNoRecognizableTextForEmptyOCRResultWithoutCallingRiskEvaluationService() async {
        let riskEvaluationService = FakeRiskEvaluationService(result: MenuRiskEvaluationResult(items: [], failures: []))
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)

        let result = await service.analyze(OCRResult(observations: []), profile: profile(withAllergens: []))

        #expect(result == .noRecognizableText)
        #expect(riskEvaluationService.capturedRequest == nil)
    }

    @Test func analyzeReturnsNoRecognizableTextWhenAllObservationsAreWhitespaceOnly() async {
        let riskEvaluationService = FakeRiskEvaluationService(result: MenuRiskEvaluationResult(items: [], failures: []))
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "   ", confidence: 0.5, boundingBox: .zero)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: []))

        #expect(result == .noRecognizableText)
        #expect(riskEvaluationService.capturedRequest == nil)
    }

    @Test func analyzePassesBuiltRequestAndProfileToRiskEvaluationService() async {
        let riskEvaluationService = FakeRiskEvaluationService(result: MenuRiskEvaluationResult(items: [], failures: []))
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: .zero)
        ])
        let profile = profile(withAllergens: [.wheat])

        _ = await service.analyze(ocrResult, profile: profile)

        #expect(riskEvaluationService.capturedRequest?.segments.count == 1)
        #expect(riskEvaluationService.capturedRequest?.segments.first?.rawText == "沖縄そば")
        #expect(riskEvaluationService.capturedProfile === profile)
    }

    @Test func analyzeAttachesBoundingBoxAndPreservesResultsForSuccessfulItem() async throws {
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        let sourceID = MenuUnderstandingSourceID("ocr-source-0")
        let evaluation = MenuItemRiskEvaluation(
            reference: makeReference(sourceID: sourceID, rawFragment: "ラフテー"),
            results: [RiskEvaluationResult(target: .allergen(.pork), determination: .likelyContains, evidence: [RiskEvidence(kind: .dishDatabase)])]
        )
        let riskEvaluationService = FakeRiskEvaluationService(
            result: MenuRiskEvaluationResult(items: [evaluation], failures: [])
        )
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: box)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 1)
        #expect(summary.items.first?.boundingBoxes == [box])
        #expect(summary.items.first?.overallDetermination == .likelyContains)
        #expect(summary.items.first?.results.first?.evidence.first?.kind == .dishDatabase)
        #expect(summary.failures.isEmpty)
    }

    @Test func analyzeRestoresUndeterminedItemWithBoundingBoxForItemScopedFailure() async throws {
        let box = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.2)
        let sourceID = MenuUnderstandingSourceID("ocr-source-0")
        let failure = RiskEvaluationFailure(
            scope: .item(makeReference(sourceID: sourceID, rawFragment: "未知の料理")),
            reason: .aliasResolutionFailed,
            retryability: .notRetryable
        )
        let riskEvaluationService = FakeRiskEvaluationService(
            result: MenuRiskEvaluationResult(items: [], failures: [failure])
        )
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "未知の料理", confidence: 0.9, boundingBox: box)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 1)
        #expect(summary.items.first?.boundingBoxes == [box])
        #expect(summary.items.first?.overallDetermination == .undetermined)
        #expect(summary.items.first?.results.allSatisfy { $0.determination == .undetermined } == true)
        // item scopeの失敗は復元済みitemへ変換され、failuresへ二重に残さない。
        #expect(summary.failures.isEmpty)
    }

    @Test func analyzeKeepsSuccessfulItemAlongsideRestoredItemScopedFailureInOrdinalOrder() async throws {
        // `firstBox`は`secondBox`より上（y値が大きい。Visionの座標系は原点左下）に置き、読み取り順
        // （`OCRReadingOrderSorter`、FIX-010）でもocr-source-0（`firstBox`）が先になるようにする。
        let firstBox = CGRect(x: 0, y: 0.3, width: 0.2, height: 0.2)
        let secondBox = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let successID = MenuUnderstandingSourceID("ocr-source-0")
        let failedID = MenuUnderstandingSourceID("ocr-source-1")

        let successEvaluation = MenuItemRiskEvaluation(
            reference: makeReference(sourceID: successID, rawFragment: "ラフテー", ordinal: 0),
            results: [RiskEvaluationResult(target: .allergen(.pork), determination: .likelyContains, evidence: [])]
        )
        let failure = RiskEvaluationFailure(
            scope: .item(makeReference(sourceID: failedID, rawFragment: "未知の料理", ordinal: 1)),
            reason: .aliasResolutionFailed,
            retryability: .notRetryable
        )
        let riskEvaluationService = FakeRiskEvaluationService(
            result: MenuRiskEvaluationResult(items: [successEvaluation], failures: [failure])
        )
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: firstBox),
            RecognizedTextObservation(text: "未知の料理", confidence: 0.9, boundingBox: secondBox)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 2)
        #expect(summary.items[0].overallDetermination == .likelyContains)
        #expect(summary.items[0].boundingBoxes == [firstBox])
        #expect(summary.items[1].overallDetermination == .undetermined)
        #expect(summary.items[1].boundingBoxes == [secondBox])
    }

    @Test func analyzeFallsBackToPerSegmentUndeterminedWhenModelUnavailableAndNoItemsAtAll() async throws {
        // `firstBox`を`secondBox`より上に置く理由は
        // `analyzeKeepsSuccessfulItemAlongsideRestoredItemScopedFailureInOrdinalOrder`と同じ。
        let firstBox = CGRect(x: 0, y: 0.3, width: 0.2, height: 0.2)
        let secondBox = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let failure = RiskEvaluationFailure(
            scope: .request,
            reason: .menuUnderstanding(.modelUnavailable(.appleIntelligenceNotEnabled)),
            retryability: .notRetryable
        )
        let riskEvaluationService = FakeRiskEvaluationService(
            result: MenuRiskEvaluationResult(items: [], failures: [failure])
        )
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: firstBox),
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: secondBox)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 2)
        #expect(summary.items.allSatisfy { $0.overallDetermination == .undetermined } == true)
        #expect(summary.items[0].boundingBoxes == [firstBox])
        #expect(summary.items[1].boundingBoxes == [secondBox])
        // Foundation Models利用不可の事実は、フォールバックitemを生成しても失われず保持される。
        #expect(summary.failures.count == 1)
        #expect(summary.failures.first?.reason == .menuUnderstanding(.modelUnavailable(.appleIntelligenceNotEnabled)))
    }

    @Test func analyzeFallbackExcludesPriceOnlySegmentButKeepsDishSegment() async throws {
        // FIX-013: `500円`のような価格のみのOCRセグメントは、料理ではないためフォールバックの
        // 判定対象itemにしない。`dishBox`は`priceBox`より上に置き、読み取り順で先になるようにする
        // （他のフォールバックテストと同じ理由、FIX-010）。
        let dishBox = CGRect(x: 0, y: 0.3, width: 0.2, height: 0.2)
        let priceBox = CGRect(x: 0.3, y: 0.3, width: 0.1, height: 0.2)
        let failure = RiskEvaluationFailure(
            scope: .request,
            reason: .menuUnderstanding(.modelUnavailable(.appleIntelligenceNotEnabled)),
            retryability: .notRetryable
        )
        let riskEvaluationService = FakeRiskEvaluationService(
            result: MenuRiskEvaluationResult(items: [], failures: [failure])
        )
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: dishBox),
            RecognizedTextObservation(text: "500円", confidence: 0.9, boundingBox: priceBox)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.count == 1)
        #expect(summary.items.first?.boundingBoxes == [dishBox])
        #expect(summary.items.first?.reference.originalText == "ラフテー")
        #expect(summary.items.first?.overallDetermination == .undetermined)
    }

    @Test func analyzeDoesNotFabricateItemsWhenZeroItemsAreAGenuineResultWithoutFailures() async throws {
        let riskEvaluationService = FakeRiskEvaluationService(result: MenuRiskEvaluationResult(items: [], failures: []))
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "店名: サンプル食堂", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.isEmpty)
        #expect(summary.failures.isEmpty)
    }

    @Test func analyzeDoesNotFabricateItemsForSourcesScopedFailureWithoutModelUnavailable() async throws {
        let failure = RiskEvaluationFailure(
            scope: .sources([MenuUnderstandingSourceID("ocr-source-0")]),
            reason: .menuUnderstanding(.generationFailed(.contextWindowExceeded)),
            retryability: .retryable
        )
        let riskEvaluationService = FakeRiskEvaluationService(
            result: MenuRiskEvaluationResult(items: [], failures: [failure])
        )
        let service = DefaultMenuAnalysisService(riskEvaluationService: riskEvaluationService)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: .zero)
        ])

        let result = await service.analyze(ocrResult, profile: profile(withAllergens: [.pork]))

        let summary = try #require(completedSummary(from: result))
        #expect(summary.items.isEmpty)
        #expect(summary.failures.count == 1)
    }

    // MARK: - Fixtures

    private func makeReference(
        sourceID: MenuUnderstandingSourceID,
        rawFragment: String,
        ordinal: Int = 0
    ) -> MenuUnderstandingItemReference {
        MenuUnderstandingItemReference(
            ordinal: ordinal,
            sourceReferences: [MenuUnderstandingSourceReference(sourceID: sourceID, rawFragment: rawFragment)],
            separator: "\n"
        )
    }

    private func profile(withAllergens allergens: [AllergenItem]) -> UserProfile {
        UserProfile(allergenItems: allergens)
    }

    private func completedSummary(from result: MenuAnalysisResult) -> MenuAnalysisSummary? {
        guard case .completed(let summary) = result else { return nil }
        return summary
    }
}

/// `RiskEvaluationService`のfake。渡された`request`・`profile`を記録し、事前に設定した結果を返す。
private final class FakeRiskEvaluationService: RiskEvaluationService {
    private let result: MenuRiskEvaluationResult
    private(set) var capturedRequest: MenuUnderstandingRequest?
    private(set) var capturedProfile: UserProfile?

    init(result: MenuRiskEvaluationResult) {
        self.result = result
    }

    func evaluate(_ request: MenuUnderstandingRequest, profile: UserProfile) async -> MenuRiskEvaluationResult {
        capturedRequest = request
        capturedProfile = profile
        return result
    }
}
