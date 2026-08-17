# Services

ViewModelから呼び出すユースケース層。OCR、LLMによるメニュー解析、判定処理など、Apple FrameworkやRepositoryを利用する処理はProtocolとして定義し、具象実装（例: `VisionOCRService`、`FoundationModelsMenuParser`）をこの配下に追加していく。

ViewModelはProtocol経由でのみServiceに依存し、Vision・Foundation Models・SwiftDataなどの具象実装や外部Frameworkを直接importしない。

## 現在の内容（Issue #14）

- `CameraService.swift`: カメラの権限確認・撮影・プレビュー表示を表すProtocol。プレビューも`AnyView`で返すことで、ViewModel/ViewがAVFoundationの型を直接扱わずに済む設計にしている。
- `OCRService.swift`: 画像データを受け取り`OCRResult`（またはエラー）を返すProtocol。日本語優先の認識言語ヒント固定を前提とする。
- 具象実装（`AVFoundationCameraService` `VisionOCRService`）はTASK-020・TASK-021で追加する。

詳細は `docs/technology-selection.md`「4. アプリケーションアーキテクチャ」「5. OCR」を参照。
