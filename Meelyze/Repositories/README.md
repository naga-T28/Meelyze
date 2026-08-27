# Repositories

DishやIngredientなど、永続化されたデータへのアクセスを担う層。SwiftDataなど具体的なデータソースはProtocolの背後に隠し、ViewModel/Service層からProtocol経由で利用する。

## 現在の内容（Issue #11）

- `ProfileRepository.swift`: `UserProfile`の保存・復元を表すProtocol。ViewModelはこのProtocol経由でのみ永続化にアクセスし、SwiftDataを直接importしない。
- `SwiftDataProfileRepository.swift`: `ModelContainer` / `ModelContext`経由で`UserProfile`を1件のみ保持・upsertする実装。

DishやIngredientなど判定ロジック用のRepositoryは別Issueで追加する。詳細は `docs/technology-selection.md`「4. アプリケーションアーキテクチャ」「8. Local Database」を参照。

## 現在の内容（Issue #19）

- `MenuKnowledgeRepository.swift` / `SwiftDataMenuKnowledgeRepository.swift`（Issue #12で追加済み）を、`RootView`の`menuKnowledgeRepository`計算プロパティ（`profileRepository`と同様のパターン）から実際に構築するようにした。
- `RootView`は起動時（`.task`内、`determineInitialDestination()`より前）に`InitialDataImportService(repository: menuKnowledgeRepository).importBundledInitialDataIfNeeded()`を呼び出し、同梱JSON（`Meelyze/Resources/InitialMenuKnowledgeData.json`）をSwiftDataへ投入する。これにより、`MenuAnalysisService`（Issue #19）が実データに対してDB照合できるようになる。
- Import失敗時もアプリ起動を止めない（`try?`で握り潰し、DB照合0件のまま安全側「判定不可」へ縮退させる）。`dataVersion`ガードにより2回目以降の起動では再投入しない。
