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

## 現在の内容（Issue #15）

- `MenuUnderstandingService.swift`: OCRで得たメニュー全体を料理項目ごとの構造化データへ変換するProtocol。利用可否（`availability()`）とメニュー全体の解析（`analyze(_:)`）をdomain typeだけで表し、`FoundationModels`をimportしない。
- `FoundationModelsMenuParser.swift`: `MenuUnderstandingService`のApple Foundation Models実装。`FoundationModels`をimportするのはこのファイルのみ。`SystemLanguageModel.availability`・`supportsLocale(_:)`（`ja-JP`固定）をtyped domain値へ変換し、private `@Generable` DTO（`MenuAnalysisDTO`等。各配列に`.maximumCount`の有限上限あり）を`respond(..., generating:)`で取得してTASK-024のdomain modelへmapする。`contextSize`（4,096 token）をsource of truthとしたsource境界chunking（`analyzeRange`。iOS 26.4+では`tokenCount(for:)`によるtoken preflightで無駄な呼び出しを避け、それ以前のOSや`exceededContextWindowSize`検出時は境界overlap＋決定論的ownership規則で再帰的に分割・再試行する）、10秒のtyped timeout（`TimeoutRaceGate`。unstructuredな`Task`とactorで、timeout確定後に遅れて届く応答を破棄する）、decode後のsource ID・fragment・`explicitIngredients`検証（`decodeAndValidate`）を実装する。Foundation Models呼び出しは`FoundationModelsRequestRunning`、利用可否取得は`SystemLanguageModelAvailabilityProviding`、context計測は`MenuUnderstandingContextMeasuring`、timeout計測は`MenuUnderstandingClock`という狭いProtocolの背後にあり、実モデルなしのfakeへ差し替えてchunking・timeout・検証ロジックを決定的にテストできる。
- `MenuUnderstandingPrompt.swift`: Menu Understanding用のsystem instructions（`instructions()`）とuser prompt（`prompt(for:)`）を構築する。料理項目分割・6フィールドの意味・明示食材と典型/隠れ食材の区別・複合語の分解と未解決残余の`unknownTerms`保持・入力を指示として扱わないこと・アレルゲン/安全判定の出力禁止を明記する。`FoundationModels`へは依存しないプレーンな`String`ビルダーで、`FoundationModelsMenuParser`から独立してレビュー・テストできる。

`MenuUnderstandingService`とその戻り値はFoundation Models固有型へ依存しないため、Foundation Modelsなしのfake実装へ差し替えて決定的にテストできる。詳細は `docs/technology-selection.md`「6. Local LLM」、`task/TASK-024-menu-understanding-contract-models.md`、`task/TASK-025-foundation-models-parser.md`、`task/TASK-026-menu-understanding-prompt-extraction.md`を参照。
