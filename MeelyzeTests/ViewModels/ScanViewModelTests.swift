import Testing
import Foundation
import SwiftUI
@testable import Meelyze

@MainActor
struct ScanViewModelTests {

    @Test func alreadyAuthorizedStartsSessionWithoutRequestingAgain() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .authorized
        let viewModel = ScanViewModel(cameraService: cameraService)

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .authorized)
        #expect(cameraService.startSessionCallCount == 1)
        #expect(viewModel.isShowingPermissionDeniedAlert == false)
    }

    @Test func notDeterminedAndGrantedStartsSession() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .notDetermined
        cameraService.requestAuthorizationResult = .authorized
        let viewModel = ScanViewModel(cameraService: cameraService)

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .authorized)
        #expect(cameraService.startSessionCallCount == 1)
    }

    @Test func notDeterminedAndDeniedShowsPermissionDeniedAlertWithoutStartingSession() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .notDetermined
        cameraService.requestAuthorizationResult = .denied
        let viewModel = ScanViewModel(cameraService: cameraService)

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .denied)
        #expect(viewModel.isShowingPermissionDeniedAlert == true)
        #expect(cameraService.startSessionCallCount == 0)
    }

    @Test func alreadyDeniedShowsPermissionDeniedAlertWithoutRequestingAgain() async {
        let cameraService = FakeCameraService()
        cameraService.authorizationStatusToReturn = .denied
        let viewModel = ScanViewModel(cameraService: cameraService)

        await viewModel.onAppear()

        #expect(viewModel.permissionState == .denied)
        #expect(viewModel.isShowingPermissionDeniedAlert == true)
        #expect(cameraService.requestAuthorizationCallCount == 0)
    }

    @Test func capturePhotoStoresDataInMemoryOnly() async {
        let cameraService = FakeCameraService()
        cameraService.capturePhotoResult = .success(Data([0xAA, 0xBB]))
        let viewModel = ScanViewModel(cameraService: cameraService)

        await viewModel.capturePhoto()

        #expect(viewModel.capturedImageData == Data([0xAA, 0xBB]))
    }

    @Test func failedCapturedLeavesNoImageData() async {
        let cameraService = FakeCameraService()
        cameraService.capturePhotoResult = .failure(CameraServiceError.captureFailed)
        let viewModel = ScanViewModel(cameraService: cameraService)

        await viewModel.capturePhoto()

        #expect(viewModel.capturedImageData == nil)
    }

    @Test func disappearStopsSession() {
        let cameraService = FakeCameraService()
        let viewModel = ScanViewModel(cameraService: cameraService)

        viewModel.onDisappear()

        #expect(cameraService.stopSessionCallCount == 1)
    }
}

@MainActor
private final class FakeCameraService: CameraService {
    var authorizationStatusToReturn: CameraAuthorizationStatus = .notDetermined
    var requestAuthorizationResult: CameraAuthorizationStatus = .authorized
    var requestAuthorizationCallCount = 0
    var startSessionCallCount = 0
    var stopSessionCallCount = 0
    var capturePhotoResult: Result<Data, Error> = .success(Data([0x01]))

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
        switch capturePhotoResult {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    func makePreviewView() -> AnyView { AnyView(EmptyView()) }
}
