import SwiftUI

/// カメラの権限確認・撮影・プレビュー表示を担うProtocol。ViewModelとViewはこのProtocol経由でのみ
/// カメラにアクセスし、AVFoundationを直接importしない（`docs/technology-selection.md`§4）。
///
/// プレビュー表示自体もAVFoundationの型（`AVCaptureVideoPreviewLayer`等）を外部へ露出させず、
/// `AnyView`として提供する。Viewはそれをそのまま埋め込むだけでよく、プレビューの具体的な実装
/// （`AVFoundationCameraService`側、TASK-020）を意識しない。
@MainActor
protocol CameraService: AnyObject {
    /// 現在のカメラ権限状態を確認する（要求は行わない）。
    func authorizationStatus() -> CameraAuthorizationStatus

    /// カメラ権限を要求する。既に確定済みの場合は要求せず現在の状態を返す。
    func requestAuthorization() async -> CameraAuthorizationStatus

    /// カメラSessionを開始する。
    func startSession() async throws

    /// カメラSessionを停止する。
    func stopSession()

    /// 現在のプレビューを撮影し、画像データをメモリ上で返す。ディスク・SwiftDataへの保存は行わない
    /// （`docs/ui-design.md`「画像の非永続化」方針）。
    func capturePhoto() async throws -> Data

    /// カメラプレビュー表示を返す。
    func makePreviewView() -> AnyView
}

/// カメラ権限状態。`AVAuthorizationStatus`相当だが、ViewModel/ViewがAVFoundationを直接importせずに
/// 扱えるようProtocol層で定義する。
enum CameraAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}
