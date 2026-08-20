import Testing
import Foundation
import FoundationModels
@testable import Meelyze

struct FoundationModelsMenuParserTests {

    // MARK: - availability()

    @Test func availabilityReflectsAvailableWithoutModification() async {
        let provider = FakeAvailabilityProvider()
        provider.availabilityToReturn = .available
        let parser = makeParser(runner: FakeFoundationModelsRequestRunner(), availabilityProvider: provider)

        let availability = await parser.availability()

        #expect(availability == .available)
    }

    @Test func availabilityMapsAllThreeKnownUnavailableReasons() async {
        let cases: [(SystemLanguageModel.Availability.UnavailableReason, MenuUnderstandingAvailability.UnavailableReason)] = [
            (.deviceNotEligible, .deviceNotEligible),
            (.appleIntelligenceNotEnabled, .appleIntelligenceNotEnabled),
            (.modelNotReady, .modelNotReady),
        ]

        for (sdkReason, expectedDomainReason) in cases {
            let provider = FakeAvailabilityProvider()
            provider.availabilityToReturn = .unavailable(sdkReason)
            let parser = makeParser(runner: FakeFoundationModelsRequestRunner(), availabilityProvider: provider)

            let availability = await parser.availability()

            #expect(availability == .unavailable(expectedDomainReason), "sdkReason: \(sdkReason)")
        }
    }

    // MARK: - analyze(): input validation short-circuits before calling the model

    @Test func analyzeRejectsDuplicateSourceIDsWithoutCallingRunner() async {
        let runner = FakeFoundationModelsRequestRunner()
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1"), segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures == [.invalidInput(.duplicateSourceID(MenuUnderstandingSourceID("s1")))])
        #expect(runner.invocations.isEmpty)
    }

    @Test func analyzeRejectsEmptySourceIDsWithoutCallingRunner() async {
        let runner = FakeFoundationModelsRequestRunner()
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "")])

        let result = await parser.analyze(request)

        #expect(result.failures == [.invalidInput(.emptySourceID(index: 0))])
        #expect(runner.invocations.isEmpty)
    }

    // MARK: - analyze(): unavailable / unsupported locale short-circuit before calling the model

    @Test func analyzeReturnsModelUnavailableFailureWithoutCallingRunnerWhenUnavailable() async {
        let provider = FakeAvailabilityProvider()
        provider.availabilityToReturn = .unavailable(.appleIntelligenceNotEnabled)
        let runner = FakeFoundationModelsRequestRunner()
        let parser = makeParser(runner: runner, availabilityProvider: provider)
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.availability == .unavailable(.appleIntelligenceNotEnabled))
        #expect(result.failures == [
            MenuUnderstandingFailure(scope: .request, reason: .modelUnavailable(.appleIntelligenceNotEnabled), retryability: .notRetryable),
        ])
        #expect(runner.invocations.isEmpty)
    }

    @Test func analyzeTreatsModelNotReadyAsRetryable() async {
        let provider = FakeAvailabilityProvider()
        provider.availabilityToReturn = .unavailable(.modelNotReady)
        let parser = makeParser(runner: FakeFoundationModelsRequestRunner(), availabilityProvider: provider)
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.failures.first?.retryability == .retryable)
    }

    @Test func analyzeReturnsUnsupportedLocaleFailureDistinctFromModelUnavailableWhenLocaleUnsupported() async {
        let provider = FakeAvailabilityProvider()
        provider.availabilityToReturn = .available
        provider.localeSupportToReturn = false
        let runner = FakeFoundationModelsRequestRunner()
        let parser = makeParser(runner: runner, availabilityProvider: provider)
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        // モデル自体は利用可能なので、availability snapshotは`.available`のまま。
        #expect(result.availability == .available)
        #expect(result.failures == [
            MenuUnderstandingFailure(scope: .request, reason: .unsupportedLocale, retryability: .notRetryable),
        ])
        #expect(runner.invocations.isEmpty)
        #expect(provider.suppliedLocales == [FoundationModelsMenuParser.menuLocale])
    }

    // MARK: - analyze(): structured output -> domain mapping

    @Test func analyzeMapsSingleSourceItemFromStructuredOutput() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try GeneratedContent(json: """
            {"items": [{"sourceReferences": [{"sourceID": "s1", "fragment": "ラフテー"}], \
            "baseDishCandidates": ["ラフテー"], "explicitIngredients": [], "preparationMethods": [], \
            "modifiers": [], "unknownTerms": []}]}
            """)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ラフテー")])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 1)
        #expect(result.items[0].reference.ordinal == 0)
        #expect(result.items[0].reference.originalText == "ラフテー")
        #expect(result.items[0].reference.sourceReferences == [
            MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "ラフテー"),
        ])
        #expect(result.items[0].baseDishCandidates == ["ラフテー"])
    }

    @Test func analyzeConstructsOriginalTextDeterministicallyForMultiSourceItemUsingRequestSeparator() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try GeneratedContent(json: """
            {"items": [{"sourceReferences": [{"sourceID": "s1", "fragment": "島豚の炙り"}, \
            {"sourceID": "s2", "fragment": "沖縄そば"}], "baseDishCandidates": ["沖縄そば"], \
            "explicitIngredients": ["島豚"], "preparationMethods": ["炙り"], "modifiers": [], "unknownTerms": []}]}
            """)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(
            segments: [segment(id: "s1", rawText: "島豚の炙り"), segment(id: "s2", rawText: "沖縄そば")],
            sourceSeparator: " / "
        )

        let result = await parser.analyze(request)

        #expect(result.items[0].reference.originalText == "島豚の炙り / 沖縄そば")
        #expect(result.items[0].explicitIngredients == ["島豚"])
        #expect(result.items[0].preparationMethods == ["炙り"])
    }

    @Test func analyzeAssignsOrdinalsBySequentialStructuredOutputOrder() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try GeneratedContent(json: """
            {"items": [
                {"sourceReferences": [{"sourceID": "s1", "fragment": "ラフテー"}], "baseDishCandidates": ["ラフテー"], "explicitIngredients": [], "preparationMethods": [], "modifiers": [], "unknownTerms": []},
                {"sourceReferences": [{"sourceID": "s2", "fragment": "ソーキそば"}], "baseDishCandidates": ["ソーキそば"], "explicitIngredients": [], "preparationMethods": [], "modifiers": [], "unknownTerms": []}
            ]}
            """)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ラフテー"),
            segment(id: "s2", rawText: "ソーキそば"),
        ])

        let result = await parser.analyze(request)

        #expect(result.items.map(\.reference.ordinal) == [0, 1])
    }

    @Test func analyzeReturnsDecodingFailedScopedToTheChunkWhenStructuredPayloadDoesNotMatchSchema() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try GeneratedContent(json: #"{"items": "not-an-array"}"#)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures == [
            MenuUnderstandingFailure(scope: .sources([MenuUnderstandingSourceID("s1")]), reason: .generationFailed(.decodingFailed), retryability: .retryable),
        ])
    }

    // MARK: - analyze(): GenerationError -> typed domain reason/retryability table

    @Test func analyzeMapsEachKnownGenerationErrorCaseToADistinctReasonAndRetryability() async {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        let cases: [(name: String, error: LanguageModelSession.GenerationError, reason: MenuUnderstandingFailureReason, retryability: MenuUnderstandingRetryability)] = [
            ("exceededContextWindowSize", .exceededContextWindowSize(context), .generationFailed(.contextWindowExceeded), .notRetryable),
            ("assetsUnavailable", .assetsUnavailable(context), .generationFailed(.modelAssetsUnavailable), .retryable),
            ("guardrailViolation", .guardrailViolation(context), .generationFailed(.guardrailViolation), .notRetryable),
            ("unsupportedGuide", .unsupportedGuide(context), .generationFailed(.unsupportedGuide), .notRetryable),
            ("unsupportedLanguageOrLocale", .unsupportedLanguageOrLocale(context), .unsupportedLocale, .notRetryable),
            ("decodingFailure", .decodingFailure(context), .generationFailed(.decodingFailed), .retryable),
            ("rateLimited", .rateLimited(context), .generationFailed(.rateLimited), .retryable),
            ("concurrentRequests", .concurrentRequests(context), .generationFailed(.concurrentRequestsNotAllowed), .retryable),
            (
                "refusal",
                .refusal(.init(transcriptEntries: []), context),
                .generationFailed(.refused),
                .notRetryable
            ),
        ]

        for testCase in cases {
            // exceededContextWindowSizeは単一sourceでは分割できず、"これ以上分割できない"分岐で
            // 同じreasonへ到達する。他のcaseは通常のGenerationErrorマッピング分岐を通る。
            let runner = FakeFoundationModelsRequestRunner()
            runner.resultProvider = { _, _, _ in throw testCase.error }
            let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
            let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

            let result = await parser.analyze(request)

            #expect(result.failures.count == 1, "case: \(testCase.name)")
            #expect(result.failures.first?.reason == testCase.reason, "case: \(testCase.name)")
            #expect(result.failures.first?.retryability == testCase.retryability, "case: \(testCase.name)")
            #expect(result.failures.first?.scope == .sources([MenuUnderstandingSourceID("s1")]), "case: \(testCase.name)")
        }
    }

    @Test func analyzeConservativelyMapsUnexpectedNonGenerationErrorToNotRetryableUnknown() async {
        struct SomeOtherError: Error {}
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in throw SomeOtherError() }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.failures == [
            MenuUnderstandingFailure(scope: .sources([MenuUnderstandingSourceID("s1")]), reason: .generationFailed(.unknown), retryability: .notRetryable),
        ])
    }

    // MARK: - analyze(): fresh runner invocation per call, no shared state across calls

    @Test func analyzeInvokesRunnerExactlyOncePerCallWithoutReusingAPriorInvocation() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in try GeneratedContent(json: #"{"items": []}"#) }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        _ = await parser.analyze(request)
        _ = await parser.analyze(request)

        #expect(runner.invocations.count == 2)
    }

    // MARK: - analyze(): maximumResponseTokens flows into GenerationOptions

    @Test func analyzePassesConfiguredMaximumResponseTokensToGenerationOptions() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in try GeneratedContent(json: #"{"items": []}"#) }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider(), maximumResponseTokens: 777)
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        _ = await parser.analyze(request)

        #expect(runner.invocations.first?.options.maximumResponseTokens == 777)
    }

    // MARK: - analyze(): wires MenuUnderstandingPrompt output through to the runner unchanged

    @Test func analyzeSendsMenuUnderstandingPromptInstructionsAndPromptToTheRunner() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in try GeneratedContent(json: #"{"items": []}"#) }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ラフテー")])

        _ = await parser.analyze(request)

        let invocation = try #require(runner.invocations.first)
        #expect(invocation.instructions == MenuUnderstandingPrompt.instructions())
        #expect(invocation.prompt == MenuUnderstandingPrompt.prompt(for: request))
    }

    // MARK: - analyze(): source mapping validation (TASK-027)

    @Test func analyzeRejectsItemReferencingASourceIDThatNeverExistedInTheRequest() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try GeneratedContent(json: """
            {"items": [{"sourceReferences": [{"sourceID": "s99", "fragment": "何か"}], \
            "baseDishCandidates": [], "explicitIngredients": [], "preparationMethods": [], "modifiers": [], "unknownTerms": []}]}
            """)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ラフテー")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures == [
            MenuUnderstandingFailure(
                scope: .sources([MenuUnderstandingSourceID("s1")]),
                reason: .sourceMappingInvalid(.unknownSourceID(MenuUnderstandingSourceID("s99"))),
                retryability: .notRetryable
            ),
        ])
    }

    @Test func analyzeRejectsItemWhoseFragmentIsNotFoundInTheReferencedSourceRawText() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try GeneratedContent(json: """
            {"items": [{"sourceReferences": [{"sourceID": "s1", "fragment": "全く違う文字列"}], \
            "baseDishCandidates": [], "explicitIngredients": [], "preparationMethods": [], "modifiers": [], "unknownTerms": []}]}
            """)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ラフテー")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures == [
            MenuUnderstandingFailure(
                scope: .sources([MenuUnderstandingSourceID("s1")]),
                reason: .sourceMappingInvalid(.sourceFragmentMismatch(MenuUnderstandingSourceID("s1"))),
                retryability: .notRetryable
            ),
        ])
    }

    @Test func analyzeStripsExplicitIngredientsNotFoundInSourceFragmentsAndKeepsTheItemWithAnItemScopedFailure() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try GeneratedContent(json: """
            {"items": [{"sourceReferences": [{"sourceID": "s1", "fragment": "ゴーヤーチャンプルー"}], \
            "baseDishCandidates": ["ゴーヤーチャンプルー"], "explicitIngredients": ["ゴーヤー", "捏造食材"], \
            "preparationMethods": [], "modifiers": [], "unknownTerms": []}]}
            """)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ゴーヤーチャンプルー")])

        let result = await parser.analyze(request)

        #expect(result.items.count == 1)
        #expect(result.items[0].explicitIngredients == ["ゴーヤー"])
        #expect(result.items[0].baseDishCandidates == ["ゴーヤーチャンプルー"])
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason == .itemValidationFailed(.explicitIngredientsNotInSource(["捏造食材"])))
        #expect(result.failures[0].retryability == .notRetryable)
        if case .item(let reference) = result.failures[0].scope {
            #expect(reference == result.items[0].reference)
        } else {
            Issue.record("expected .item scope carrying the resolved item reference")
        }
    }

    // MARK: - analyze(): single source too large for the context window

    @Test func analyzeReturnsSourceScopedFailureWithoutSplittingFurtherWhenASingleSegmentAloneExceedsContext() async throws {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "too big")
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in throw LanguageModelSession.GenerationError.exceededContextWindowSize(context) }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures == [
            MenuUnderstandingFailure(scope: .sources([MenuUnderstandingSourceID("s1")]), reason: .generationFailed(.contextWindowExceeded), retryability: .notRetryable),
        ])
        // 単一sourceはこれ以上分割できないため、1回の試行だけで打ち切られる。
        #expect(runner.invocations.count == 1)
    }

    // MARK: - analyze(): reactive context-exceeded splitting with boundary overlap and ownership dedup

    @Test func analyzeSplitsOnExceededContextWindowSizeAndDedupsBoundaryOverlapByOwnership() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let dishes = parsePromptLines(prompt)
            if dishes.count >= 3 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            return try jsonForSingleSourceDishes(dishes)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ラフテー"),
            segment(id: "s2", rawText: "ミミガー"),
            segment(id: "s3", rawText: "テビチ"),
        ])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == [["s1"], ["s2"], ["s3"]])
        #expect(result.items.map(\.baseDishCandidates) == [["ラフテー"], ["ミミガー"], ["テビチ"]])
        #expect(result.items.map(\.reference.ordinal) == [0, 1, 2])
        // 1回目（全体・失敗）＋ 左右2つのsub-chunk（overlapによりs2が両方の入力に現れるが、
        // 出力側はownershipにより重複しない）＝ 3回のFoundation Models呼び出し。
        #expect(runner.invocations.count == 3)
    }

    @Test func analyzeRejectsItemsReferencingASourceThatExistsInTheRequestButNotInTheCurrentChunk() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let dishes = parsePromptLines(prompt)
            if dishes.count >= 2 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            // 単一segmentのchunkへ縮退した後も、あえて「相手側」のsource IDを参照して誤動作を模す。
            let onlyID = dishes[0].id
            let foreignID = onlyID == "s1" ? "s2" : "s1"
            return try jsonForSingleSourceDishes([(id: foreignID, text: "誤参照")])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures.count == 2)
        for failure in result.failures {
            #expect(failure.reason == .sourceMappingInvalid(.chunkBoundaryUnresolved))
            #expect(failure.retryability == .notRetryable)
        }
    }

    // MARK: - analyze(): proactive token preflight (iOS 26.4+) skips a doomed full-range attempt

    @Test func analyzeSplitsProactivelyWhenContextMeasurerPredictsOverflowWithoutAttemptingTheFullRangeFirst() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in try jsonForSingleSourceDishes(parsePromptLines(prompt)) }
        let contextMeasurer = FakeContextMeasurer(contextSize: 100) { prompt in
            parsePromptLines(prompt).count >= 2 ? 1000 : 10
        }
        let parser = FoundationModelsMenuParser(
            runner: runner,
            availabilityProvider: FakeAvailabilityProvider(),
            contextMeasurer: contextMeasurer
        )
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー")])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == [["s1"], ["s2"]])
        // 全体レンジへの無駄な試行をせず、分割後の2回だけ呼び出す。
        #expect(runner.invocations.count == 2)
    }

    // MARK: - analyze(): 10 second timeout wrapper isolates late responses

    @Test func analyzeReturnsTypedTimeoutPromptlyAndSafelyDiscardsALateArrivingResponse() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.blockUntilReleased = true
        let parser = FoundationModelsMenuParser(
            runner: runner,
            availabilityProvider: FakeAvailabilityProvider(),
            contextMeasurer: NoOpContextMeasurer(),
            clock: InstantMenuUnderstandingClock(),
            timeoutDuration: .seconds(10)
        )
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.reason == .generationFailed(.timedOut))
        #expect(result.failures.first?.retryability == .retryable)
        #expect(result.failures.first?.scope == .sources([MenuUnderstandingSourceID("s1")]))

        // cancelを無視して遅れて完了するrunnerを解放しても、クラッシュ・deadlockせず安全に破棄される。
        runner.releasePending(with: .success(try GeneratedContent(json: #"{"items": []}"#)))
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - analyze(): representative menu cases through the adapter boundary

    @Test func representativeMenuCasesMapDeterministicallyThroughTheAdapterBoundary() async throws {
        for fixture in RepresentativeMenuFixtures.all {
            let runner = FakeFoundationModelsRequestRunner()
            runner.resultProvider = { _, _, _ in try GeneratedContent(json: fixture.modelResponseJSON) }
            let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
            let request = MenuUnderstandingRequest(
                segments: fixture.segments.map {
                    MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID($0.id), rawText: $0.rawText, confidence: 0.9, boundingBox: .zero)
                }
            )

            let result = await parser.analyze(request)

            #expect(result.failures.isEmpty, "fixture: \(fixture.name)")
            #expect(result.items.count == fixture.expectedItems.count, "fixture: \(fixture.name)")
            for (item, expected) in zip(result.items, fixture.expectedItems) {
                #expect(item.reference.sourceReferences.map(\.sourceID.rawValue) == expected.sourceIDs, "fixture: \(fixture.name)")
                #expect(item.reference.originalText == expected.originalText, "fixture: \(fixture.name)")
                #expect(item.baseDishCandidates == expected.baseDishCandidates, "fixture: \(fixture.name)")
                #expect(item.explicitIngredients == expected.explicitIngredients, "fixture: \(fixture.name)")
                #expect(item.preparationMethods == expected.preparationMethods, "fixture: \(fixture.name)")
                #expect(item.modifiers == expected.modifiers, "fixture: \(fixture.name)")
                #expect(item.unknownTerms == expected.unknownTerms, "fixture: \(fixture.name)")
            }
        }
    }

    @Test func representativeMenuCasesNeverProduceAllergenOrSafetyRelatedText() async throws {
        let forbiddenSubstrings = ["アレルゲン", "アレルギー", "安全", "該当なし", "含まれない", "食べられ"]

        for fixture in RepresentativeMenuFixtures.all {
            let runner = FakeFoundationModelsRequestRunner()
            runner.resultProvider = { _, _, _ in try GeneratedContent(json: fixture.modelResponseJSON) }
            let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
            let request = MenuUnderstandingRequest(
                segments: fixture.segments.map {
                    MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID($0.id), rawText: $0.rawText, confidence: 0.9, boundingBox: .zero)
                }
            )

            let result = await parser.analyze(request)

            for item in result.items {
                let allText = ([item.baseDishCandidates, item.explicitIngredients, item.preparationMethods, item.modifiers, item.unknownTerms]
                    .flatMap { $0 } + [item.reference.originalText]).joined()
                for forbidden in forbiddenSubstrings {
                    #expect(!allText.contains(forbidden), "fixture: \(fixture.name) unexpectedly contains \(forbidden)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func segment(id: String, rawText: String = "raw") -> MenuUnderstandingSourceSegment {
        MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID(id), rawText: rawText, confidence: 0.9, boundingBox: .zero)
    }
}

/// `FoundationModelsMenuParser`のtest-friendlyなfactory。既定の`LiveMenuUnderstandingContextMeasurer`は
/// 実SDKの`SystemLanguageModel`へ問い合わせるため、`contextMeasurer`は常に`NoOpContextMeasurer`へ
/// 差し替え、chunking関連の挙動を実機のApple Intelligence状態に依存させない。
private func makeParser(
    runner: any FoundationModelsRequestRunning,
    availabilityProvider: any SystemLanguageModelAvailabilityProviding,
    maximumResponseTokens: Int = 800
) -> FoundationModelsMenuParser {
    FoundationModelsMenuParser(
        runner: runner,
        availabilityProvider: availabilityProvider,
        contextMeasurer: NoOpContextMeasurer(),
        maximumResponseTokens: maximumResponseTokens
    )
}

/// promptの`[id] text`形式の行を`(id, text)`へ分解する。chunking関連のfake runnerが、
/// 実際に渡されたsegment集合に応じて応答内容を変えるために使う。
private func parsePromptLines(_ prompt: String) -> [(id: String, text: String)] {
    prompt.split(separator: "\n").compactMap { line -> (id: String, text: String)? in
        guard line.first == "[", let closeBracket = line.firstIndex(of: "]") else { return nil }
        let id = String(line[line.index(after: line.startIndex)..<closeBracket])
        let text = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
        return (id, text)
    }
}

/// 各dishを単一sourceのみを参照する独立した項目として返すStructured Outputを組み立てる。
private func jsonForSingleSourceDishes(_ dishes: [(id: String, text: String)]) throws -> GeneratedContent {
    let payload = SimpleDishPayload(items: dishes.map {
        SimpleDishPayload.Item(
            sourceReferences: [SimpleDishPayload.Item.Reference(sourceID: $0.id, fragment: $0.text)],
            baseDishCandidates: [$0.text],
            explicitIngredients: [],
            preparationMethods: [],
            modifiers: [],
            unknownTerms: []
        )
    })
    let data = try JSONEncoder().encode(payload)
    let jsonString = String(data: data, encoding: .utf8)!
    return try GeneratedContent(json: jsonString)
}

private struct SimpleDishPayload: Encodable {
    struct Item: Encodable {
        struct Reference: Encodable {
            let sourceID: String
            let fragment: String
        }
        let sourceReferences: [Reference]
        let baseDishCandidates: [String]
        let explicitIngredients: [String]
        let preparationMethods: [String]
        let modifiers: [String]
        let unknownTerms: [String]
    }
    let items: [Item]
}

// MARK: - Test doubles

private final class FakeAvailabilityProvider: SystemLanguageModelAvailabilityProviding, @unchecked Sendable {
    var availabilityToReturn: SystemLanguageModel.Availability = .available
    var localeSupportToReturn = true
    private(set) var suppliedLocales: [Locale] = []

    func currentAvailability() -> SystemLanguageModel.Availability {
        availabilityToReturn
    }

    func supportsLocale(_ locale: Locale) -> Bool {
        suppliedLocales.append(locale)
        return localeSupportToReturn
    }
}

private final class FakeFoundationModelsRequestRunner: FoundationModelsRequestRunning, @unchecked Sendable {
    var resultProvider: (@Sendable (String, String, GenerationOptions) throws -> GeneratedContent)?
    var blockUntilReleased = false

    private let lock = NSLock()
    private var _invocations: [(instructions: String, prompt: String, options: GenerationOptions)] = []
    private var pendingContinuations: [CheckedContinuation<GeneratedContent, Error>] = []

    var invocations: [(instructions: String, prompt: String, options: GenerationOptions)] {
        lock.lock()
        defer { lock.unlock() }
        return _invocations
    }

    func respond(instructions: String, prompt: String, options: GenerationOptions) async throws -> GeneratedContent {
        let shouldBlock = recordInvocationAndReturnShouldBlock((instructions, prompt, options))

        if shouldBlock {
            return try await withCheckedThrowingContinuation { continuation in
                self.enqueue(continuation)
            }
        }
        guard let resultProvider else {
            return try GeneratedContent(json: #"{"items": []}"#)
        }
        return try resultProvider(instructions, prompt, options)
    }

    /// timeoutで既に打ち切られた後の、遅れて完了する応答を模す。
    func releasePending(with result: Result<GeneratedContent, Error>) {
        for continuation in dequeueAllPending() {
            continuation.resume(with: result)
        }
    }

    // NSLockのlock/unlockはasync文脈から直接呼べないため、同期関数へ閉じ込める。
    private func recordInvocationAndReturnShouldBlock(_ invocation: (String, String, GenerationOptions)) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _invocations.append(invocation)
        return blockUntilReleased
    }

    private func enqueue(_ continuation: CheckedContinuation<GeneratedContent, Error>) {
        lock.lock()
        defer { lock.unlock() }
        pendingContinuations.append(continuation)
    }

    private func dequeueAllPending() -> [CheckedContinuation<GeneratedContent, Error>] {
        lock.lock()
        defer { lock.unlock() }
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        return continuations
    }
}

private struct NoOpContextMeasurer: MenuUnderstandingContextMeasuring {
    let contextSize = 4096

    func predictedTotalTokenCount(instructions: String, prompt: String, maximumResponseTokens: Int) async -> Int? {
        nil
    }
}

private struct FakeContextMeasurer: MenuUnderstandingContextMeasuring {
    let contextSize: Int
    let predictor: @Sendable (String) -> Int?

    func predictedTotalTokenCount(instructions: String, prompt: String, maximumResponseTokens: Int) async -> Int? {
        predictor(prompt)
    }
}

/// `timeoutDuration`を無視して即座に解決するfake clock。timeoutのtyped経路を、実際に
/// 数秒待つことなく決定的に検証するために使う。
private struct InstantMenuUnderstandingClock: MenuUnderstandingClock {
    func sleep(for duration: Duration) async throws {}
}
