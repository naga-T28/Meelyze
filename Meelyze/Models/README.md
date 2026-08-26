# Models

Dish、Ingredient、Allergenなど、アプリのドメインを表す型を配置する。SwiftDataのスキーマ定義もこの配下に追加していく。

## 現在の内容（Issue #11）

- `UserProfile.swift`: 初回設定（免責同意・表示言語・アレルゲン・食事制限・初期設定完了フラグ）を表す`@Model`。複数プロファイルはMVP非対応（FR-5.4）のため常に単一レコードを前提とする。
- `AllergenItem.swift`: 特定原材料8品目・特定原材料に準ずるもの20品目（計28品目）のenumカタログ。日本語表示名とMVP対象4言語（英語・繁体字中国語・簡体字中国語・韓国語）の表示名を持つ。
- `DietaryRestrictionCategory.swift`: MVP対象の食事制限区分（ハラール／ベジタリアン／ヴィーガン／ノンアルコール）のenumカタログ。`AllergenItem`と同様に多言語表示名を持つ。
- `DisplayLanguage.swift`: MVP対象表示言語（英語・繁体字中国語・簡体字中国語・韓国語）。メニュー原文の言語である日本語は含まない。

`AllergenItem` `DietaryRestrictionCategory`は、Dish/Ingredient側の判定ロジック（Rule Engine、#17）が未着手のため、SwiftDataエンティティ化せずenumカタログとして実装している。関連付け対象が具体化した時点でSwiftData化を再検討する（`task/README-issue11.md`「前提となる設計判断」参照）。

Dish、Ingredientなど判定ロジック用のモデルは別Issueで追加する。詳細は `docs/technology-selection.md`「8. Local Database」を参照。

## 現在の内容（Issue #14）

- `RecognizedTextObservation.swift`: OCRが検出した1件のテキスト領域（認識文字列・Confidence・Bounding Box）を表す。
- `OCRResult.swift`: 1回の撮影・OCR実行結果全体（`[RecognizedTextObservation]`）を表す。空配列は「Visionが文字を1件も抽出できなかった」ことを表す。

## 現在の内容（Issue #15）

- `MenuUnderstandingModels.swift`: Menu Understandingへのメニュー全体入力（`MenuUnderstandingRequest`とsource segmentである`MenuUnderstandingSourceSegment`・`MenuUnderstandingSourceID`）、Foundation Models利用可否（`MenuUnderstandingAvailability`）、型付き失敗（`MenuUnderstandingFailureScope` `MenuUnderstandingFailureReason` `MenuUnderstandingRetryability` `MenuUnderstandingFailure`）、解析結果全体（`MenuUnderstandingResult`）を定義する。Foundation Modelsへ依存しない純粋なドメインモデル。
- `ParsedMenuItem.swift`: LLMが抽出した1料理項目の型安全な構造化結果（`ParsedMenuItem`）と、そのsource対応（`MenuUnderstandingSourceReference` `MenuUnderstandingItemReference`）を定義する。`MenuUnderstandingItemReference.originalText`は参照元sourceのraw fragmentから決定論的に構成し、直接指定するAPIは提供しない。

`MenuUnderstandingRequest.segments`は呼び出し側が渡したOCR observation順をそのまま保持し、読み取り順として並べ替えない。`explicitIngredients`は原文へ明示された食材のみを保持し、料理名から推測した典型・隠れ食材は含まない契約とする。詳細は `docs/technology-selection.md`「6. Local LLM」、`task/TASK-024-menu-understanding-contract-models.md`を参照。

## 現在の内容（Issue #17）

- `RiskEvaluationModels.swift`: 決定論的Risk Engineの契約モデル。三値`RiskDetermination`（`likelyContains` / `noRecordedMatch` / `undetermined`、Boolへ縮退させない）、判定対象`RiskTarget`（`AllergenItem` / `DietaryRestrictionCategory`をID/raw valueで保持）、Evidence種別`RiskEvidenceKind`（既存のSwiftDataモデル`EvidenceSource`とは別名にして衝突を避ける）、Evidence本体`RiskEvidence`（SwiftData model instanceを保持しない値型）、Rule Engine出力`RiskEvaluationResult`を定義する。あわせて、TASK-031が構築するFactの型（`RiskFact` `RiskFactResolution` `RiskFactDatabaseMatch`）と、TASK-032のRule Engineが受け取るLLM由来補助シグナルの型（`RiskLLMSignal` `RiskLLMSignalPolarity`）も、後続タスクが依存する共通契約としてここで確定する。

判定ロジック本体（Rule Engine）・DB Fact構築・Service結線は別タスクで追加する。詳細は `docs/technology-selection.md`「9. Risk Aggregation / Evidence」「10. 最終判定」、`task/README-issue17.md`「前提となる設計判断」を参照。

