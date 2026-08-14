# Services

ViewModelから呼び出すユースケース層。OCR、LLMによるメニュー解析、判定処理など、Apple FrameworkやRepositoryを利用する処理はProtocolとして定義し、具象実装（例: `VisionOCRService`、`FoundationModelsMenuParser`）をこの配下に追加していく。

ViewModelはProtocol経由でのみServiceに依存し、Vision・Foundation Models・SwiftDataなどの具象実装や外部Frameworkを直接importしない。

現時点では初期画面のみのため、具体的なServiceはまだ存在しない。詳細は `docs/technology-selection.md`「4. アプリケーションアーキテクチャ」を参照。
