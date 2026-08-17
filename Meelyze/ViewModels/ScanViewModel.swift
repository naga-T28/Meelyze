import Foundation
import SwiftUI

/// S06（メニュー撮影）の状態を保持し、撮影→OCR実行→成功時の結果保持／失敗時のE01フォールバック表示を
/// 一連のフローとして扱う。
///
/// `CameraService`が`@MainActor`のため、本ViewModelも`@MainActor`とし、SwiftUIのView更新と同一の
/// 実行コンテキストで状態を扱う。
@MainActor
@Observable
final class ScanViewModel {
    /// カメラ権限の表示状態。
    enum PermissionState: Equatable {
        case unknown
        case authorized
        case denied
    }

    /// S06〜OCR実行に閉じた暫定のローカル状態。`docs/ui-design.md`が定める`idle / processing /
    /// completed / failed`という共有の状態概念は#19（オンライン/オフライン検知）の担当範囲と読めるが、
    /// #19着手前に#14がS06→OCR実行の最小フローを動かす必要があるため、本ViewModelに閉じた暫定状態と
    /// して定義する。#19着手時に共有の状態表現へ統合できるかを再検討する前提とする
    /// （`task/README-issue14.md`「前提となる設計判断」）。
    enum ScanState: Equatable {
        /// 撮影前。カメラプレビューとシャッターを表示する。
        case idle
        /// シャッター操作を受けて撮影中。
        case capturing
        /// 撮影完了、OCR実行中。
        case recognizing
        /// OCRが1件以上のテキスト領域を取得できた（低Confidenceを含む）。S08結果表示自体は別Issueの
        /// 範囲のため、本ViewModelは後続Issueが参照できる形で`OCRResult`を保持するところまでを担う。
        case recognized(OCRResult)
        /// OCRが0件、または撮影・OCR処理自体が失敗した。E01フォールバックUIを表示する。
        case failed
    }

    private(set) var permissionState: PermissionState = .unknown
    private(set) var scanState: ScanState = .idle
    var isShowingPermissionDeniedAlert = false

    private let cameraService: CameraService
    private let ocrService: OCRService

    init(cameraService: CameraService, ocrService: OCRService) {
        self.cameraService = cameraService
        self.ocrService = ocrService
    }

    /// カメラのライブプレビュー表示。AVFoundationの型を経由せず`AnyView`として提供する。
    var cameraPreviewView: AnyView { cameraService.makePreviewView() }

    /// 撮影・OCR実行中はシャッター操作を受け付けない。
    var isBusy: Bool {
        switch scanState {
        case .capturing, .recognizing:
            return true
        case .idle, .recognized, .failed:
            return false
        }
    }

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

    /// シャッター操作。撮影→OCR実行を行う。撮影画像・OCR結果はメモリ上でのみ保持し、ディスク・
    /// SwiftDataへ保存しない。失敗時も判定履歴として保存しない（`docs/ui-design.md`E01の定義）。
    func capturePhoto() async {
        guard !isBusy else { return }

        scanState = .capturing
        guard let imageData = try? await cameraService.capturePhoto() else {
            scanState = .failed
            return
        }

        scanState = .recognizing
        guard let result = try? await ocrService.recognizeText(in: imageData) else {
            scanState = .failed
            return
        }

        scanState = result.isEmpty ? .failed : .recognized(result)
    }

    /// E01の主操作「再撮影」。S06（撮影前）の状態へ戻す。プロファイルは保持し、カメラSessionは
    /// 維持したままにする。
    func retake() {
        scanState = .idle
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
