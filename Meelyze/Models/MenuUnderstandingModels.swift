import Foundation

/// Menu Understandingへ渡す1件の入力sourceを表す。OCRが検出した1テキスト領域（Issue #14の
/// `RecognizedTextObservation`）に対応し、`id`を介して元のBounding Boxへ戻れるようにする。
///
/// `rawText`はPrompt用の整形・正規化前の生のOCR文字列であり、`analysisText`（Issue #16が
/// 前処理後に設定するoptionalな解析用文字列）を設定してもLLMや後段が上書きしない。
struct MenuUnderstandingSourceSegment: Equatable, Sendable {
    /// requestが有効な間、request内で一意かつ安定したopaque ID。Foundation Modelsに生成させない。
    let id: MenuUnderstandingSourceID

    /// 前処理前のOCR原文断片。`originalText`の唯一の情報源であり、書き換えない。
    let rawText: String

    /// OCR認識の信頼度（0.0〜1.0）。
    let confidence: Float

    /// 画像上の正規化座標（`RecognizedTextObservation.boundingBox`と同じ座標系）。
    let boundingBox: CGRect

    /// Issue #16が価格・記号除去等の前処理後に設定できる解析用文字列。意味解析に使えるが、
    /// `rawText`や`originalText`の代替・上書きには使用しない。
    var analysisText: String?

    init(
        id: MenuUnderstandingSourceID,
        rawText: String,
        confidence: Float,
        boundingBox: CGRect,
        analysisText: String? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.analysisText = analysisText
    }
}

/// `MenuUnderstandingSourceSegment.id`のopaqueなwrapper。生の`String`と混同しないための型。
struct MenuUnderstandingSourceID: Hashable, Equatable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var isEmpty: Bool { rawValue.isEmpty }
    var description: String { rawValue }
}

/// メニュー全体の入力。呼び出し側が渡したOCR observation順を維持したsource segment配列を保持する。
///
/// `VisionOCRService`（Issue #14）は幾何学的なreading-order sortを保証しないため、`segments`の
/// 順序は「読み取り順」として再解釈・並べ替えしない。呼び出し側が渡した順序をそのまま保持する。
struct MenuUnderstandingRequest: Equatable, Sendable {
    /// 入力順を維持したsource segment配列。
    var segments: [MenuUnderstandingSourceSegment]

    /// 複数sourceにまたがる項目の`originalText`を構成する際に使う、source間の決定論的な区切り。
    let sourceSeparator: String

    init(segments: [MenuUnderstandingSourceSegment], sourceSeparator: String = "\n") {
        self.segments = segments
        self.sourceSeparator = sourceSeparator
    }

    /// `segments`のsource IDが非空かつrequest内で一意であることを検証する。
    /// 違反があれば、Foundation Modelsを呼ぶ前に検出できるよう最初に見つかった違反を返す。
    func validateSourceIDs() -> MenuUnderstandingInvalidInputReason? {
        var seenIDs = Set<MenuUnderstandingSourceID>()
        for (index, segment) in segments.enumerated() {
            if segment.id.isEmpty {
                return .emptySourceID(index: index)
            }
            if !seenIDs.insert(segment.id).inserted {
                return .duplicateSourceID(segment.id)
            }
        }
        return nil
    }
}

/// request生成時に検出する入力不正の理由。
enum MenuUnderstandingInvalidInputReason: Equatable, Sendable {
    /// `index`番目のsegmentのsource IDが空だった。
    case emptySourceID(index: Int)
    /// `id`がrequest内で複数のsegmentに使われていた。
    case duplicateSourceID(MenuUnderstandingSourceID)
}

/// Apple Foundation Modelsの利用可否を、Framework固有型へ依存せず表す。
/// `SystemLanguageModel.availability`（TASK-025が変換する）に対応する。
enum MenuUnderstandingAvailability: Equatable, Sendable {
    /// 利用不可の理由。`SystemLanguageModel.Availability.UnavailableReason`に対応する3種類に加え、
    /// 非`@frozen`な同enumがSDK側で将来追加するcaseを保守的に受け止める`.unknown`を持つ
    /// （TASK-025が`@unknown default`で変換する）。
    enum UnavailableReason: Equatable, Sendable {
        /// 端末がFoundation Modelsの要件を満たさない。
        case deviceNotEligible
        /// Apple Intelligenceが有効化されていない。
        case appleIntelligenceNotEnabled
        /// モデルの準備がまだ完了していない。
        case modelNotReady
        /// SDKが将来追加した未知の利用不可理由。
        case unknown
    }

    case available
    case unavailable(UnavailableReason)
}

/// 解析失敗の影響範囲。境界を検証できたitemだけが`.item`を名乗れる。
/// 項目境界を取得できなかった生成・decode失敗は`.request`または`.sources`にとどめ、itemを捏造しない。
enum MenuUnderstandingFailureScope: Equatable, Sendable {
    /// request全体（入力不正、Foundation Models利用不可等）。
    case request
    /// 特定のsource集合（chunk単位の生成・decode失敗等）。
    case sources([MenuUnderstandingSourceID])
    /// 境界を検証できた特定の項目（decode後の項目単位バリデーション失敗等）。
    case item(MenuUnderstandingItemReference)
}

/// 失敗が再試行可能かどうか。SDK上で一時的と確認できる場合だけ`.retryable`とする
/// （TASK-025/027が実際の分類を行う）。
enum MenuUnderstandingRetryability: Equatable, Sendable {
    case retryable
    case notRetryable
}

/// Menu Understanding解析が失敗した理由。Foundation Models固有の型や生の`Error`を含まない。
/// TASK-027は、context超過・timeout・chunking異常を表す追加caseをこのenumへ追加する。
enum MenuUnderstandingFailureReason: Equatable, Sendable {
    /// request生成時に検出した入力不正（空・重複source ID）。
    case invalidInput(MenuUnderstandingInvalidInputReason)
    /// Apple Foundation Modelsが利用できない状態だった。
    case modelUnavailable(MenuUnderstandingAvailability.UnavailableReason)
    /// メニュー原文の対象locale（`ja-JP`）にモデルが対応していなかった。モデル自体は利用可能な
    /// 状態であり得るため`.modelUnavailable`とは区別する。
    case unsupportedLocale
    /// 生成処理中に発生した失敗。詳細な原因は`MenuUnderstandingGenerationFailureReason`で表す。
    case generationFailed(MenuUnderstandingGenerationFailureReason)
    /// Structured Outputが返したsource参照が、現在のchunk・requestと整合しなかった。
    /// 詳細な原因は`MenuUnderstandingSourceMappingFailureReason`で表す。
    case sourceMappingInvalid(MenuUnderstandingSourceMappingFailureReason)
    /// 境界を検証できたitemについて、decode後のフィールド単位バリデーションが失敗した。
    /// 詳細な原因は`MenuUnderstandingItemValidationReason`で表す。
    case itemValidationFailed(MenuUnderstandingItemValidationReason)
}

/// `LanguageModelSession.GenerationError`および予期しない`Error`をTASK-025が変換した、
/// 生成処理中の失敗理由。Foundation Models固有の型を含まない。
enum MenuUnderstandingGenerationFailureReason: Equatable, Sendable {
    /// モデルのcontext windowを超過した（`exceededContextWindowSize`）。TASK-027が
    /// source境界でのchunk分割・再試行を扱う。
    case contextWindowExceeded
    /// モデルのアセットが利用できなかった（`assetsUnavailable`）。
    case modelAssetsUnavailable
    /// 安全機構（guardrail）が生成を拒否した（`guardrailViolation`）。
    case guardrailViolation
    /// Structured Outputのguide指定がSDKでサポートされていなかった（`unsupportedGuide`）。
    case unsupportedGuide
    /// SDKが応答をStructured Outputへdecodeできなかった（`decodingFailure`、または
    /// Serviceが独自にDTO decodeを試みて失敗した場合）。
    case decodingFailed
    /// リクエスト頻度が制限を超えた（`rateLimited`）。
    case rateLimited
    /// 同一Sessionへの同時request制限に抵触した（`concurrentRequests`）。
    case concurrentRequestsNotAllowed
    /// モデルが応答を拒否した（`refusal`）。
    case refused
    /// Foundation Models呼び出しのwrapperが10秒でtyped timeoutを返した。SDKの生成処理自体が
    /// 停止したとは限らないため、遅れて届く応答は破棄し確定済み結果へ反映しない。
    case timedOut
    /// 呼び出し元のTaskがキャンセルされた。
    case cancelled
    /// 上記以外の、SDKが将来追加した未知case、または予期しない`Error`。
    case unknown
}

/// Structured Outputが返したsource参照を検証した結果、現在のchunk・requestと整合しなかった理由。
enum MenuUnderstandingSourceMappingFailureReason: Equatable, Sendable {
    /// requestに一度も存在しないsource IDを参照していた（捏造）。
    case unknownSourceID(MenuUnderstandingSourceID)
    /// requestには存在するが、現在のchunkの入力には含まれていないsource IDを参照していた。
    /// 別chunkの出力を文字列類似で結合せず、この項目は境界未解決として扱う。
    case chunkBoundaryUnresolved
    /// 参照元sourceのraw textに、宣言されたfragmentが（空でない完全一致部分として）含まれていなかった。
    case sourceFragmentMismatch(MenuUnderstandingSourceID)
}

/// 境界を検証できたitemについて、decode後のフィールド単位バリデーションが失敗した理由。
enum MenuUnderstandingItemValidationReason: Equatable, Sendable {
    /// `explicitIngredients`の一部が、参照元raw fragmentへ文字として明記されていなかった。
    /// 該当要素は結果から除外したうえで、この失敗をitem-scopedで併記する。
    case explicitIngredientsNotInSource([String])
}

/// 型付きの失敗。scope・reason・retryabilityを同時に保持し、後段（Issue #17/#19）が
/// アレルゲン三値へ直接変換しないための事実情報として扱う。
struct MenuUnderstandingFailure: Equatable, Sendable {
    let scope: MenuUnderstandingFailureScope
    let reason: MenuUnderstandingFailureReason
    let retryability: MenuUnderstandingRetryability
}

extension MenuUnderstandingFailure {
    /// request生成時に検出した入力不正をrequest-scopedな失敗として表す。
    /// 空・重複source IDは入力を修正しない限り再試行しても同じ結果になるため`.notRetryable`とする。
    static func invalidInput(_ reason: MenuUnderstandingInvalidInputReason) -> MenuUnderstandingFailure {
        MenuUnderstandingFailure(
            scope: .request,
            reason: .invalidInput(reason),
            retryability: .notRetryable
        )
    }
}

/// メニュー全体解析の結果。成功した`[ParsedMenuItem]`と型付きの失敗を同じ結果内で共存させ、
/// 1件の失敗で成功済み項目を捨てない。
///
/// `items`が空であることだけをもって「安全」「該当なし」または成功として扱わない
/// （`docs/technology-selection.md`§1・§9〜10）。`isTotalFailure` `isPartialSuccess`で
/// 全失敗・部分成功・全成功を区別する。
struct MenuUnderstandingResult: Equatable, Sendable {
    /// 解析に使った入力request（source segment・順序・区切り規則を含む）。
    let request: MenuUnderstandingRequest
    /// 解析に成功した項目。
    let items: [ParsedMenuItem]
    /// 解析実行時点のFoundation Models利用可否のsnapshot。
    let availability: MenuUnderstandingAvailability
    /// request/source/item単位の型付き失敗。
    let failures: [MenuUnderstandingFailure]

    init(
        request: MenuUnderstandingRequest,
        items: [ParsedMenuItem],
        availability: MenuUnderstandingAvailability,
        failures: [MenuUnderstandingFailure]
    ) {
        self.request = request
        self.items = items
        self.availability = availability
        self.failures = failures
    }

    /// 成功項目が1件もなく、失敗のみが存在する状態。
    var isTotalFailure: Bool { items.isEmpty && !failures.isEmpty }

    /// 成功項目と失敗の両方が存在する状態（1件以上の項目・sourceが失敗しても他は保持されている）。
    var isPartialSuccess: Bool { !items.isEmpty && !failures.isEmpty }
}
