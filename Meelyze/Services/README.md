# Services

ViewModelから呼び出すユースケース層。OCR、LLMによるメニュー解析、判定処理など、Apple FrameworkやRepositoryを利用する処理はProtocolとして定義し、具象実装（例: `VisionOCRService`、`FoundationModelsMenuParser`）をこの配下に追加していく。

ViewModelはProtocol経由でのみServiceに依存し、Vision・Foundation Models・SwiftDataなどの具象実装や外部Frameworkを直接importしない。

## 現在の内容（Issue #14）

- `CameraService.swift`: カメラの権限確認・撮影・プレビュー表示を表すProtocol。プレビューも`AnyView`で返すことで、ViewModel/ViewがAVFoundationの型を直接扱わずに済む設計にしている。
- `OCRService.swift`: 画像データを受け取り`OCRResult`（またはエラー）を返すProtocol。日本語優先の認識言語ヒント固定を前提とする。
- `AVFoundationCameraService.swift`: `CameraService`の実機向け実装。`AVCaptureSession`で撮影・プレビューを扱う。
- `VisionOCRService.swift`: `OCRService`のApple Vision実装。`VNRecognizeTextRequest`で日本語優先のOCRを行う。
- `SimulatorCameraService.swift`: `CameraService`のSimulator専用実装（`#if targetEnvironment(simulator)`）。実カメラSessionを持たないSimulatorで、`Meelyze/DebugResources/SimulatorMenuPhotos/`に置いた画像を撮影結果代わりに使い、実際の`VisionOCRService`の挙動を手動確認できるようにする。
- `UITestScanStubs.swift`: UI Test専用の`CameraService` `OCRService`スタブ（`StubCameraService` `StubOCRService`）。`UITEST_OCR_STUB_MODE`環境変数でOCR結果を決定的に制御する。

詳細は `docs/technology-selection.md`「4. アプリケーションアーキテクチャ」「5. OCR」を参照。
