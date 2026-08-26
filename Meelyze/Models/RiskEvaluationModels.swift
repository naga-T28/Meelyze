import Foundation

/// アレルゲン・食事制限の最終判定を表す三値。Boolへの縮退経路は提供しない
/// （`docs/technology-selection.md`§1・§9〜10）。`noRecordedMatch`は安全の保証ではなく、
/// 未知・未解決要素が一切残っていない場合に限って使える。
enum RiskDetermination: Equatable, Sendable {
    /// 含有の可能性が高い。
    case likelyContains
    /// 収録データ上は該当なし。
    case noRecordedMatch
    /// 判定不可 / 要確認。
    case undetermined
}

/// 判定対象。表示名や翻訳文字列ではなく、DB照合に使うID/raw valueで保持する。
/// `UserProfile.allergenItems`は`AllergenItem.rawValue`・`Allergen.id`と、
/// `UserProfile.dietaryRestrictionCategories`は`Restriction.category`と照合する
/// （`task/README-issue17.md`「前提となる設計判断」）。
enum RiskTarget: Equatable, Hashable, Sendable {
    case allergen(AllergenItem)
    case dietaryRestriction(DietaryRestrictionCategory)
}

extension RiskTarget {
    private var japaneseName: String {
        switch self {
        case .allergen(let item): return item.japaneseName
        case .dietaryRestriction(let category): return category.japaneseName
        }
    }

    /// `RiskLLMSignalExtractor`のテキスト部分一致検索に使うキーワード群。「AAA（BBB）」形式の
    /// 複合表記（例:「落花生（ピーナッツ）」）は両方を独立したキーワードとして返す。該当しなければ
    /// 表示名そのものを1件返す。メニュー原文の言語（日本語）に対する部分一致専用であり、
    /// DB照合のキーとしては使わない（DB照合はraw value/IDで行う。上記doc参照）。
    var japaneseMatchKeywords: [String] {
        let name = japaneseName
        guard let open = name.firstIndex(of: "（"), let close = name.firstIndex(of: "）"), open < close else {
            return [name]
        }
        let before = String(name[name.startIndex..<open])
        let inside = String(name[name.index(after: open)..<close])
        return [before, inside].filter { !$0.isEmpty }
    }
}

/// Risk判定Evidenceの由来種別。既存のSwiftDataモデル`EvidenceSource`
/// （`Meelyze/Models/EvidenceSource.swift`、料理・食材DBの出典情報）と名前が衝突しないよう別名にしている。
enum RiskEvidenceKind: Equatable, Sendable {
    /// メニュー文字列に直接記載されていた情報。
    case explicit
    /// Alias Dictionaryによって正規化された情報。
    case normalized
    /// 既知料理のDBから得られた情報。
    case dishDatabase
    /// LLMによる意味的推論。Positiveな推論のみ警告方向に利用できる。
    case llmInference
    /// 未知語、曖昧な候補など、解決できなかった情報。
    case unknown
}

/// `llmInference` `unknown` Evidenceの由来詳細。DBの正規データとして確定していない理由を明示し、
/// Negativeシグナルを`RiskEvidence`へ昇格させない・未解決要素を安全側判定へ反映させるための
/// 追跡情報として使う（`task/README-issue17.md`「LLM Positiveの扱い」「複数解釈」）。
enum RiskInferredOrigin: Equatable, Sendable {
    /// LLMの意味的推論によるPositiveシグナル（DBと未照合）。Negativeな推論はEvidenceへ昇格しない。
    case llmPositiveInference
    /// Alias解決できなかった未知語・未解決要素。
    case unresolvedTerm
    /// 複数のDB候補へ解決し、一意に確定できなかった。
    case ambiguousCandidates([MenuAliasResolvedEntity])
    /// Alias解決は一意に確定したが、より深いDish/Ingredient関連の取得にRepositoryエラー等で失敗した。
    /// `unresolvedTerm`と異なり、解決先のCanonical Entity自体は判明している（`RiskEvidence.resolvedEntity`参照）。
    case databaseFetchFailed
    /// item scopeのMenu Understanding失敗（バリデーション失敗・出力上限到達等）と併存する項目の
    /// `noRecordedMatch`を安全側で`undetermined`へ倒したことを表す。
    case itemUnderstandingIncomplete([MenuUnderstandingFailureReason])
}

/// アレルゲン・食事制限判定を裏付ける1件の根拠。SwiftDataのmodel instanceを保持しない値型で、
/// UI・テスト・監査へ安全に渡せる（`docs/technology-selection.md`§9）。
struct RiskEvidence: Equatable, Sendable {
    /// この根拠の由来種別。
    let kind: RiskEvidenceKind
    /// 根拠となったOCR source（sourceID・前処理前rawText・Confidence・Bounding Box）。
    /// 複数sourceにまたがる項目由来の場合は複数件持つ。
    let sourceEvidence: [MenuTextPreprocessingEvidence]
    /// DB照合前後の正規化情報（Issue #16の`MenuNameNormalizationEvidence`）。
    let normalization: MenuNameNormalizationEvidence?
    /// 解決先のCanonical Entityの種別（料理 or 食材）。
    let resolvedEntityType: MenuAliasEntityType?
    /// 解決先のCanonical Entity（IDとcanonical名のスナップショット）。
    let resolvedEntity: MenuAliasResolvedEntity?
    /// このEvidenceの根拠となったDB側の出典ID（`EvidenceSource.id`相当の文字列参照）。
    /// SwiftDataの`EvidenceSource` model instanceそのものは保持しない。
    let databaseSourceIDs: [String]
    /// 隠れ食材由来かどうか。
    let isHiddenIngredient: Bool
    /// 隠れ食材である場合のカテゴリ。
    let hiddenIngredientCategory: HiddenIngredientCategory?
    /// `llmInference` `unknown`の場合の由来詳細。
    let inferredOrigin: RiskInferredOrigin?

    init(
        kind: RiskEvidenceKind,
        sourceEvidence: [MenuTextPreprocessingEvidence] = [],
        normalization: MenuNameNormalizationEvidence? = nil,
        resolvedEntityType: MenuAliasEntityType? = nil,
        resolvedEntity: MenuAliasResolvedEntity? = nil,
        databaseSourceIDs: [String] = [],
        isHiddenIngredient: Bool = false,
        hiddenIngredientCategory: HiddenIngredientCategory? = nil,
        inferredOrigin: RiskInferredOrigin? = nil
    ) {
        self.kind = kind
        self.sourceEvidence = sourceEvidence
        self.normalization = normalization
        self.resolvedEntityType = resolvedEntityType
        self.resolvedEntity = resolvedEntity
        self.databaseSourceIDs = databaseSourceIDs
        self.isHiddenIngredient = isHiddenIngredient
        self.hiddenIngredientCategory = hiddenIngredientCategory
        self.inferredOrigin = inferredOrigin
    }
}

/// 1つの`RiskTarget`についての最終判定とEvidence。Rule Engine（TASK-032）の出力単位。
struct RiskEvaluationResult: Equatable, Sendable {
    let target: RiskTarget
    let determination: RiskDetermination
    let evidence: [RiskEvidence]
}

// MARK: - Fact（TASK-031が`MenuKnowledgeRepository`・`UserProfile`から構築する入力）

/// `RiskFact`が対象targetについてDBを確認できたかどうか。Issue #16の`MenuAliasResolutionStatus`
/// （resolved/unresolved/ambiguous）に、Fact構築時特有の「DB取得失敗」を加えた4値。
enum RiskFactResolution: Equatable, Sendable {
    /// 候補が一意にDBのCanonical Entityへ解決され、関連DB情報を確認できた。
    case resolved
    /// Alias解決できなかった未知語・未解決要素。
    case unresolved
    /// 複数候補へ解決し、一意に確定できなかった。
    case ambiguous
    /// 候補は解決できたが、関連DB情報の取得に失敗した（例: Repositoryのエラー）。
    case databaseUnavailable
}

/// 一意に解決された料理・食材が、対象targetを持つ1つの`Ingredient`に関連していたことを表す。
struct RiskFactDatabaseMatch: Equatable, Sendable {
    let ingredientID: String
    /// `DishIngredient.confidence`。`variesByStore`は確定的な一致と区別して扱う
    /// （`task/README-issue17.md`「該当なしの必要条件」）。
    let confidence: DishIngredientConfidence
    let isHiddenIngredient: Bool
    let hiddenIngredientCategory: HiddenIngredientCategory?
    /// この一致の根拠となったDB側の出典ID（`DishIngredient.sourceIds`・`IngredientAllergen.sourceIds`・
    /// `IngredientRestriction.sourceIds`相当）。`RiskEvidence.databaseSourceIDs`へそのまま渡せる。
    let sourceIDs: [String]
}

/// TASK-031が、1つの候補（料理名候補または明示食材）と1つの`RiskTarget`について構築する、
/// DB由来の決定論的な事実。三値判定そのものではなく、Rule Engine（TASK-032）の入力になる。
///
/// `resolution != .resolved`の場合、`databaseMatches`は常に空とし、確定的な「含まれる」
/// 「含まれない」を意味させない。同一のDB内容・同一の入力からは常に同じFactが返る。
struct RiskFact: Equatable, Sendable {
    let target: RiskTarget
    let resolution: RiskFactResolution
    let databaseMatches: [RiskFactDatabaseMatch]
    let evidence: [RiskEvidence]
}

// MARK: - LLM Signal（TASK-032のRule Engineが受け取る、DB未照合の補助入力）

/// LLM由来シグナルの極性。Negativeは安全側の判定根拠としてRule Engineへ渡さない
/// （`docs/technology-selection.md`§1・§9〜10）。
enum RiskLLMSignalPolarity: Equatable, Sendable {
    case positive
    case negative
}

/// `ParsedMenuItem`から得られる、DBの照合をまだ経ていないLLM由来の補助シグナル。Positiveのみ、
/// 結果を安全側へ単調に移動させる補助Evidenceとして使う（`task/README-issue17.md`「LLM Positiveの扱い」）。
struct RiskLLMSignal: Equatable, Sendable {
    let target: RiskTarget
    let polarity: RiskLLMSignalPolarity
    let sourceText: String
    let sourceEvidence: [MenuTextPreprocessingEvidence]
}

extension UserProfile {
    /// 選択済みのアレルゲン・食事制限を、重複を除いた選択順の`RiskTarget`として返す。
    /// `RiskFactBuilder`（TASK-031）・`RiskEvaluationService`（TASK-033）が同じ導出ロジックを
    /// 共有するための単一のsource of truth。
    var selectedRiskTargets: [RiskTarget] {
        let allTargets = allergenItems.map(RiskTarget.allergen) + dietaryRestrictionCategories.map(RiskTarget.dietaryRestriction)
        var seen = Set<RiskTarget>()
        return allTargets.filter { seen.insert($0).inserted }
    }
}

// MARK: - Service出力（TASK-033の`RiskEvaluationService`がメニュー全体について返す結果）

/// Risk評価が失敗した理由。Menu Understanding由来の失敗はそのまま透過し、Alias解決等の
/// Risk評価固有の失敗は別caseで表す（Foundation Models固有の失敗理由と混同しない）。
enum RiskEvaluationFailureReason: Equatable, Sendable {
    /// Menu Understanding段階で発生した失敗をそのまま透過したもの。
    case menuUnderstanding(MenuUnderstandingFailureReason)
    /// Alias解決（DB照合）段階でのRepositoryエラー等、Risk評価固有の失敗。
    case aliasResolutionFailed
}

/// Risk評価の型付き失敗。`MenuUnderstandingFailure`と同じscope・retryability概念を再利用する。
struct RiskEvaluationFailure: Equatable, Sendable {
    let scope: MenuUnderstandingFailureScope
    let reason: RiskEvaluationFailureReason
    let retryability: MenuUnderstandingRetryability
}

/// 1つの`ParsedMenuItem`について、選択済みtargetごとのRisk評価結果。
struct MenuItemRiskEvaluation: Equatable, Sendable {
    let reference: MenuUnderstandingItemReference
    let results: [RiskEvaluationResult]

    /// 全targetの中で最も安全側（警戒レベルが高い）の判定。`likelyContains > undetermined >
    /// noRecordedMatch`の優先度で集約する。`results`が空（評価対象targetなし）の場合は`nil`。
    /// `nil`をBoolや特定の`RiskDetermination`へ暗黙に読み替えないこと。
    var overallDetermination: RiskDetermination? {
        if results.contains(where: { $0.determination == .likelyContains }) { return .likelyContains }
        if results.contains(where: { $0.determination == .undetermined }) { return .undetermined }
        if results.isEmpty { return nil }
        return .noRecordedMatch
    }
}

/// メニュー全体のRisk評価結果。`MenuUnderstandingResult`と同様、成功した項目のRisk評価と
/// 型付き失敗を同じ結果内で共存させる。項目境界を復元できない失敗から架空の項目を生成しない。
struct MenuRiskEvaluationResult: Equatable, Sendable {
    let items: [MenuItemRiskEvaluation]
    let failures: [RiskEvaluationFailure]
}
