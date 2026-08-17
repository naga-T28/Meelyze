# Models

Dish、Ingredient、Allergenなど、アプリのドメインを表す型を配置する。SwiftDataのスキーマ定義もこの配下に追加していく。

## 現在の内容（Issue #11）

- `UserProfile.swift`: 初回設定（免責同意・表示言語・アレルゲン・食事制限・初期設定完了フラグ）を表す`@Model`。複数プロファイルはMVP非対応（FR-5.4）のため常に単一レコードを前提とする。
- `AllergenItem.swift`: 特定原材料8品目・特定原材料に準ずるもの20品目（計28品目）のenumカタログ。日本語表示名とMVP対象4言語（英語・繁体字中国語・簡体字中国語・韓国語）の表示名を持つ。
- `DietaryRestrictionCategory.swift`: MVP対象の食事制限区分（ハラール／ベジタリアン／ヴィーガン／ノンアルコール）のenumカタログ。`AllergenItem`と同様に多言語表示名を持つ。
- `DisplayLanguage.swift`: MVP対象表示言語（英語・繁体字中国語・簡体字中国語・韓国語）。メニュー原文の言語である日本語は含まない。

`AllergenItem` `DietaryRestrictionCategory`は、Dish/Ingredient側の判定ロジック（Rule Engine、#17）が未着手のため、SwiftDataエンティティ化せずenumカタログとして実装している。関連付け対象が具体化した時点でSwiftData化を再検討する（`task/README-issue11.md`「前提となる設計判断」参照）。

Dish、Ingredientなど判定ロジック用のモデルは別Issueで追加する。詳細は `docs/technology-selection.md`「8. Local Database」を参照。
