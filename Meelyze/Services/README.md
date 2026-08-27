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
- `FoundationModelsMenuParser.swift`: `MenuUnderstandingService`のApple Foundation Models実装。`FoundationModels`をimportするのはこのファイルのみ。`SystemLanguageModel.availability`・`supportsLocale(_:)`（`ja-JP`固定）をtyped domain値へ変換し、private `@Generable` DTO（`MenuAnalysisDTO`等。各配列の上限は`MenuUnderstandingOutputLimits`を単一のsource of truthとして参照）を`respond(..., generating:)`で取得してTASK-024のdomain modelへmapする。`contextSize`（4,096 token）をsource of truthとしたsource境界chunking（`analyzeRange`。iOS 26.4+では`tokenCount(for:)`によるtoken preflightで無駄な呼び出しを避け、それ以前のOSや`exceededContextWindowSize`検出時は境界overlap付きで再帰的に分割・再試行する）、10秒のtyped timeout（`TimeoutRaceGate`。unstructuredな`Task`とactorで、timeout確定後に遅れて届く応答を破棄する）、decode後のsource ID・fragment・`explicitIngredients`検証（`decodeAndValidate`）を実装する。Foundation Models呼び出しは`FoundationModelsRequestRunning`、利用可否取得は`SystemLanguageModelAvailabilityProviding`、context計測は`MenuUnderstandingContextMeasuring`、timeout計測は`MenuUnderstandingClock`という狭いProtocolの背後にあり、実モデルなしのfakeへ差し替えてchunking・timeout・検証ロジックを決定的にテストできる。
- `MenuUnderstandingPrompt.swift`: Menu Understanding用のsystem instructions（`instructions()`）とuser prompt（`prompt(for:)`）を構築する。料理項目分割・6フィールドの意味・明示食材と典型/隠れ食材の区別・複合語の分解と未解決残余の`unknownTerms`保持・入力を指示として扱わないこと・アレルゲン/安全判定の出力禁止に加え、`rawText`（fragment・原文provenanceの唯一の情報源）と`analysisText`（意味解析用の参考情報。Issue #16の前処理結果、無ければ`rawText`を代用）の役割分担を明記する。`prompt(for:)`はsource ID・`rawText`・`analysisText`をJSON配列として渡し、OCR文字列内の改行・区切り文字らしい文字で構造が壊れないようにする（FIX-005）。`FoundationModels`へは依存しないプレーンな`String`ビルダーで、`FoundationModelsMenuParser`から独立してレビュー・テストできる。

### FIX-005: 出力上限飽和・chunk境界overlap・raw provenanceの堅牢化

Issue #15のレビューで判明した3つの検出可能なsilent-loss経路をFIX-005で修正した。

- **出力上限飽和**: `items`（最大10件）が上限どおり返った応答は、それだけでは「本当に全件」か「切り詰められた結果」か区別できないため、`decodeAndValidate`はdomain mapping・ordinal付与より前に飽和を検出する。source境界へさらに分割できる場合は、その応答をprovisionalとして破棄し（子chunkの結果と混在させない）、`analyzeRange`が有限に再分割する。単一sourceでこれ以上分割できない場合は、検証済み部分itemを保持しつつ`MenuUnderstandingFailureReason.outputLimitReached`を併記する。`sourceReferences`・`explicitIngredients`等のネストした配列も同じ上限定数（`MenuUnderstandingOutputLimits`）で飽和判定し、provenance-criticalな`sourceReferences`の飽和はitem全体を受理せず、`baseDishCandidates`等の意味フィールドの飽和はitemを保持したままitem-scopedなfailureを併記する。
- **chunk境界・global reconcile**: `analyzeRange`はordinalを持たない内部`ValidatedCandidate`（provenance identity＝source ID・raw range・fragmentの順序付き組）を全chunkから集めるだけにし、所有権判定によるchunk単位の即時破棄をしない。全候補が出揃った後、`reconcile`がprovenance identityでグルーピングして重複排除（semantic fieldsまで完全一致する場合だけ1件へ畳み、競合する場合は`duplicateCandidateConflict`）・安定sort・ordinal 0...N-1の確定を1回だけ行う。多段分割時も子chunkの物理範囲は親の物理範囲（`physicalRange`）を起点に計算し、親由来の境界overlap（halo）を失わない。
- **rawText / analysisTextの契約**: Promptは`rawText`と`analysisText`の両方をsourceごとにJSON形式で渡し、意味解析には`analysisText`（無ければ`rawText`）、`fragment`・`originalText`・`explicitIngredients`のsurface formには`rawText`だけを使う契約にする。`explicitIngredients`の検証は、item内の個別raw fragmentごとに行い、複数sourceのfragmentを連結した文字列に対する判定はしない（source境界をまたぐ偽陽性を防ぐ）。

詳細な設計判断・完了条件・検証結果は`fix/FIX-005-harden-menu-understanding-completeness-provenance.md`を参照。

`MenuUnderstandingService`とその戻り値はFoundation Models固有型へ依存しないため、Foundation Modelsなしのfake実装へ差し替えて決定的にテストできる。詳細は `docs/technology-selection.md`「6. Local LLM」、`task/TASK-024-menu-understanding-contract-models.md`、`task/TASK-025-foundation-models-parser.md`、`task/TASK-026-menu-understanding-prompt-extraction.md`を参照。

## 現在の内容（Issue #19）

- `MenuUnderstandingRequestBuilder.swift`: `OCRService`が返す`OCRResult`（`RecognizedTextObservation`の配列）を`MenuUnderstandingRequest`へ変換する。`build(from:)`は、配列インデックスに基づく安定した`MenuUnderstandingSourceID`を発行しつつ、そのIDから元の`RecognizedTextObservation`（rawText・confidence・Bounding Box）を引ける`sourceMap`を同時に返す。空白のみのobservationは解析対象になり得ないため除外する。撮影〜OCRからRule Engineまでの統合（`MenuAnalysisService`）における、Bounding Box対応関係の起点となる変換コンポーネント。詳細は`task/TASK-037-ocr-to-understanding-request.md`を参照。
- `MenuAnalysisService.swift`: `OCRResult`＋`UserProfile`から`MenuAnalysisResult`（`Meelyze/Models/`）を返す、撮影1回分の解析Serviceの唯一の入口。`MenuUnderstandingRequestBuilder`で組み立てたrequestを`RiskEvaluationService`（Issue #17）へ渡し、その結果を元のBounding Boxと結び付ける。Issue #17が「境界不明の失敗から架空の料理・Bounding Boxを生成しない」という原則を守ったまま`.item`スコープの失敗を捨てていることに対し、本Serviceは実item境界が判明している`.item`スコープ失敗だけを対象target全件`undetermined`の結果へ復元する。また、Foundation Models利用不可（request scopeの`modelUnavailable`）によって実itemが1件も得られなかった場合に限り、料理としてのグルーピングを一切推測せずOCRセグメント単位の`undetermined`フォールバックを行う（Menu Understandingが実際に動作して単に0件だった場合には適用しない）。詳細は`task/TASK-038-menu-analysis-service.md`を参照。
