# Repositories

DishやIngredientなど、永続化されたデータへのアクセスを担う層。SwiftDataなど具体的なデータソースはProtocolの背後に隠し、ViewModel/Service層からProtocol経由で利用する。

## 現在の内容（Issue #11）

- `ProfileRepository.swift`: `UserProfile`の保存・復元を表すProtocol。ViewModelはこのProtocol経由でのみ永続化にアクセスし、SwiftDataを直接importしない。
- `SwiftDataProfileRepository.swift`: `ModelContainer` / `ModelContext`経由で`UserProfile`を1件のみ保持・upsertする実装。

DishやIngredientなど判定ロジック用のRepositoryは別Issueで追加する。詳細は `docs/technology-selection.md`「4. アプリケーションアーキテクチャ」「8. Local Database」を参照。
