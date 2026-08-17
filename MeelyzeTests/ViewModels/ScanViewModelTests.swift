import Testing
import Foundation
import SwiftUI
@testable import Meelyze

@MainActor
struct ScanViewModelTests {

    @Test func alreadyAuthorizedStartsSessionWithoutRequestingAgain() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .authorized
        let viewModel = ScanViewModel(cameraService: cameraService, ocrService: FakeOCRService())

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .authorized)
        #expect(cameraService.startSessionCallCount == 1)
        #expect(viewModel.isShowingPermissionDeniedAlert == false)
    }

    @Test func notDeterminedAndGrantedStartsSession() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .notDetermined
        cameraService.requestAuthorizationResult = .authorized
        let viewModel = ScanViewModel(cameraService: cameraService, ocrService: FakeOCRService())

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .authorized)
        #expect(cameraService.startSessionCallCount == 1)
    }

    @Test func notDeterminedAndDeniedShowsPermissionDeniedAlertWithoutStartingSession() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .notDetermined
        cameraService.requestAuthorizationResult = .denied
        let viewModel = ScanViewModel(cameraService: cameraService, ocrService: FakeOCRService())

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .denied)
        #expect(viewModel.isShowingPermissionDeniedAlert == true)
        #expect(cameraService.startSessionCallCount == 0)
    }

    @Test func alreadyDeniedShowsPermissionDeniedAlertWithoutRequestingAgain() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .denied
        let viewModel = ScanViewModel(cameraService: cameraService, ocrService: FakeOCRService())

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .denied)
        #expect(viewModel.isShowingPermissionDeniedAlert == true)
        #expect(cameraService.requestAuthorizationCallCount == 0)
    }

    @Test func disappearStopsSession() {
        let cameraService = FakeCameraService()
        let viewModel = ScanViewModel(cameraService: cameraService, ocrService: FakeOCRService())

        viewModel.onDisappear()

        #expect(cameraService.stopSessionCallCount == 1)
    }

    @Test func successfulCaptureAndRecognitionHoldsResultAsRecognized() async {
        let observation = RecognizedTextObservation(text: "唐揚げ定食", confidence: 0.9, boundingBox: .zero)
        let ocrService = FakeOCRService()
        ocrService.recognizeTextResult = .success(OCRResult(observations: [observation]))
        let viewModel = ScanViewModel(cameraService: FakeCameraService(), ocrService: ocrService)

        await viewModel.capturePhoto()

        #expect(viewModel.scanState == .recognized(OCRResult(observations: [observation])))
    }

    @Test func lowConfidenceSingleObservationIsNotTreatedAsFailure() async {
        let lowConfidence = RecognizedTextObservation(text: "?", confidence: 0.05, boundingBox: .zero)
        let ocrService = FakeOCRService()
        ocrService.recognizeTextResult = .success(OCRResult(observations: [lowConfidence]))
        let viewModel = ScanViewModel(cameraService: FakeCameraService(), ocrService: ocrService)

        await viewModel.capturePhoto()

        #expect(viewModel.scanState != .failed)
    }

    @Test func zeroObservationsTransitionsToFailed() async {
        let ocrService = FakeOCRService()
        ocrService.recognizeTextResult = .success(OCRResult(observations: []))
        let viewModel = ScanViewModel(cameraService: FakeCameraService(), ocrService: ocrService)

        await viewModel.capturePhoto()

        #expect(viewModel.scanState == .failed)
    }

    @Test func ocrThrowingErrorTransitionsToFailed() async {
        let ocrService = FakeOCRService()
        ocrService.recognizeTextResult = .failure(OCRError.recognitionRequestFailed)
        let viewModel = ScanViewModel(cameraService: FakeCameraService(), ocrService: ocrService)

        await viewModel.capturePhoto()

        #expect(viewModel.scanState == .failed)
    }

    @Test func captureFailureTransitionsToFailedWithoutCallingOCR() async {
        let cameraService = FakeCameraService()
        cameraService.capturePhotoResult = .failure(CameraServiceError.captureFailed)
        let ocrService = FakeOCRService()
        let viewModel = ScanViewModel(cameraService: cameraService, ocrService: ocrService)

        await viewModel.capturePhoto()

        #expect(viewModel.scanState == .failed)
        #expect(ocrService.recognizeTextCallCount == 0)
    }

    @Test func retakeFromFailedReturnsToIdle() async {
        let ocrService = FakeOCRService()
        ocrService.recognizeTextResult = .success(OCRResult(observations: []))
        let viewModel = ScanViewModel(cameraService: FakeCameraService(), ocrService: ocrService)
        await viewModel.capturePhoto()
        #expect(viewModel.scanState == .failed)

        viewModel.retake()

        #expect(viewModel.scanState == .idle)
    }

    @Test func secondCaptureRequestWhileBusyIsIgnored() async {
        let cameraService = FakeCameraService()
        cameraService.capturePhotoDelayNanoseconds = 50_000_000
        let ocrService = FakeOCRService()
        ocrService.recognizeTextResult = .success(OCRResult(observations: []))
        let viewModel = ScanViewModel(cameraService: cameraService, ocrService: ocrService)

        async let first: Void = viewModel.capturePhoto()
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(viewModel.isBusy == true)
        await viewModel.capturePhoto()
        await first

        #expect(cameraService.capturePhotoCallCount == 1)
    }

    @Test func isBusyReflectsCapturingAndRecognizingStatesOnly() {
        let viewModel = ScanViewModel(cameraService: FakeCameraService(), ocrService: FakeOCRService())

        #expect(viewModel.isBusy == false)
    }
}

@MainActor
private final class FakeCameraService: CameraService {
    var authorizationStatusToReturn: CameraAuthorizationStatus = .notDetermined
    var requestAuthorizationResult: CameraAuthorizationStatus = .authorized
    var requestAuthorizationCallCount = 0
    var startSessionCallCount = 0
    var stopSessionCallCount = 0
    var capturePhotoCallCount = 0
    var capturePhotoResult: Result<Data, Error> = .success(Data([0x01]))
    var capturePhotoDelayNanoseconds: UInt64 = 0

    func authorizationStatus() -> CameraAuthorizationStatus { authorizationStatusToReturn }

    func requestAuthorization() async -> CameraAuthorizationStatus {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }

    func startSession() async throws {
        startSessionCallCount += 1
    }

    func stopSession() {
        stopSessionCallCount += 1
    }

    func capturePhoto() async throws -> Data {
        capturePhotoCallCount += 1
        if capturePhotoDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: capturePhotoDelayNanoseconds)
        }
        switch capturePhotoResult {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    func makePreviewView() -> AnyView { AnyView(EmptyView()) }
}

private final class FakeOCRService: OCRService, @unchecked Sendable {
    var recognizeTextResult: Result<OCRResult, Error> = .success(OCRResult(observations: []))
    private(set) var recognizeTextCallCount = 0

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        recognizeTextCallCount += 1
        switch recognizeTextResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
