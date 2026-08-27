import Testing
import Foundation
@testable import Meelyze

@MainActor
struct MenuAnalysisViewModelTests {
    @Test func initialStateIsIdle() {
        let viewModel = MenuAnalysisViewModel(
            menuAnalysisService: FakeMenuAnalysisService(result: .noRecognizableText),
            profileRepository: FakeProfileRepository()
        )

        #expect(viewModel.analysisState == .idle)
        #expect(viewModel.isProcessing == false)
    }

    @Test func analyzeTransitionsToCompletedWithResultFromServiceUsingCurrentProfile() async {
        let profile = UserProfile(allergenItems: [.pork])
        let profileRepository = FakeProfileRepository()
        profileRepository.profileToReturn = profile
        let service = FakeMenuAnalysisService(result: .noRecognizableText)
        let viewModel = MenuAnalysisViewModel(menuAnalysisService: service, profileRepository: profileRepository)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "ラフテー", confidence: 0.9, boundingBox: .zero)
        ])

        await viewModel.analyze(ocrResult: ocrResult)

        #expect(viewModel.analysisState == .completed(.noRecognizableText))
        #expect(viewModel.isProcessing == false)
        #expect(service.callCount == 1)
        #expect(service.capturedOCRResult == ocrResult)
        #expect(service.capturedProfile === profile)
    }

    @Test func analyzeFailsWithProfileUnavailableWhenNoProfileIsSaved() async {
        let profileRepository = FakeProfileRepository()
        profileRepository.profileToReturn = nil
        let service = FakeMenuAnalysisService(result: .noRecognizableText)
        let viewModel = MenuAnalysisViewModel(menuAnalysisService: service, profileRepository: profileRepository)

        await viewModel.analyze(ocrResult: OCRResult(observations: []))

        #expect(viewModel.analysisState == .failed(.profileUnavailable))
        #expect(service.callCount == 0)
    }

    @Test func analyzeFailsWithProfileUnavailableWhenProfileRepositoryThrows() async {
        let profileRepository = FakeProfileRepository()
        profileRepository.errorToThrow = StubError()
        let service = FakeMenuAnalysisService(result: .noRecognizableText)
        let viewModel = MenuAnalysisViewModel(menuAnalysisService: service, profileRepository: profileRepository)

        await viewModel.analyze(ocrResult: OCRResult(observations: []))

        #expect(viewModel.analysisState == .failed(.profileUnavailable))
        #expect(service.callCount == 0)
    }

    @Test func analyzeIgnoresReentrantCallWhileProcessing() async {
        let profileRepository = FakeProfileRepository()
        profileRepository.profileToReturn = UserProfile(allergenItems: [])
        let service = GatedFakeMenuAnalysisService(result: .noRecognizableText)
        let viewModel = MenuAnalysisViewModel(menuAnalysisService: service, profileRepository: profileRepository)

        let firstCall = Task { await viewModel.analyze(ocrResult: OCRResult(observations: [])) }

        // ポーリングではなく、Fake Service自身が「実行開始した」ことを継続で通知するまで
        // 構造化されたawaitで待つ。busy-loopなポーリングは、テスト実行環境の
        // executor/schedulingの詳細次第でTask.yield()が他のTaskへ実際に制御を譲らずハングしうる
        // ため使わない。
        await service.waitUntilStarted()

        // 処理中の再入呼び出しは無視される。
        await viewModel.analyze(ocrResult: OCRResult(observations: []))
        #expect(await service.callCount == 1)
        #expect(viewModel.analysisState == .processing)

        await service.resume()
        await firstCall.value

        #expect(viewModel.analysisState == .completed(.noRecognizableText))
    }

    @Test func analyzeAllowsReanalyzingAfterPreviousCallCompletes() async {
        let profileRepository = FakeProfileRepository()
        profileRepository.profileToReturn = UserProfile(allergenItems: [])
        let service = FakeMenuAnalysisService(result: .noRecognizableText)
        let viewModel = MenuAnalysisViewModel(menuAnalysisService: service, profileRepository: profileRepository)

        await viewModel.analyze(ocrResult: OCRResult(observations: []))
        await viewModel.analyze(ocrResult: OCRResult(observations: []))

        #expect(service.callCount == 2)
        #expect(viewModel.analysisState == .completed(.noRecognizableText))
    }
}

private struct StubError: Error {}

/// `ProfileRepository`のfake。`profileToReturn`未設定（`nil`）はオンボーディング未完了を、
/// `errorToThrow`設定は読み込み失敗を表す。
private final class FakeProfileRepository: ProfileRepository {
    var profileToReturn: UserProfile?
    var errorToThrow: Error?

    func currentProfile() throws -> UserProfile? {
        if let errorToThrow { throw errorToThrow }
        return profileToReturn
    }

    func save(_ profile: UserProfile) throws {
        profileToReturn = profile
    }
}

/// `MenuAnalysisService`のfake。渡された`ocrResult`・`profile`を記録し、事前に設定した結果を返す。
private final class FakeMenuAnalysisService: MenuAnalysisService {
    private let result: MenuAnalysisResult
    private(set) var callCount = 0
    private(set) var capturedOCRResult: OCRResult?
    private(set) var capturedProfile: UserProfile?

    init(result: MenuAnalysisResult) {
        self.result = result
    }

    func analyze(_ ocrResult: OCRResult, profile: UserProfile) async -> MenuAnalysisResult {
        callCount += 1
        capturedOCRResult = ocrResult
        capturedProfile = profile
        return result
    }
}

/// `MenuAnalysisService`のfake。`resume()`が呼ばれるまで`analyze(_:profile:)`を一時停止させ、
/// 処理中（`.processing`）の間に発生した再入呼び出しを決定的に検証できるようにする。
///
/// `analyze(_:profile:)`（`MenuAnalysisViewModel`側から実行される）と`waitUntilStarted()`
/// （テスト側から実行される）は互いに独立した非isolatedなコンテキストから並行に呼ばれうるため、
/// `final class`にすると`hasStarted`のcheck-and-setと`startedContinuation`の登録の間に
/// レース（"started"通知が先に発生し、後から登録されたcontinuationが二度と解決されずハングする
/// TOCTOU）が生じる。`actor`にすることで、この2箇所が互いにinterleaveしないことを保証する。
private actor GatedFakeMenuAnalysisService: MenuAnalysisService {
    private let result: MenuAnalysisResult
    private(set) var callCount = 0
    private var hasStarted = false
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    init(result: MenuAnalysisResult) {
        self.result = result
    }

    func analyze(_ ocrResult: OCRResult, profile: UserProfile) async -> MenuAnalysisResult {
        callCount += 1
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            self.resumeContinuation = continuation
        }
        return result
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            self.startedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
