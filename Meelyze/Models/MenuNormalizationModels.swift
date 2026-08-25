import Foundation

/// OCR原文からLLM意味解析用の補助文字列を作る際に適用した前処理。
enum MenuTextPreprocessingChange: Equatable, Sendable {
    case priceRemoved
    case whitespaceNormalized
}

/// 1つのOCR sourceに対する前処理結果。`rawText`と位置情報は必ず元segmentから保持する。
struct MenuTextPreprocessingEvidence: Equatable, Sendable {
    let sourceID: MenuUnderstandingSourceID
    let rawText: String
    let analysisText: String?
    let confidence: Float
    let boundingBox: CGRect
    let changes: [MenuTextPreprocessingChange]
}

/// 複数sourceの前処理結果。Issue #15へ渡すsegment配列と、S09へ渡せる根拠を同時に保持する。
struct MenuTextPreprocessingResult: Equatable, Sendable {
    let segments: [MenuUnderstandingSourceSegment]
    let evidence: [MenuTextPreprocessingEvidence]
}

/// DB照合前の候補文字列へ適用した正規化。
enum MenuNameNormalizationChange: Equatable, Sendable {
    case trimmed
    case widthAndCaseFolded
    case hiraganaConvertedToKatakana
    case separatorsRemoved
}

/// 料理名・食材名候補の正規化結果。
struct MenuNameNormalizationEvidence: Equatable, Sendable {
    let originalText: String
    let normalizedText: String
    let changes: [MenuNameNormalizationChange]
}

/// Alias解決対象の種類。
enum MenuAliasEntityType: Equatable, Sendable {
    case dish
    case ingredient
}

/// Alias解決結果の分類。最終的な安全判定ではなく、後段Rule Engineへ渡す事実情報。
enum MenuAliasResolutionStatus: Equatable, Sendable {
    case resolved
    case unresolved
    case ambiguous
}

/// DB上の解決先を値としてスナップショット化したもの。SwiftData model自体をEvidenceへ露出しない。
struct MenuAliasResolvedEntity: Equatable, Sendable {
    let id: String
    let canonicalName: String
}

/// 正規化済み候補をAlias Dictionary/DBへ照合した結果。
struct MenuAliasResolutionEvidence: Equatable, Sendable {
    let entityType: MenuAliasEntityType
    let inputText: String
    let normalization: MenuNameNormalizationEvidence
    let status: MenuAliasResolutionStatus
    let matches: [MenuAliasResolvedEntity]
}

/// `ParsedMenuItem` 1件に対してIssue #16が後段へ渡す、正規化・Alias解決までの根拠。
struct MenuItemNormalizationEvidence: Equatable, Sendable {
    let reference: MenuUnderstandingItemReference
    let sourceEvidence: [MenuTextPreprocessingEvidence]
    let baseDishCandidateResolutions: [MenuAliasResolutionEvidence]
    let explicitIngredientResolutions: [MenuAliasResolutionEvidence]
}
