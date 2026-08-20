import Foundation
import FoundationModels

/// `MenuUnderstandingService`のApple Foundation Models実装。実行時の利用可否判定、
/// 型安全なStructured Output取得、Foundation Models固有エラーからtyped domain failureへの
/// 変換、context上限に応じたsource境界chunking、10秒timeout、source/item単位の検証を
/// このファイル内へ閉じ込める。`FoundationModels`をimportするのはこのファイルのみとし、
/// `MenuUnderstandingService` Protocol・domain model・ViewModelへは一切露出させない。
///
/// Prompt本文は`MenuUnderstandingPrompt`（TASK-026）が抽出規則を確定させる。
struct FoundationModelsMenuParser: MenuUnderstandingService {
    /// メニュー原文の対象locale。端末の`Locale.current`やユーザーの表示言語设定に判定を委ねず、
    /// 常にこの値で`supportsLocale(_:)`を確認する。
    static let menuLocale = Locale(identifier: "ja-JP")

    /// chunk境界を分割する際、隣接chunkへ重複させる（overlapさせる）source segment数。
    /// 境界をまたぐ項目が少なくとも片方のchunkで完全に検証できる可能性を残しつつ、
    /// 分割のたびに厳密にサイズが縮小することを保証する値として1を採用する。
    private static let boundaryOverlapSegmentCount = 1

    private let runner: any FoundationModelsRequestRunning
    private let availabilityProvider: any SystemLanguageModelAvailabilityProviding
    private let contextMeasurer: any MenuUnderstandingContextMeasuring
    private let clock: any MenuUnderstandingClock
    private let maximumResponseTokens: Int
    private let timeoutDuration: Duration

    /// - Parameters:
    ///   - runner: Foundation Models呼び出しを行う狭いseam。テストでは実モデルなしのfakeへ差し替える。
    ///   - availabilityProvider: `SystemLanguageModel`の利用可否・locale対応を取得するseam。
    ///   - contextMeasurer: `contextSize`と、可能な環境でのtoken preflightを提供するseam。
    ///   - clock: timeout計測に使うseam。テストでは即時解決するfakeへ差し替える。
    ///   - maximumResponseTokens: `GenerationOptions.maximumResponseTokens`に渡す上限。既定値800は
    ///     DTOの配列上限（`items`最大10件、1件あたりの各field上限。後述）を根拠に、4,096 tokenの
    ///     context windowのうち出力側へ割り当てる分として選定した（TASK-026作業ログ参照）。
    ///   - timeoutDuration: 1回のFoundation Models呼び出しに許容する時間。既定10秒
    ///     （`docs/ui-design.md`のLoading方針）。
    init(
        runner: any FoundationModelsRequestRunning = LiveFoundationModelsRequestRunner(),
        availabilityProvider: any SystemLanguageModelAvailabilityProviding = LiveSystemLanguageModelAvailabilityProvider(),
        contextMeasurer: any MenuUnderstandingContextMeasuring = LiveMenuUnderstandingContextMeasurer(),
        clock: any MenuUnderstandingClock = LiveMenuUnderstandingClock(),
        maximumResponseTokens: Int = 800,
        timeoutDuration: Duration = .seconds(10)
    ) {
        self.runner = runner
        self.availabilityProvider = availabilityProvider
        self.contextMeasurer = contextMeasurer
        self.clock = clock
        self.maximumResponseTokens = maximumResponseTokens
        self.timeoutDuration = timeoutDuration
    }

    func availability() async -> MenuUnderstandingAvailability {
        Self.mapAvailability(availabilityProvider.currentAvailability())
    }

    func analyze(_ request: MenuUnderstandingRequest) async -> MenuUnderstandingResult {
        // availabilityは呼び出しごとに再評価し、長期間キャッシュしない。
        let availability = Self.mapAvailability(availabilityProvider.currentAvailability())

        if let invalidReason = request.validateSourceIDs() {
            // 空・重複source IDはFoundation Modelsを呼ばず、request-scopedな失敗として返す。
            return MenuUnderstandingResult(request: request, items: [], availability: availability, failures: [.invalidInput(invalidReason)])
        }

        if case .unavailable(let reason) = availability {
            return MenuUnderstandingResult(
                request: request,
                items: [],
                availability: availability,
                failures: [
                    MenuUnderstandingFailure(scope: .request, reason: .modelUnavailable(reason), retryability: Self.retryability(forUnavailableReason: reason)),
                ]
            )
        }

        guard availabilityProvider.supportsLocale(Self.menuLocale) else {
            // モデル自体は利用可能でも、対象localeに対応していない場合は`.modelUnavailable`とは
            // 区別し、解析失敗として扱う。
            return MenuUnderstandingResult(
                request: request,
                items: [],
                availability: availability,
                failures: [
                    MenuUnderstandingFailure(scope: .request, reason: .unsupportedLocale, retryability: .notRetryable),
                ]
            )
        }

        guard !request.segments.isEmpty else {
            return MenuUnderstandingResult(request: request, items: [], availability: availability, failures: [])
        }

        let fullRange = 0...(request.segments.count - 1)
        var nextOrdinal = 0
        let outcome = await analyzeRange(
            physicalRange: fullRange,
            coreRange: fullRange,
            allSegments: request.segments,
            sourceSeparator: request.sourceSeparator,
            nextOrdinal: &nextOrdinal
        )

        return MenuUnderstandingResult(request: request, items: outcome.items, availability: availability, failures: outcome.failures)
    }

    // MARK: - Chunking (source境界を保ったまま再帰的に分割・実行する)

    private struct RangeOutcome {
        var items: [ParsedMenuItem] = []
        var failures: [MenuUnderstandingFailure] = []
    }

    /// `coreRange`はこの呼び出しが最終的な項目所有権を持つsource index範囲、`physicalRange`は
    /// 実際にモデルへ渡すsource index範囲（`coreRange`に境界overlapを加えたもの）を表す。
    /// 呼び出しのたびに新しいSessionを使うFoundation Models呼び出しを1回試み、
    /// `exceededContextWindowSize`または事前のtoken preflightでcontext超過が見込まれる場合は
    /// `coreRange`をsource境界で2分割し、それぞれを再帰的に処理してmergeする。
    private func analyzeRange(
        physicalRange: ClosedRange<Int>,
        coreRange: ClosedRange<Int>,
        allSegments: [MenuUnderstandingSourceSegment],
        sourceSeparator: String,
        nextOrdinal: inout Int
    ) async -> RangeOutcome {
        let physicalSegments = Array(allSegments[physicalRange])
        let instructions = MenuUnderstandingPrompt.instructions()
        let promptRequest = MenuUnderstandingRequest(segments: physicalSegments, sourceSeparator: sourceSeparator)
        let prompt = MenuUnderstandingPrompt.prompt(for: promptRequest)
        let options = GenerationOptions(maximumResponseTokens: maximumResponseTokens)

        var needsSplit = false
        if let predictedTokens = await contextMeasurer.predictedTotalTokenCount(
            instructions: instructions,
            prompt: prompt,
            maximumResponseTokens: maximumResponseTokens
        ), predictedTokens > contextMeasurer.contextSize {
            // iOS 26.4+のtoken preflightがcontext超過を予測した場合、無駄な呼び出しをせず分割する。
            needsSplit = true
        }

        if !needsSplit {
            let raceOutcome = await respondWithTimeout(instructions: instructions, prompt: prompt, options: options)
            switch raceOutcome {
            case .content(let content):
                return decodeAndValidate(
                    content,
                    physicalRange: physicalRange,
                    coreRange: coreRange,
                    allSegments: allSegments,
                    sourceSeparator: sourceSeparator,
                    nextOrdinal: &nextOrdinal
                )
            case .timedOut:
                return RangeOutcome(failures: [
                    MenuUnderstandingFailure(
                        scope: .sources(sourceIDs(in: physicalRange, of: allSegments)),
                        reason: .generationFailed(.timedOut),
                        retryability: .retryable
                    ),
                ])
            case .failure(let error):
                if Self.isExceededContextWindowSize(error) {
                    needsSplit = true
                } else if error is CancellationError {
                    return RangeOutcome(failures: [
                        MenuUnderstandingFailure(
                            scope: .sources(sourceIDs(in: physicalRange, of: allSegments)),
                            reason: .generationFailed(.cancelled),
                            retryability: .notRetryable
                        ),
                    ])
                } else if let generationError = error as? LanguageModelSession.GenerationError {
                    let (reason, retryability) = Self.mapGenerationError(generationError)
                    return RangeOutcome(failures: [
                        MenuUnderstandingFailure(scope: .sources(sourceIDs(in: physicalRange, of: allSegments)), reason: reason, retryability: retryability),
                    ])
                } else {
                    return RangeOutcome(failures: [
                        MenuUnderstandingFailure(
                            scope: .sources(sourceIDs(in: physicalRange, of: allSegments)),
                            reason: .generationFailed(.unknown),
                            retryability: .notRetryable
                        ),
                    ])
                }
            }
        }

        guard coreRange.count > 1 else {
            // これ以上分割できない単一sourceがcontextへ収まらない。切り捨て・推測をせず
            // source-scopedな失敗として返す。
            let onlySourceID = allSegments[coreRange.lowerBound].id
            return RangeOutcome(failures: [
                MenuUnderstandingFailure(scope: .sources([onlySourceID]), reason: .generationFailed(.contextWindowExceeded), retryability: .notRetryable),
            ])
        }

        let mid = (coreRange.lowerBound + coreRange.upperBound) / 2
        let leftCore = coreRange.lowerBound...mid
        let rightCore = (mid + 1)...coreRange.upperBound
        let rightOverlap = min(Self.boundaryOverlapSegmentCount, rightCore.count - 1)
        let leftOverlap = min(Self.boundaryOverlapSegmentCount, leftCore.count - 1)
        let leftPhysical = coreRange.lowerBound...(mid + rightOverlap)
        let rightPhysical = (mid + 1 - leftOverlap)...coreRange.upperBound

        let leftOutcome = await analyzeRange(
            physicalRange: leftPhysical, coreRange: leftCore, allSegments: allSegments, sourceSeparator: sourceSeparator, nextOrdinal: &nextOrdinal
        )
        let rightOutcome = await analyzeRange(
            physicalRange: rightPhysical, coreRange: rightCore, allSegments: allSegments, sourceSeparator: sourceSeparator, nextOrdinal: &nextOrdinal
        )
        return RangeOutcome(items: leftOutcome.items + rightOutcome.items, failures: leftOutcome.failures + rightOutcome.failures)
    }

    private func sourceIDs(in range: ClosedRange<Int>, of segments: [MenuUnderstandingSourceSegment]) -> [MenuUnderstandingSourceID] {
        segments[range].map(\.id)
    }

    private static func isExceededContextWindowSize(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else { return false }
        if case .exceededContextWindowSize = generationError { return true }
        return false
    }

    // MARK: - Timeout isolation

    /// 呼び出しのwrapperが`timeoutDuration`でtyped timeoutを返すようにする。SDKの`respond`自体が
    /// cancelで直ちに終了するとは仮定せず、実際の呼び出しはunstructuredな`Task`として実行して
    /// 関数のawaitをブロックしないようにし、`TimeoutRaceGate`（actor）で最初に届いた結果だけを
    /// 採用する。timeoutが先に確定した後にrunnerが遅れて完了しても、`TimeoutRaceGate`が
    /// 二度目以降の報告を無視するため、確定済み結果を上書きしない。
    private func respondWithTimeout(instructions: String, prompt: String, options: GenerationOptions) async -> TimeoutRaceGate.Outcome {
        let gate = TimeoutRaceGate()
        let localRunner = runner

        Task {
            do {
                let content = try await localRunner.respond(instructions: instructions, prompt: prompt, options: options)
                await gate.reportSuccess(content)
            } catch {
                await gate.reportFailure(error)
            }
        }

        let localClock = clock
        let duration = timeoutDuration
        Task {
            try? await localClock.sleep(for: duration)
            await gate.reportTimeout()
        }

        return await gate.awaitOutcome()
    }

    // MARK: - Availability mapping

    private static func mapAvailability(_ availability: SystemLanguageModel.Availability) -> MenuUnderstandingAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(mapUnavailableReason(reason))
        }
    }

    private static func mapUnavailableReason(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> MenuUnderstandingAvailability.UnavailableReason {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        @unknown default:
            // SDKが将来追加する未知の利用不可理由を保守的に`.unknown`へ変換する。
            return .unknown
        }
    }

    /// モデル準備待ち（`.modelNotReady`）だけを再試行可能とする。端末非対応・Apple Intelligence
    /// 未設定・未知理由は、ユーザー操作なしに再試行しても解消しないため`.notRetryable`とする。
    private static func retryability(forUnavailableReason reason: MenuUnderstandingAvailability.UnavailableReason) -> MenuUnderstandingRetryability {
        reason == .modelNotReady ? .retryable : .notRetryable
    }

    // MARK: - GenerationError mapping

    private static func mapGenerationError(
        _ error: LanguageModelSession.GenerationError
    ) -> (MenuUnderstandingFailureReason, MenuUnderstandingRetryability) {
        switch error {
        case .exceededContextWindowSize:
            // 呼び出し側（analyzeRange）がsource境界での適応分割・再試行を扱うため、ここへ到達するのは
            // これ以上分割できない単一source failureに限られる。無制限な自動retryをしない。
            return (.generationFailed(.contextWindowExceeded), .notRetryable)
        case .assetsUnavailable:
            return (.generationFailed(.modelAssetsUnavailable), .retryable)
        case .guardrailViolation:
            return (.generationFailed(.guardrailViolation), .notRetryable)
        case .unsupportedGuide:
            return (.generationFailed(.unsupportedGuide), .notRetryable)
        case .unsupportedLanguageOrLocale:
            return (.unsupportedLocale, .notRetryable)
        case .decodingFailure:
            return (.generationFailed(.decodingFailed), .retryable)
        case .rateLimited:
            return (.generationFailed(.rateLimited), .retryable)
        case .concurrentRequests:
            return (.generationFailed(.concurrentRequestsNotAllowed), .retryable)
        case .refusal:
            return (.generationFailed(.refused), .notRetryable)
        @unknown default:
            // SDKが将来追加する未知caseを保守的にnon-retryableへ変換する。
            return (.generationFailed(.unknown), .notRetryable)
        }
    }

    // MARK: - Decode + source/item validation

    /// Structured Output全体のdecodeに失敗した場合はchunkのsource集合scopeで失敗を返し、項目境界を
    /// 捏造しない。decodeに成功した各itemについては、(1) 参照source IDが現在のchunkの入力に属すること、
    /// (2) 参照fragmentが対応するsourceのraw textに含まれる非空の完全一致部分であることを検証し、
    /// いずれかを満たさない項目はitemを構築せずsource-scopedな失敗として扱う（文字列類似での
    /// 再結合はしない）。境界を検証できた項目は、`coreRange`（この呼び出しが所有権を持つsource index
    /// 範囲）内にminimum source indexを持つ場合だけ採用し、overlapにより重複して現れた項目は
    /// 所有chunk以外では黙って捨てる。採用した項目については、最後に`explicitIngredients`の各要素が
    /// 参照fragmentへ実際に含まれるかを検証し、含まれない要素を除外したうえでitem-scopedな
    /// バリデーション失敗を併記する。
    private func decodeAndValidate(
        _ content: GeneratedContent,
        physicalRange: ClosedRange<Int>,
        coreRange: ClosedRange<Int>,
        allSegments: [MenuUnderstandingSourceSegment],
        sourceSeparator: String,
        nextOrdinal: inout Int
    ) -> RangeOutcome {
        let dto: MenuAnalysisDTO
        do {
            dto = try MenuAnalysisDTO(content)
        } catch {
            return RangeOutcome(failures: [
                MenuUnderstandingFailure(
                    scope: .sources(sourceIDs(in: physicalRange, of: allSegments)),
                    reason: .generationFailed(.decodingFailed),
                    retryability: .retryable
                ),
            ])
        }

        let allSegmentIDs = Set(allSegments.map(\.id))
        let physicalSegmentsByID = Dictionary(uniqueKeysWithValues: allSegments[physicalRange].map { ($0.id, $0) })
        let indexByID = Dictionary(uniqueKeysWithValues: allSegments.enumerated().map { ($0.element.id, $0.offset) })

        var outcome = RangeOutcome()

        for dtoItem in dto.items {
            var sourceReferences: [MenuUnderstandingSourceReference] = []
            var mappingFailure: MenuUnderstandingSourceMappingFailureReason?

            for dtoReference in dtoItem.sourceReferences {
                let sourceID = MenuUnderstandingSourceID(dtoReference.sourceID)
                guard !sourceID.isEmpty, allSegmentIDs.contains(sourceID) else {
                    mappingFailure = .unknownSourceID(sourceID)
                    break
                }
                guard let segment = physicalSegmentsByID[sourceID] else {
                    mappingFailure = .chunkBoundaryUnresolved
                    break
                }
                guard !dtoReference.fragment.isEmpty, segment.rawText.contains(dtoReference.fragment) else {
                    mappingFailure = .sourceFragmentMismatch(sourceID)
                    break
                }
                sourceReferences.append(MenuUnderstandingSourceReference(sourceID: sourceID, rawFragment: dtoReference.fragment))
            }

            if let mappingFailure {
                outcome.failures.append(
                    MenuUnderstandingFailure(
                        scope: .sources(sourceIDs(in: physicalRange, of: allSegments)),
                        reason: .sourceMappingInvalid(mappingFailure),
                        retryability: .notRetryable
                    )
                )
                continue
            }
            guard !sourceReferences.isEmpty else { continue }

            let minSourceIndex = sourceReferences.compactMap { indexByID[$0.sourceID] }.min() ?? Int.max
            guard coreRange.contains(minSourceIndex) else {
                // このchunkが所有権を持たない境界overlap上の項目。所有chunk側の出力を信頼し、
                // ここでは重複させない。
                continue
            }

            let reference = MenuUnderstandingItemReference(ordinal: nextOrdinal, sourceReferences: sourceReferences, separator: sourceSeparator)
            nextOrdinal += 1

            var explicitIngredients = dtoItem.explicitIngredients
            let referencedText = sourceReferences.map(\.rawFragment).joined()
            let invalidIngredients = explicitIngredients.filter { !referencedText.contains($0) }
            if !invalidIngredients.isEmpty {
                explicitIngredients.removeAll { invalidIngredients.contains($0) }
                outcome.failures.append(
                    MenuUnderstandingFailure(
                        scope: .item(reference),
                        reason: .itemValidationFailed(.explicitIngredientsNotInSource(invalidIngredients)),
                        retryability: .notRetryable
                    )
                )
            }

            outcome.items.append(
                ParsedMenuItem(
                    reference: reference,
                    baseDishCandidates: dtoItem.baseDishCandidates,
                    explicitIngredients: explicitIngredients,
                    preparationMethods: dtoItem.preparationMethods,
                    modifiers: dtoItem.modifiers,
                    unknownTerms: dtoItem.unknownTerms
                )
            )
        }

        return outcome
    }
}

// MARK: - Foundation Models request runner (テスト注入用の狭いseam)

/// Foundation Modelsの呼び出しを表す狭いProtocol。呼び出しごとにfreshな`LanguageModelSession`を
/// 生成する実装（`LiveFoundationModelsRequestRunner`）と、実モデルなしで`GeneratedContent`
/// または失敗を返すテスト用runnerを差し替え可能にする。戻り値を`GeneratedContent`（公開型）に
/// 統一することで、private DTOのaccess levelを広げずにDTO decode・domain mappingを
/// テストできる境界にしている。
protocol FoundationModelsRequestRunning: Sendable {
    func respond(instructions: String, prompt: String, options: GenerationOptions) async throws -> GeneratedContent
}

/// 実際に`LanguageModelSession`を生成しFoundation Modelsを呼び出す実装。呼び出しごとに新しい
/// Sessionを生成し、別の解析のtranscriptを再利用しない。
struct LiveFoundationModelsRequestRunner: FoundationModelsRequestRunning {
    func respond(instructions: String, prompt: String, options: GenerationOptions) async throws -> GeneratedContent {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: MenuAnalysisDTO.self, options: options)
        return response.content.generatedContent
    }
}

// MARK: - System language model availability provider (テスト注入用の狭いseam)

/// `SystemLanguageModel`の利用可否・locale対応取得を表す狭いProtocol。
protocol SystemLanguageModelAvailabilityProviding: Sendable {
    func currentAvailability() -> SystemLanguageModel.Availability
    func supportsLocale(_ locale: Locale) -> Bool
}

/// `SystemLanguageModel.default`を使う実装。値を保持・キャッシュせず、呼び出しごとに
/// 現在の状態を取得する。
struct LiveSystemLanguageModelAvailabilityProvider: SystemLanguageModelAvailabilityProviding {
    func currentAvailability() -> SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    func supportsLocale(_ locale: Locale) -> Bool {
        SystemLanguageModel.default.supportsLocale(locale)
    }
}

// MARK: - Context measurement (テスト注入用の狭いseam)

/// `contextSize`（4,096 token、`SystemLanguageModel.contextSize`相当）と、可能な環境でのtoken
/// preflightを提供する狭いProtocol。固定の文字数をtoken数として代用しない。
protocol MenuUnderstandingContextMeasuring: Sendable {
    var contextSize: Int { get }

    /// instructions・schema・prompt・`maximumResponseTokens`を合算した保守的な予測token数を返す。
    /// `tokenCount(for:)`が利用できない環境（iOS 26.4未満）やpreflight自体が失敗した場合は`nil`を
    /// 返し、呼び出し側は`exceededContextWindowSize`を検出してからの適応分割にフォールバックする。
    func predictedTotalTokenCount(instructions: String, prompt: String, maximumResponseTokens: Int) async -> Int?
}

/// `SystemLanguageModel.default`を使う実装。`contextSize`は`@backDeployed`によりiOS 26.0以降で
/// 動作するが、`tokenCount(for:)`はiOS 26.4以降でのみ呼び出す。
struct LiveMenuUnderstandingContextMeasurer: MenuUnderstandingContextMeasuring {
    var contextSize: Int {
        SystemLanguageModel.default.contextSize
    }

    func predictedTotalTokenCount(instructions: String, prompt: String, maximumResponseTokens: Int) async -> Int? {
        guard #available(iOS 26.4, *) else { return nil }
        let model = SystemLanguageModel.default
        do {
            let instructionsTokens = try await model.tokenCount(for: FoundationModels.Instructions(instructions))
            let promptTokens = try await model.tokenCount(for: prompt)
            let schemaTokens = try await model.tokenCount(for: MenuAnalysisDTO.generationSchema)
            return instructionsTokens + promptTokens + schemaTokens + maximumResponseTokens
        } catch {
            // preflight自体の失敗は、実際の呼び出しとexceededContextWindowSizeの検出へ委ねる。
            return nil
        }
    }
}

// MARK: - Clock (テスト注入用の狭いseam)

/// timeout計測に使う狭いProtocol。テストでは即時（またはごく短時間で）解決するfakeへ差し替え、
/// 実際に10秒待つことなくtimeout経路を検証できるようにする。
protocol MenuUnderstandingClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct LiveMenuUnderstandingClock: MenuUnderstandingClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

// MARK: - Timeout race gate

/// `respondWithTimeout`内で、実際の呼び出しとtimeout Taskのどちらが先に完了したかを判定する
/// actor。最初に届いた報告だけを採用し、以降の報告（timeout確定後に遅れて完了したrunner呼び出し等）
/// は無視することで、後着応答が確定済み結果を上書きしないことを保証する。
actor TimeoutRaceGate {
    enum Outcome {
        case content(GeneratedContent)
        case failure(Error)
        case timedOut
    }

    private var outcome: Outcome?
    private var continuation: CheckedContinuation<Outcome, Never>?

    func awaitOutcome() async -> Outcome {
        if let outcome {
            return outcome
        }
        return await withCheckedContinuation { continuation = $0 }
    }

    func reportSuccess(_ content: GeneratedContent) {
        resolve(.content(content))
    }

    func reportFailure(_ error: Error) {
        resolve(.failure(error))
    }

    func reportTimeout() {
        resolve(.timedOut)
    }

    private func resolve(_ newOutcome: Outcome) {
        guard outcome == nil else { return }
        outcome = newOutcome
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: newOutcome)
        }
    }
}

// MARK: - Structured Output DTO (private: ドメインモデルへ変換後は外部へ露出しない)
//
// 各配列に`.maximumCount`の有限上限を設け、`FoundationModelsMenuParser.init`の
// `maximumResponseTokens`（既定800）と整合する出力budgetにする。上限は代表ケース
// （`RepresentativeMenuFixtures`、いずれも数品程度）を十分に超える一方、無制限出力を
// 許さない値として選定した。1リクエストで上限を超える大きなメニューは`analyzeRange`が
// source境界でchunkへ分割し、超過分を黙って欠落させない。

@Generable
private struct MenuAnalysisDTO {
    @Guide(description: "メニュー原文から分割した料理項目。入力source順に沿って並べる。", .maximumCount(10))
    var items: [MenuItemDTO]
}

@Generable
private struct MenuItemDTO {
    @Guide(description: "この項目の根拠となる入力source。入力に存在するsource IDのみを参照する。", .maximumCount(4))
    var sourceReferences: [MenuItemSourceReferenceDTO]

    @Guide(description: "入力から読み取れるベース料理名候補。確度の高い候補を先頭にする。", .maximumCount(3))
    var baseDishCandidates: [String]

    @Guide(description: "原文に文字として明示されている食材のみ。料理名から推測した食材は含めない。", .maximumCount(6))
    var explicitIngredients: [String]

    @Guide(description: "原文に現れる調理方法。", .maximumCount(3))
    var preparationMethods: [String]

    @Guide(description: "量・味・地域性・追加/除外等の修飾表現。", .maximumCount(4))
    var modifiers: [String]

    @Guide(description: "意味を十分に解決できない語・未解決要素。", .maximumCount(4))
    var unknownTerms: [String]
}

@Generable
private struct MenuItemSourceReferenceDTO {
    @Guide(description: "参照元segmentの入力source ID。入力に存在するIDのみを使用する。")
    var sourceID: String

    @Guide(description: "参照元sourceのraw textに含まれる、この項目に対応する原文断片。")
    var fragment: String
}
