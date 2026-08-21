import Foundation
import FoundationModels

/// `MenuUnderstandingService`のApple Foundation Models実装。実行時の利用可否判定、
/// 型安全なStructured Output取得、Foundation Models固有エラーからtyped domain failureへの
/// 変換、context上限に応じたsource境界chunking、出力配列の有限上限飽和検出、10秒timeout、
/// source/item単位の検証をこのファイル内へ閉じ込める。`FoundationModels`をimportするのは
/// このファイルのみとし、`MenuUnderstandingService` Protocol・domain model・ViewModelへは
/// 一切露出させない。
///
/// Prompt本文は`MenuUnderstandingPrompt`（TASK-026）が抽出規則を確定させる。chunk分割・出力上限
/// 飽和検出・provenance identityによるglobal reconcileはFIX-005が確定させた契約に従う。
struct FoundationModelsMenuParser: MenuUnderstandingService {
    /// メニュー原文の対象locale。端末の`Locale.current`やユーザーの表示言語设定に判定を委ねず、
    /// 常にこの値で`supportsLocale(_:)`を確認する。
    static let menuLocale = Locale(identifier: "ja-JP")

    /// chunk境界を分割する際、隣接chunkへ重複させる（overlapさせる）source segment数の上限。
    /// 1つのitemが`MenuUnderstandingOutputLimits.sourceReferences`（4）件のsourceへまたがり得る
    /// 契約を維持するため、境界item解決に必要になり得る最大3つの隣接sourceを見込む（FIX-005）。
    /// 実際に付与されるoverlapは、隣接side自身のcore segment数（`- 1`）によっても制約されるため、
    /// 小さいsplitではこの上限に到達しない。
    private static let boundaryOverlapSegmentCount = MenuUnderstandingOutputLimits.sourceReferences - 1

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
    ///     FIX-005でPromptへ`rawText`・`analysisText`の両方を含めるようになった分の入力側token増は
    ///     `contextMeasurer`のtoken preflight（利用可能な環境）とcontext超過の反応的検出の双方で
    ///     引き続きcontext分割の対象になる。
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
        let outcome = await analyzeRange(
            physicalRange: fullRange,
            coreRange: fullRange,
            allSegments: request.segments,
            sourceSeparator: request.sourceSeparator
        )
        let (items, failures) = Self.reconcile(
            candidates: outcome.candidates,
            priorFailures: outcome.failures,
            allSegments: request.segments,
            sourceSeparator: request.sourceSeparator
        )

        return MenuUnderstandingResult(request: request, items: items, availability: availability, failures: failures)
    }

    // MARK: - Chunking (source境界を保ったまま再帰的に分割・実行する)

    /// 1回の`analyzeRange`呼び出しが集めた、まだordinalを持たない検証済み候補と失敗。
    /// ordinal・item-scoped failureの`MenuUnderstandingItemReference`は、全chunkの候補が出揃った後
    /// `reconcile(candidates:priorFailures:allSegments:sourceSeparator:)`が一度だけ確定させる
    /// （FIX-005: decode直後にordinalを付けない）。
    private struct RangeOutcome {
        var candidates: [ValidatedCandidate] = []
        var failures: [MenuUnderstandingFailure] = []
    }

    /// `coreRange`はこの呼び出しが分割の起点とするsource index範囲、`physicalRange`は実際に
    /// モデルへ渡すsource index範囲（`coreRange`に境界overlapを加えたもの）を表す。呼び出しのたびに
    /// 新しいSessionを使うFoundation Models呼び出しを1回試み、(1) `exceededContextWindowSize`・
    /// 事前のtoken preflightがcontext超過を示した場合、または(2) 応答の`items`が
    /// `MenuUnderstandingOutputLimits.items`へ飽和し、かつ`coreRange`をさらに安全に分割できる場合に、
    /// `coreRange`をsource境界で2分割し、それぞれを再帰的に処理してcandidateをmergeする
    /// （FIX-005: 上限飽和を明示的に検出し、silent successにしない）。
    ///
    /// このメソッドは、item-levelの所有権判定を一切行わない。overlapにより複数chunkが同じ境界item
    /// を独立に観測した場合も、両方のcandidateをそのまま返す。重複排除は`reconcile`が
    /// provenance identity（source ID・raw range・fragmentの順序付き組）に基づいて行う。
    private func analyzeRange(
        physicalRange: ClosedRange<Int>,
        coreRange: ClosedRange<Int>,
        allSegments: [MenuUnderstandingSourceSegment],
        sourceSeparator: String
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
                let decoded = decodeAndValidate(content, physicalRange: physicalRange, coreRange: coreRange, allSegments: allSegments)
                if decoded.itemsSaturated, coreRange.count > 1 {
                    // `items`が上限どおり返り、かつまだsource境界で分割できる。この応答は
                    // 「本当に全件」か「切り詰められた結果」か判別できないためprovisionalとして
                    // 破棄し（candidateもfailureも採用しない）、下のsplit処理へ進む。
                    needsSplit = true
                } else {
                    return RangeOutcome(candidates: decoded.candidates, failures: decoded.failures)
                }
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
            // source-scopedな失敗として返す（`items`飽和で`coreRange.count == 1`の場合は、上の
            // `!needsSplit`分岐が`decoded`を直接返しているため、ここへは到達しない）。
            let onlySourceID = allSegments[coreRange.lowerBound].id
            return RangeOutcome(failures: [
                MenuUnderstandingFailure(scope: .sources([onlySourceID]), reason: .generationFailed(.contextWindowExceeded), retryability: .notRetryable),
            ])
        }

        // `coreRange`を厳密に縮小しながら2分割する。同じ`(physicalRange, coreRange)`を再試行しない
        // ため、再帰は必ず有限回（高々source数程度の呼び出し）で停止する。
        let mid = (coreRange.lowerBound + coreRange.upperBound) / 2
        let leftCore = coreRange.lowerBound...mid
        let rightCore = (mid + 1)...coreRange.upperBound
        // overlapは常に隣接side自身のcore segment数（`- 1`）と`boundaryOverlapSegmentCount`の
        // 小さい方に収める。物理範囲の外側edge（`physicalRange`の境界）はここで再計算せず、
        // 親から継承した`physicalRange`をそのまま使うことで、多段再帰でも親由来のoverlap
        // （halo）を失わない（FIX-005: 旧実装は`coreRange`基準で再計算しhaloを失っていた）。
        let rightOverlap = min(Self.boundaryOverlapSegmentCount, rightCore.count - 1)
        let leftOverlap = min(Self.boundaryOverlapSegmentCount, leftCore.count - 1)
        let leftPhysical = physicalRange.lowerBound...(mid + rightOverlap)
        let rightPhysical = (mid + 1 - leftOverlap)...physicalRange.upperBound

        let leftOutcome = await analyzeRange(
            physicalRange: leftPhysical, coreRange: leftCore, allSegments: allSegments, sourceSeparator: sourceSeparator
        )
        let rightOutcome = await analyzeRange(
            physicalRange: rightPhysical, coreRange: rightCore, allSegments: allSegments, sourceSeparator: sourceSeparator
        )
        return RangeOutcome(candidates: leftOutcome.candidates + rightOutcome.candidates, failures: leftOutcome.failures + rightOutcome.failures)
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

    // MARK: - Decode + source/item validation (global reconcile前のcandidate生成)

    /// 1回のFoundation Models応答をdecode・検証した結果。`items`飽和判定はdomain mapping・
    /// item-scoped failure生成より前に行う（FIX-005: 上限到達を`failures`なしの成功として返さない）。
    private struct DecodeOutcome {
        var candidates: [ValidatedCandidate] = []
        var failures: [MenuUnderstandingFailure] = []
        /// `dto.items.count`が`MenuUnderstandingOutputLimits.items`へ到達したか。
        var itemsSaturated = false
    }

    /// ordinalを持たない内部候補。provenance identity（`provenance`。source ID・raw range・
    /// fragmentの順序付き組）で境界item・同文別itemを区別する。semantic fieldsはdecode済みの値を
    /// そのまま保持し、`explicitIngredients`は個別raw fragment単位の検証を経た値にする。
    /// `itemScopedFailureReasons`は、この候補が最終的にitemとして採用された場合にだけ
    /// `.item(reference)` scopeへ解決される（FIX-005）。
    private struct ValidatedCandidate {
        var provenance: [CandidateSourceReference]
        var baseDishCandidates: [String]
        var explicitIngredients: [String]
        var preparationMethods: [String]
        var modifiers: [String]
        var unknownTerms: [String]
        var itemScopedFailureReasons: [MenuUnderstandingFailureReason]
    }

    /// provenance identityの1要素。`rawRange`はraw text内でfragmentが一意に出現する位置
    /// （UTF-16 half-open range）を表し、`(sourceID, rawFragment)`だけでは区別できない同文別item・
    /// 同一source内の複数出現を識別するために使う（FIX-005）。
    private struct CandidateSourceReference: Equatable {
        let sourceID: MenuUnderstandingSourceID
        let rawRange: RawRange
        let rawFragment: String
    }

    /// sourceの`rawText`内での位置を表す、UTF-16 half-open rangeの座標系。
    private struct RawRange: Equatable, Hashable {
        let lowerBound: Int
        let upperBound: Int
    }

    /// Structured Output全体のdecodeに失敗した場合はchunkのsource集合scopeで失敗を返し、項目境界を
    /// 捏造しない。`items`が上限へ到達し、かつ`coreRange`をさらに分割できる場合は、呼び出し元
    /// （`analyzeRange`）が再分割できるよう`itemsSaturated`だけを立てて候補・failureを生成しない。
    ///
    /// それ以外の場合、decodeに成功した各itemについて (1) 参照source IDが現在のchunkの入力に属し、
    /// 空・重複・順序逆転がないこと、(2) 参照fragmentが対応するsourceのraw textに含まれる非空・
    /// 一意な完全一致部分であることを検証し、いずれかを満たさない項目はitemを構築せず
    /// source-scopedな失敗として扱う（文字列類似での再結合はしない）。`sourceReferences`が
    /// `MenuUnderstandingOutputLimits.sourceReferences`へ飽和した項目は、参照元が完全か証明できない
    /// ため通常itemとして受理せず、output-limit failureへする。
    ///
    /// 境界を検証できた項目は、所有権判定なしにそのまま候補として返す（overlapにより複数chunkが
    /// 同じ境界itemを独立に観測しても、ここでは重複排除しない）。重複排除・ordinal付与は
    /// `reconcile`がglobalに行う。採用した候補については、`explicitIngredients`の各要素が
    /// 対応する個別raw fragment（複数fragmentを連結した文字列ではない）へ実際に含まれるかを検証し、
    /// 含まれない要素を除外したうえでitem-scopedなバリデーション失敗を併記する。`baseDishCandidates`・
    /// `preparationMethods`・`modifiers`・`unknownTerms`が上限へ到達した場合も、候補自体は保持しつつ
    /// item-scopedなoutput-limit failureを併記する。
    private func decodeAndValidate(
        _ content: GeneratedContent,
        physicalRange: ClosedRange<Int>,
        coreRange: ClosedRange<Int>,
        allSegments: [MenuUnderstandingSourceSegment]
    ) -> DecodeOutcome {
        let dto: MenuAnalysisDTO
        do {
            dto = try MenuAnalysisDTO(content)
        } catch {
            return DecodeOutcome(failures: [
                MenuUnderstandingFailure(
                    scope: .sources(sourceIDs(in: physicalRange, of: allSegments)),
                    reason: .generationFailed(.decodingFailed),
                    retryability: .retryable
                ),
            ])
        }

        let itemsSaturated = dto.items.count >= MenuUnderstandingOutputLimits.items

        if itemsSaturated, coreRange.count > 1 {
            // 「本当に全件」か「切り詰められた結果」か判別できない。呼び出し元が再分割できるよう、
            // この応答（飽和した親応答）はprovisionalとして破棄し、候補・failureを一切生成しない。
            return DecodeOutcome(itemsSaturated: true)
        }

        let allSegmentIDs = Set(allSegments.map(\.id))
        let physicalSegmentsByID = Dictionary(uniqueKeysWithValues: allSegments[physicalRange].map { ($0.id, $0) })
        let indexByID = Dictionary(uniqueKeysWithValues: allSegments.enumerated().map { ($0.element.id, $0.offset) })

        var outcome = DecodeOutcome(itemsSaturated: itemsSaturated)

        for dtoItem in dto.items {
            var sourceReferences: [CandidateSourceReference] = []
            var resolvedIndices: [Int] = []
            var seenSourceIDsInItem = Set<MenuUnderstandingSourceID>()
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
                guard seenSourceIDsInItem.insert(sourceID).inserted else {
                    mappingFailure = .duplicateSourceReference(sourceID)
                    break
                }
                guard !dtoReference.fragment.isEmpty, segment.rawText.contains(dtoReference.fragment) else {
                    mappingFailure = .sourceFragmentMismatch(sourceID)
                    break
                }
                let occurrences = Self.occurrenceRanges(of: dtoReference.fragment, in: segment.rawText)
                guard occurrences.count == 1 else {
                    // fragmentが同じsource内に複数回出現し、どちらの出現かを推測で決められない。
                    mappingFailure = .ambiguousFragmentOccurrence(sourceID)
                    break
                }
                resolvedIndices.append(indexByID[sourceID] ?? Int.max)
                sourceReferences.append(CandidateSourceReference(sourceID: sourceID, rawRange: occurrences[0], rawFragment: dtoReference.fragment))
            }

            if mappingFailure == nil, sourceReferences.isEmpty {
                mappingFailure = .emptySourceReferences
            }
            if mappingFailure == nil, resolvedIndices != resolvedIndices.sorted() {
                mappingFailure = .sourceReferenceOrderInvalid
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

            if dtoItem.sourceReferences.count >= MenuUnderstandingOutputLimits.sourceReferences {
                // provenance-criticalなsourceReferencesが上限へ到達。参照元が完全か証明できないため、
                // 通常itemとして受理せず、既に検証済みの参照sourceをscopeとするfailureにする。
                outcome.failures.append(
                    MenuUnderstandingFailure(
                        scope: .sources(sourceReferences.map(\.sourceID)),
                        reason: .outputLimitReached(
                            MenuUnderstandingOutputLimit(field: .sourceReferences, limit: MenuUnderstandingOutputLimits.sourceReferences)
                        ),
                        retryability: .notRetryable
                    )
                )
                continue
            }

            // explicitIngredientsは、複数sourceのraw fragmentを連結した文字列ではなく、
            // 各要素が少なくとも1つの個別raw fragment内に完全一致することを確認する（FIX-005）。
            // source境界をまたいだ偽の一致（例: source A末尾「豚」+ source B先頭「肉」→「豚肉」）を
            // 受理しない。
            var explicitIngredients = dtoItem.explicitIngredients
            let invalidIngredients = explicitIngredients.filter { ingredient in
                !sourceReferences.contains { $0.rawFragment.contains(ingredient) }
            }
            var itemScopedFailureReasons: [MenuUnderstandingFailureReason] = []
            if !invalidIngredients.isEmpty {
                explicitIngredients.removeAll { invalidIngredients.contains($0) }
                itemScopedFailureReasons.append(.itemValidationFailed(.explicitIngredientsNotInSource(invalidIngredients)))
            }

            Self.appendOutputLimitFailureIfSaturated(dtoItem.baseDishCandidates.count, field: .baseDishCandidates, into: &itemScopedFailureReasons)
            Self.appendOutputLimitFailureIfSaturated(dtoItem.explicitIngredients.count, field: .explicitIngredients, into: &itemScopedFailureReasons)
            Self.appendOutputLimitFailureIfSaturated(dtoItem.preparationMethods.count, field: .preparationMethods, into: &itemScopedFailureReasons)
            Self.appendOutputLimitFailureIfSaturated(dtoItem.modifiers.count, field: .modifiers, into: &itemScopedFailureReasons)
            Self.appendOutputLimitFailureIfSaturated(dtoItem.unknownTerms.count, field: .unknownTerms, into: &itemScopedFailureReasons)

            outcome.candidates.append(
                ValidatedCandidate(
                    provenance: sourceReferences,
                    baseDishCandidates: dtoItem.baseDishCandidates,
                    explicitIngredients: explicitIngredients,
                    preparationMethods: dtoItem.preparationMethods,
                    modifiers: dtoItem.modifiers,
                    unknownTerms: dtoItem.unknownTerms,
                    itemScopedFailureReasons: itemScopedFailureReasons
                )
            )
        }

        if itemsSaturated {
            // ここへ到達するのは`coreRange.count == 1`（これ以上source境界で分割できない）場合のみ。
            // 検証済み候補は部分結果として保持しつつ、完全性を確認できないことを示すfailureを併記する。
            let scopeSourceID = allSegments[coreRange.lowerBound].id
            outcome.failures.append(
                MenuUnderstandingFailure(
                    scope: .sources([scopeSourceID]),
                    reason: .outputLimitReached(MenuUnderstandingOutputLimit(field: .items, limit: MenuUnderstandingOutputLimits.items)),
                    retryability: .notRetryable
                )
            )
        }

        return outcome
    }

    private static func appendOutputLimitFailureIfSaturated(
        _ count: Int,
        field: MenuUnderstandingOutputLimitField,
        into reasons: inout [MenuUnderstandingFailureReason]
    ) {
        let limit: Int
        switch field {
        case .items: limit = MenuUnderstandingOutputLimits.items
        case .sourceReferences: limit = MenuUnderstandingOutputLimits.sourceReferences
        case .baseDishCandidates: limit = MenuUnderstandingOutputLimits.baseDishCandidates
        case .explicitIngredients: limit = MenuUnderstandingOutputLimits.explicitIngredients
        case .preparationMethods: limit = MenuUnderstandingOutputLimits.preparationMethods
        case .modifiers: limit = MenuUnderstandingOutputLimits.modifiers
        case .unknownTerms: limit = MenuUnderstandingOutputLimits.unknownTerms
        }
        guard count >= limit else { return }
        reasons.append(.outputLimitReached(MenuUnderstandingOutputLimit(field: field, limit: limit)))
    }

    /// `text`内で`fragment`が完全一致する（重複しない）出現をすべて返す。空の`fragment`は
    /// 呼び出し前に弾かれている前提で、`fragment`が非空であることを要求しない代わりに空配列を返す。
    private static func occurrenceRanges(of fragment: String, in text: String) -> [RawRange] {
        guard !fragment.isEmpty else { return [] }
        var ranges: [RawRange] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex, let found = text.range(of: fragment, range: searchStart..<text.endIndex) {
            let lower = found.lowerBound.utf16Offset(in: text)
            let upper = found.upperBound.utf16Offset(in: text)
            ranges.append(RawRange(lowerBound: lower, upperBound: upper))
            searchStart = found.upperBound
        }
        return ranges
    }

    // MARK: - Global reconcile (candidate → domain item)

    /// 全chunkから集めたordinal未確定のcandidateを、provenance identityでグルーピングして重複排除し、
    /// 安定sortしてから初めてordinal 0...N-1を確定する（FIX-005）。owner側での採用確認なしに
    /// non-owner側のcandidateを無言で破棄しない設計であるため、ここに到達する候補はすべて
    /// 「境界を検証できた」候補であり、あとはprovenance identityが重複するかどうかだけを見る。
    ///
    /// - 同じprovenance identityの候補が1件だけならそのまま採用する。
    /// - 同じprovenance identityの候補が複数あり、semantic fieldsまで完全一致するなら安全な
    ///   duplicateとして1件へ畳む（overlapにより複数chunkが同じ境界itemを観測したケース）。
    /// - 同じprovenance identityでもsemantic fieldsが競合する候補が複数あれば、無言でどちらかを
    ///   選ばず`duplicateCandidateConflict`のtyped failureにし、その識別子ではitemを生成しない。
    private static func reconcile(
        candidates: [ValidatedCandidate],
        priorFailures: [MenuUnderstandingFailure],
        allSegments: [MenuUnderstandingSourceSegment],
        sourceSeparator: String
    ) -> (items: [ParsedMenuItem], failures: [MenuUnderstandingFailure]) {
        let indexByID = Dictionary(uniqueKeysWithValues: allSegments.enumerated().map { ($0.element.id, $0.offset) })

        var groupIndexByKey: [ProvenanceKey: Int] = [:]
        var groups: [[ValidatedCandidate]] = []
        for candidate in candidates {
            let key = ProvenanceKey(candidate.provenance)
            if let existingIndex = groupIndexByKey[key] {
                groups[existingIndex].append(candidate)
            } else {
                groupIndexByKey[key] = groups.count
                groups.append([candidate])
            }
        }

        var resolvedCandidates: [ValidatedCandidate] = []
        var reconcileFailures: [MenuUnderstandingFailure] = []

        for group in groups {
            guard let first = group.first else { continue }
            if group.count == 1 {
                resolvedCandidates.append(first)
                continue
            }

            let semanticFieldsAgree = group.dropFirst().allSatisfy { candidate in
                candidate.baseDishCandidates == first.baseDishCandidates
                    && candidate.explicitIngredients == first.explicitIngredients
                    && candidate.preparationMethods == first.preparationMethods
                    && candidate.modifiers == first.modifiers
                    && candidate.unknownTerms == first.unknownTerms
            }

            if semanticFieldsAgree {
                var mergedReasons: [MenuUnderstandingFailureReason] = []
                for candidate in group {
                    for reason in candidate.itemScopedFailureReasons where !mergedReasons.contains(reason) {
                        mergedReasons.append(reason)
                    }
                }
                var merged = first
                merged.itemScopedFailureReasons = mergedReasons
                resolvedCandidates.append(merged)
            } else {
                reconcileFailures.append(
                    MenuUnderstandingFailure(
                        scope: .sources(orderedUniqueSourceIDs(in: group, indexByID: indexByID)),
                        reason: .duplicateCandidateConflict,
                        retryability: .notRetryable
                    )
                )
            }
        }

        // 入力source順で安定sort: 先頭source referenceのglobal indexを主キー、そのraw rangeの
        // 開始位置を副キーにする。同じsourceに複数itemがある場合も、原文内の出現順を保つ。
        let sorted = resolvedCandidates.sorted { lhs, rhs in
            let lhsIndex = indexByID[lhs.provenance[0].sourceID] ?? Int.max
            let rhsIndex = indexByID[rhs.provenance[0].sourceID] ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.provenance[0].rawRange.lowerBound < rhs.provenance[0].rawRange.lowerBound
        }

        var items: [ParsedMenuItem] = []
        var itemScopedFailures: [MenuUnderstandingFailure] = []
        for (ordinal, candidate) in sorted.enumerated() {
            let reference = MenuUnderstandingItemReference(
                ordinal: ordinal,
                sourceReferences: candidate.provenance.map {
                    MenuUnderstandingSourceReference(sourceID: $0.sourceID, rawFragment: $0.rawFragment)
                },
                separator: sourceSeparator
            )
            items.append(
                ParsedMenuItem(
                    reference: reference,
                    baseDishCandidates: candidate.baseDishCandidates,
                    explicitIngredients: candidate.explicitIngredients,
                    preparationMethods: candidate.preparationMethods,
                    modifiers: candidate.modifiers,
                    unknownTerms: candidate.unknownTerms
                )
            )
            for reason in candidate.itemScopedFailureReasons {
                itemScopedFailures.append(MenuUnderstandingFailure(scope: .item(reference), reason: reason, retryability: .notRetryable))
            }
        }

        return (items, priorFailures + reconcileFailures + itemScopedFailures)
    }

    /// `group`内の全候補が参照するsource IDを、global source順で重複なく列挙する。
    private static func orderedUniqueSourceIDs(
        in group: [ValidatedCandidate],
        indexByID: [MenuUnderstandingSourceID: Int]
    ) -> [MenuUnderstandingSourceID] {
        var seen = Set<MenuUnderstandingSourceID>()
        var ids: [MenuUnderstandingSourceID] = []
        for candidate in group {
            for reference in candidate.provenance where seen.insert(reference.sourceID).inserted {
                ids.append(reference.sourceID)
            }
        }
        return ids.sorted { (indexByID[$0] ?? Int.max) < (indexByID[$1] ?? Int.max) }
    }

    /// candidateの重複排除に使う、順序付きprovenance identity。`(sourceID, rawFragment)`だけでは
    /// 同じsource内の同文別itemや複数出現を区別できないため、検証済みraw rangeを含める（FIX-005）。
    private struct ProvenanceKey: Hashable {
        struct Entry: Hashable {
            let sourceID: MenuUnderstandingSourceID
            let lowerBound: Int
            let upperBound: Int
        }
        let entries: [Entry]

        init(_ provenance: [CandidateSourceReference]) {
            entries = provenance.map { Entry(sourceID: $0.sourceID, lowerBound: $0.rawRange.lowerBound, upperBound: $0.rawRange.upperBound) }
        }
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
// 各配列の上限は`MenuUnderstandingOutputLimits`（`Meelyze/Models/MenuUnderstandingModels.swift`）
// を単一のsource of truthとして参照する。schema側の値とParserの飽和判定がずれないようにするためで、
// 上限値を上げるだけでは飽和時のsilent lossが再発する（FIX-005）。上限は代表ケース
// （`RepresentativeMenuFixtures`、いずれも数品程度）を十分に超える一方、無制限出力を許さない値として
// 選定した。1リクエストで上限を超える大きなメニューは`analyzeRange`がsource境界でchunkへ分割し、
// 上限へ飽和した応答はprovisionalとして扱う。

@Generable
private struct MenuAnalysisDTO {
    @Guide(description: "メニュー原文から分割した料理項目。入力source順に沿って並べる。", .maximumCount(MenuUnderstandingOutputLimits.items))
    var items: [MenuItemDTO]
}

@Generable
private struct MenuItemDTO {
    @Guide(description: "この項目の根拠となる入力source。入力に存在するsource IDのみを参照する。", .maximumCount(MenuUnderstandingOutputLimits.sourceReferences))
    var sourceReferences: [MenuItemSourceReferenceDTO]

    @Guide(description: "入力から読み取れるベース料理名候補。確度の高い候補を先頭にする。", .maximumCount(MenuUnderstandingOutputLimits.baseDishCandidates))
    var baseDishCandidates: [String]

    @Guide(description: "原文に文字として明示されている食材のみ。料理名から推測した食材は含めない。", .maximumCount(MenuUnderstandingOutputLimits.explicitIngredients))
    var explicitIngredients: [String]

    @Guide(description: "原文に現れる調理方法。", .maximumCount(MenuUnderstandingOutputLimits.preparationMethods))
    var preparationMethods: [String]

    @Guide(description: "量・味・地域性・追加/除外等の修飾表現。", .maximumCount(MenuUnderstandingOutputLimits.modifiers))
    var modifiers: [String]

    @Guide(description: "意味を十分に解決できない語・未解決要素。", .maximumCount(MenuUnderstandingOutputLimits.unknownTerms))
    var unknownTerms: [String]
}

@Generable
private struct MenuItemSourceReferenceDTO {
    @Guide(description: "参照元segmentの入力source ID。入力に存在するIDのみを使用する。")
    var sourceID: String

    @Guide(description: "参照元sourceのraw textに含まれる、この項目に対応する原文断片。")
    var fragment: String
}
