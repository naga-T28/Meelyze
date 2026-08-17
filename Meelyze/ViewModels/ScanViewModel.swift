import Foundation
import SwiftUI

/// S06（メニュー撮影）の状態を保持する。カメラ権限確認・Session開始・撮影を扱う。
///
/// OCR実行への結線・E01（OCR失敗）フォールバックはTASK-022でこのViewModelを拡張して追加する
/// （`task/README-issue14.md`「前提となる設計判断」）。`CameraService`が`@MainActor`のため、
/// 本ViewModelも`@MainActor`とし、SwiftUIのView更新と同一の実行コンテキストで状態を扱う。
@MainActor
@Observable
final class ScanViewModel {
    /// カメラ権限の表示状態。
    enum PermissionState: Equatable {
        case unknown
        case authorized
        case denied
    }

    private(set) var permissionState: PermissionState = .unknown
    private(set) var capturedImageData: Data?
    var isShowingPermissionDeniedAlert = false

    private let cameraService: CameraService

    init(cameraService: CameraService) {
        self.cameraService = cameraService
    }

    /// カメラのライブプレビュー表示。AVFoundationの型を経由せず`AnyView`として提供する。
    var cameraPreviewView: AnyView { cameraService.makePreviewView() }

    /// S06表示時にカメラ権限を確認・要求し、許可済みならSessionを開始する。
    func onAppear() async {
        let current = cameraService.authorizationStatus()
        switch current {
        case .authorized:
            await handleAuthorized()
        case .notDetermined:
            let result = await cameraService.requestAuthorization()
            if result == .authorized {
                await handleAuthorized()
            } else {
                handleDenied()
            }
        case .denied, .restricted:
            handleDenied()
        }
    }

    /// S06から離れる際にSessionを停止する。
    func onDisappear() {
        cameraService.stopSession()
    }

    /// シャッター操作。撮影した画像データはメモリ上でのみ保持し、ディスク・SwiftDataへ保存しない
    /// （`docs/ui-design.md`「画像の非永続化」方針）。
    func capturePhoto() async {
        capturedImageData = try? await cameraService.capturePhoto()
    }

    private func handleAuthorized() async {
        permissionState = .authorized
        try? await cameraService.startSession()
    }

    private func handleDenied() {
        permissionState = .denied
        isShowingPermissionDeniedAlert = true
    }
}
