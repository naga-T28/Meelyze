import Foundation

/// `ParsedMenuItem`が参照する1つのsourceについて、そのsourceのraw textに完全一致する
/// item fragmentを保持する。
struct MenuUnderstandingSourceReference: Equatable, Sendable {
    /// 参照元segmentのsource ID。
    let sourceID: MenuUnderstandingSourceID
    /// 参照元segmentの`rawText`に含まれる、この項目に対応する原文断片。
    let rawFragment: String
}

/// request内だけで安定する項目の識別情報。Foundation Modelsに永続IDを生成させず、
/// Structured Outputの検証後にServiceが付与する。
///
/// `originalText`は`sourceReferences`順の`rawFragment`を`separator`で結合した値として
/// イニシャライザ内で決定論的に構成し、直接指定するAPIは提供しない。要約・翻訳・補正された
/// 文字列や、入力にない文字列を`originalText`として保持することはできない。
struct MenuUnderstandingItemReference: Equatable, Sendable {
    /// request内で一意な、この項目のordinal（生成順）。
    let ordinal: Int
    /// この項目の根拠となる、入力順のsource reference配列。
    let sourceReferences: [MenuUnderstandingSourceReference]
    /// `sourceReferences`のrawFragmentから決定論的に構成した、前処理前OCR原文断片。
    let originalText: String

    init(ordinal: Int, sourceReferences: [MenuUnderstandingSourceReference], separator: String) {
        self.ordinal = ordinal
        self.sourceReferences = sourceReferences
        self.originalText = sourceReferences.map(\.rawFragment).joined(separator: separator)
    }
}

/// Foundation Models等のLLMがメニュー原文から抽出した、1料理項目の型安全な構造化結果。
/// Foundation Models固有の型へは依存しない純粋なドメインモデル。
///
/// 各フィールドは自然言語理解の結果のみを表し、アレルゲン・食事制限の最終判定、
/// 「含まれない」、安全を示す結論を含まない（`docs/technology-selection.md`§1・§9〜10）。
struct ParsedMenuItem: Equatable, Sendable {
    /// この項目の識別情報と、参照元sourceへの対応関係。
    let reference: MenuUnderstandingItemReference
    /// 入力から読み取れるベース料理名候補。
    let baseDishCandidates: [String]
    /// 原文に文字として明示されている食材のみ。料理名から推測した典型・隠れ食材は含まない。
    let explicitIngredients: [String]
    /// 原文に現れる調理方法。
    let preparationMethods: [String]
    /// 量・味・地域性・追加/除外等の修飾表現。
    let modifiers: [String]
    /// 意味を十分に解決できない語・未解決要素。
    let unknownTerms: [String]
}
