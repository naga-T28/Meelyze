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

    // MARK: - analyze(): output limit saturation and completeness (FIX-005)

    @Test func analyzeSplitsWhenElevenShortSourcesSaturateTheItemsLimitAndRecoversAllElevenItems() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            return try jsonForSingleSourceDishes(Array(visible.prefix(MenuUnderstandingOutputLimits.items)))
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: (1...11).map { segment(id: "s\($0)", rawText: "D\($0)") })

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 11)
        #expect(result.items.map(\.reference.ordinal) == Array(0...10))
        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == (1...11).map { ["s\($0)"] })
        // 飽和した親（discardされる）＋左右2つのsub-chunk＝3回。飽和親のitemsが二重計上されない。
        #expect(runner.invocations.count == 3)
    }

    @Test func analyzeResolvesExactlyTenItemsAtTheSaturationBoundaryWithoutDoubleCountingTheDiscardedParent() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            return try jsonForSingleSourceDishes(Array(visible.prefix(MenuUnderstandingOutputLimits.items)))
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: (1...10).map { segment(id: "s\($0)", rawText: "D\($0)") })

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 10)
        #expect(result.items.map(\.reference.ordinal) == Array(0...9))
        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == (1...10).map { ["s\($0)"] })
        #expect(runner.invocations.count == 3)
    }

    @Test func analyzeKeepsSuccessfulChildItemsAndTheFailedChildsFailureWithoutFallingBackToTheSaturatedParent() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            // 右子chunk（s4〜s11の8件が見える呼び出し）だけを生成失敗させる。
            if visible.count == 8 {
                throw LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "test"))
            }
            return try jsonForSingleSourceDishes(Array(visible.prefix(MenuUnderstandingOutputLimits.items)))
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: (1...11).map { segment(id: "s\($0)", rawText: "D\($0)") })

        let result = await parser.analyze(request)

        #expect(result.items.count == 9)
        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == (1...9).map { ["s\($0)"] })
        #expect(result.items.map(\.reference.ordinal) == Array(0...8))
        // 飽和した親の10件をfallbackとして混在させない（s10・s11を含まない）。
        #expect(!result.items.contains { $0.reference.sourceReferences.map(\.sourceID.rawValue) == ["s10"] })
        #expect(!result.items.contains { $0.reference.sourceReferences.map(\.sourceID.rawValue) == ["s11"] })
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason == .generationFailed(.guardrailViolation))
        #expect(result.failures[0].retryability == .notRetryable)
        #expect(result.isPartialSuccess)
    }

    @Test func analyzeKeepsPartialItemsWithAnOutputLimitFailureWhenASingleUnsplittableSourceSaturatesTheItemsLimit() async throws {
        // 固定幅（2桁ゼロ埋め）にすることで、"D1"が"D10"の部分文字列として偽の複数出現を
        // 起こさないようにする（ambiguousFragmentOccurrence誤検出を避ける）。
        let tokens = (0..<11).map { String(format: "D%02d", $0) }
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try jsonPayload(items: tokens.prefix(MenuUnderstandingOutputLimits.items).map { singleSourceItem(id: "s1", fragment: $0) })
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: tokens.joined(separator: " "))])

        let result = await parser.analyze(request)

        #expect(result.items.count == 10)
        #expect(result.items.map(\.reference.ordinal) == Array(0...9))
        #expect(result.failures.count == 1)
        #expect(result.failures[0].scope == .sources([MenuUnderstandingSourceID("s1")]))
        #expect(result.failures[0].reason == .outputLimitReached(MenuUnderstandingOutputLimit(field: .items, limit: MenuUnderstandingOutputLimits.items)))
        #expect(result.failures[0].retryability == .notRetryable)
        #expect(result.isPartialSuccess)
    }

    @Test func analyzeDoesNotMisapplyTheTenItemLimitGloballyWhenContextSplittingProducesMoreThanTenTotalItems() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in try jsonForSingleSourceDishes(parsePromptLines(prompt)) }
        // 全体（12 source）だけがcontext超過を予測される。分割後の各chunk（9 source）は上限未満に
        // 収まるため、そこでさらに分割が連鎖しない（overlapの累積でleafがcontext budgetを
        // 割り込まないよう、十分な余裕を持たせた閾値にする）。
        let contextMeasurer = FakeContextMeasurer(contextSize: 100) { prompt in
            parsePromptLines(prompt).count > 10 ? 1000 : 10
        }
        let parser = FoundationModelsMenuParser(runner: runner, availabilityProvider: FakeAvailabilityProvider(), contextMeasurer: contextMeasurer)
        let request = MenuUnderstandingRequest(segments: (1...12).map { segment(id: "s\($0)", rawText: "E\($0)") })

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 12)
        #expect(result.items.map(\.reference.ordinal) == Array(0...11))
        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == (1...12).map { ["s\($0)"] })
    }

    @Test func analyzeTerminatesFinitelyWithTypedFailuresWhenSaturationAndContextSplittingAlternateInTheSameRecursionTree() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count > 2 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let tokensPerSource = visible.count == 1 ? 10 : 5
            var items: [GeneralDishItem] = []
            for source in visible {
                for tokenIndex in 0..<tokensPerSource {
                    items.append(singleSourceItem(id: source.id, fragment: "\(source.id)T\(tokenIndex)"))
                }
            }
            return try jsonPayload(items: items)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let segments = (1...8).map { index in
            segment(id: "s\(index)", rawText: (0..<10).map { "s\(index)T\($0)" }.joined(separator: " "))
        }
        let request = MenuUnderstandingRequest(segments: segments)

        let result = await parser.analyze(request)

        // 8 sourceを1件ずつのcoreへ二分木で分割し尽くすため、内部ノード7＋leaf 8＝15回で終了する
        // （常に上限件数またはcontext超過を返すfakeでも無限retryしない）。
        #expect(runner.invocations.count == 15)
        #expect(result.failures.count == 8)
        for failure in result.failures {
            #expect(failure.retryability == .notRetryable)
            switch failure.reason {
            case .generationFailed(.contextWindowExceeded):
                break
            case .outputLimitReached(let limit) where limit.field == .items:
                break
            default:
                Issue.record("unexpected terminal failure reason: \(failure.reason)")
            }
        }
    }

    @Test func analyzeRejectsAnItemWhenSourceReferencesSaturatesAndKeepsAnItemWithAnOutputLimitFailureWhenASemanticFieldSaturates() async throws {
        let sourceIDs = ["s1", "s2", "s3", "s4"]
        let ingredientTokens = ["島豆腐", "豚肉", "卵", "もやし", "人参", "玉ねぎ"]
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            let saturatedSourceReferencesItem = GeneralDishItem(
                sourceReferences: sourceIDs.map { ($0, $0) },
                baseDishCandidates: ["結合料理"]
            )
            let saturatedIngredientsItem = singleSourceItem(
                id: "s5",
                fragment: "ゴーヤーチャンプルー " + ingredientTokens.joined(separator: " "),
                explicitIngredients: ingredientTokens
            )
            return try jsonPayload(items: [saturatedSourceReferencesItem, saturatedIngredientsItem])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        var segments = sourceIDs.map { segment(id: $0, rawText: $0) }
        segments.append(segment(id: "s5", rawText: "ゴーヤーチャンプルー " + ingredientTokens.joined(separator: " ")))
        let request = MenuUnderstandingRequest(segments: segments)

        let result = await parser.analyze(request)

        #expect(result.items.count == 1)
        #expect(result.items[0].reference.sourceReferences.map(\.sourceID.rawValue) == ["s5"])
        #expect(result.items[0].explicitIngredients == ingredientTokens)
        #expect(result.isPartialSuccess)

        let sourceReferencesFailure = try #require(result.failures.first { failure in
            if case .outputLimitReached(let limit) = failure.reason { return limit.field == .sourceReferences }
            return false
        })
        #expect(sourceReferencesFailure.scope == .sources(sourceIDs.map(MenuUnderstandingSourceID.init)))
        #expect(sourceReferencesFailure.retryability == .notRetryable)

        let ingredientsFailure = try #require(result.failures.first { failure in
            if case .outputLimitReached(let limit) = failure.reason { return limit.field == .explicitIngredients }
            return false
        })
        #expect(ingredientsFailure.scope == .item(result.items[0].reference))
        #expect(ingredientsFailure.retryability == .notRetryable)
    }

    @Test func analyzeRejectsRatherThanSilentlyDropsOrAcceptsMalformedSourceReferenceLists() async throws {
        let baseSegments = [segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー")]

        // empty sourceReferences
        do {
            let runner = FakeFoundationModelsRequestRunner()
            runner.resultProvider = { _, _, _ in
                try jsonPayloadWithRawSourceReferences(items: [(sourceReferences: [], baseDishCandidates: ["何か"])])
            }
            let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
            let result = await parser.analyze(MenuUnderstandingRequest(segments: baseSegments))
            #expect(result.items.isEmpty)
            #expect(result.failures == [
                MenuUnderstandingFailure(
                    scope: .sources([MenuUnderstandingSourceID("s1"), MenuUnderstandingSourceID("s2")]),
                    reason: .sourceMappingInvalid(.emptySourceReferences),
                    retryability: .notRetryable
                ),
            ])
        }

        // duplicate source reference within the same item
        do {
            let runner = FakeFoundationModelsRequestRunner()
            runner.resultProvider = { _, _, _ in
                try jsonPayloadWithRawSourceReferences(items: [
                    (sourceReferences: [("s1", "ラフテー"), ("s1", "ラフテー")], baseDishCandidates: ["ラフテー"]),
                ])
            }
            let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
            let result = await parser.analyze(MenuUnderstandingRequest(segments: baseSegments))
            #expect(result.items.isEmpty)
            #expect(result.failures == [
                MenuUnderstandingFailure(
                    scope: .sources([MenuUnderstandingSourceID("s1"), MenuUnderstandingSourceID("s2")]),
                    reason: .sourceMappingInvalid(.duplicateSourceReference(MenuUnderstandingSourceID("s1"))),
                    retryability: .notRetryable
                ),
            ])
        }

        // source references out of global source order
        do {
            let runner = FakeFoundationModelsRequestRunner()
            runner.resultProvider = { _, _, _ in
                try jsonPayloadWithRawSourceReferences(items: [
                    (sourceReferences: [("s2", "ミミガー"), ("s1", "ラフテー")], baseDishCandidates: ["結合"]),
                ])
            }
            let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
            let result = await parser.analyze(MenuUnderstandingRequest(segments: baseSegments))
            #expect(result.items.isEmpty)
            #expect(result.failures == [
                MenuUnderstandingFailure(
                    scope: .sources([MenuUnderstandingSourceID("s1"), MenuUnderstandingSourceID("s2")]),
                    reason: .sourceMappingInvalid(.sourceReferenceOrderInvalid),
                    retryability: .notRetryable
                ),
            ])
        }
    }

    // MARK: - analyze(): overlap and global-reconcile deduplication (FIX-005)

    @Test func analyzeResolvesATwoSourceBoundaryItemExactlyOnceWhenBothOverlappingChunksProposeTheIdenticalItem() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count >= 4 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let visibleIDs = Set(visible.map { $0.id })
            var items: [GeneralDishItem] = []
            if visibleIDs.isSuperset(of: ["s2", "s3"]) {
                let refs = ["s2", "s3"].map { id in (id: id, fragment: visible.first { $0.id == id }!.text) }
                items.append(GeneralDishItem(sourceReferences: refs, baseDishCandidates: ["結合料理"]))
            }
            for source in visible where source.id != "s2" && source.id != "s3" {
                items.append(singleSourceItem(id: source.id, fragment: source.text))
            }
            return try jsonPayload(items: items)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー"),
            segment(id: "s3", rawText: "テビチ"), segment(id: "s4", rawText: "ソーキ"),
        ])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 3)
        #expect(result.items.map(\.reference.ordinal) == [0, 1, 2])
        #expect(result.items[0].reference.sourceReferences.map(\.sourceID.rawValue) == ["s1"])
        #expect(result.items[1].reference.sourceReferences.map(\.sourceID.rawValue) == ["s2", "s3"])
        #expect(result.items[2].reference.sourceReferences.map(\.sourceID.rawValue) == ["s4"])
        // 1回目（全体・失敗）＋左右2つのsub-chunk＝3回。
        #expect(runner.invocations.count == 3)
    }

    @Test func analyzeResolvesATwoSourceItemAdjacentToASingletonCoreBoundary() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count >= 3 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let visibleIDs = Set(visible.map { $0.id })
            if visibleIDs.isSuperset(of: ["s1", "s2"]) {
                let refs = ["s1", "s2"].map { id in (id: id, fragment: visible.first { $0.id == id }!.text) }
                return try jsonPayload(items: [GeneralDishItem(sourceReferences: refs, baseDishCandidates: ["結合料理"])])
            }
            // 右chunk（s2, s3が見える）は、s1を参照できないため結合itemを提案せず、s3のみを返す。
            return try jsonForSingleSourceDishes(visible.filter { $0.id == "s3" })
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー"), segment(id: "s3", rawText: "テビチ"),
        ])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 2)
        #expect(result.items[0].reference.sourceReferences.map(\.sourceID.rawValue) == ["s1", "s2"])
        #expect(result.items[1].reference.sourceReferences.map(\.sourceID.rawValue) == ["s3"])
    }

    @Test func analyzeResolvesAThreeSourceSpanningItemExactlyOnceWhenOnlyOneChunkHasSufficientOverlapBudget() async throws {
        // sourceReferencesの上限は4件（`MenuUnderstandingOutputLimits.sourceReferences`）であり、
        // ちょうど4件へ到達したitemは常にoutput-limit failureとして扱う契約
        // （`analyzeRejectsAnItemWhenSourceReferencesSaturates...`で検証済み）なので、ここでは
        // 上限未満の3 source spanning itemで「十分なoverlap budgetがあれば成功する」ケースを検証する。
        let target: Set<String> = ["s3", "s4", "s5"]
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count >= 5 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let visibleIDs = Set(visible.map { $0.id })
            var items: [GeneralDishItem] = []
            if target.isSubset(of: visibleIDs) {
                let refs = ["s3", "s4", "s5"].map { id in (id: id, fragment: visible.first { $0.id == id }!.text) }
                items.append(GeneralDishItem(sourceReferences: refs, baseDishCandidates: ["3source結合料理"]))
            }
            for source in visible where !target.contains(source.id) {
                items.append(singleSourceItem(id: source.id, fragment: source.text))
            }
            return try jsonPayload(items: items)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "前菜"), segment(id: "s2", rawText: "ラフテー"), segment(id: "s3", rawText: "ミミガー"),
            segment(id: "s4", rawText: "テビチ"), segment(id: "s5", rawText: "ソーキ"),
        ])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 3)
        #expect(result.items[0].reference.sourceReferences.map(\.sourceID.rawValue) == ["s1"])
        #expect(result.items[1].reference.sourceReferences.map(\.sourceID.rawValue) == ["s2"])
        #expect(result.items[2].reference.sourceReferences.map(\.sourceID.rawValue) == ["s3", "s4", "s5"])
    }

    @Test func analyzeKeepsABoundaryItemThatOnlyOneOfTwoOverlappingChunksSuccessfullyValidatesWithoutAnOwnershipGuaranteeFromTheOtherChunk() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count >= 3 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let visibleIDs = Set(visible.map { $0.id })
            if visibleIDs == ["s1", "s2"] {
                // 左chunk（s1・s2が見える）は両方返す。s2の"所有者"は旧実装ではleftCore側だが、
                // その情報に依存せず、そのまま候補として提案する。
                return try jsonForSingleSourceDishes(visible)
            }
            // 右chunk（s2・s3が見える）はs2を返さない（何らかの理由で観測しなかった想定）。
            return try jsonForSingleSourceDishes(visible.filter { $0.id == "s3" })
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー"), segment(id: "s3", rawText: "テビチ"),
        ])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 3)
        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == [["s1"], ["s2"], ["s3"]])
        #expect(result.items.map(\.reference.ordinal) == [0, 1, 2])
    }

    @Test func analyzePreservesParentInheritedOverlapAcrossMultiLevelRecursionSoADeepBoundaryItemResolvesExactlyOnce() async throws {
        let targetIDs: Set<String> = ["s4", "s5", "s6"]
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count > 7 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let visibleIDs = Set(visible.map { $0.id })
            var items: [GeneralDishItem] = []
            if targetIDs.isSubset(of: visibleIDs) {
                let refs = ["s4", "s5", "s6"].map { id in (id: id, fragment: visible.first { $0.id == id }!.text) }
                items.append(GeneralDishItem(sourceReferences: refs, baseDishCandidates: ["深い境界結合料理"]))
            }
            for source in visible where !targetIDs.contains(source.id) {
                items.append(singleSourceItem(id: source.id, fragment: source.text))
            }
            return try jsonPayload(items: items)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: (1...11).map { segment(id: "s\($0)", rawText: "F\($0)") })

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 9)
        let ordinals = result.items.map(\.reference.ordinal)
        #expect(ordinals == Array(0..<result.items.count))
        #expect(result.items.contains { $0.reference.sourceReferences.map(\.sourceID.rawValue) == ["s4", "s5", "s6"] })
        for excludedIndex in [1, 2, 3, 7, 8, 9, 10, 11] {
            #expect(result.items.contains { $0.reference.sourceReferences.map(\.sourceID.rawValue) == ["s\(excludedIndex)"] })
        }
    }

    @Test func analyzeReturnsTypedBoundaryFailuresRatherThanAGuessedItemWhenNoChunkHasSufficientOverlapBudgetToValidateBothEnds() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count >= 5 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            if let s1 = visible.first(where: { $0.id == "s1" }) {
                return try jsonPayloadWithRawSourceReferences(items: [
                    (sourceReferences: [("s1", s1.text), ("s5", "s5の断片")], baseDishCandidates: ["幻の結合料理"]),
                ])
            }
            let s5 = visible.first { $0.id == "s5" }!
            return try jsonPayloadWithRawSourceReferences(items: [
                (sourceReferences: [("s1", "s1の断片"), ("s5", s5.text)], baseDishCandidates: ["幻の結合料理"]),
            ])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "前菜"), segment(id: "s2", rawText: "ラフテー"), segment(id: "s3", rawText: "ミミガー"),
            segment(id: "s4", rawText: "テビチ"), segment(id: "s5", rawText: "デザート"),
        ])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures.count == 2)
        for failure in result.failures {
            #expect(failure.reason == .sourceMappingInvalid(.chunkBoundaryUnresolved))
            #expect(failure.retryability == .notRetryable)
        }
        #expect(result.isTotalFailure)
    }

    @Test func analyzeReportsATypedConflictWithoutGuessingWhenOverlappingChunksProposeDifferingSemanticFieldsForTheSameBoundaryItem() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count >= 3 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let visibleIDs = Set(visible.map { $0.id })
            if visibleIDs == ["s1", "s2"] {
                return try jsonPayload(items: [
                    singleSourceItem(id: "s1", fragment: "ラフテー"),
                    singleSourceItem(id: "s2", fragment: "ミミガー", baseDishCandidates: ["ミミガーA"]),
                ])
            }
            return try jsonPayload(items: [
                singleSourceItem(id: "s2", fragment: "ミミガー", baseDishCandidates: ["ミミガーB"]),
                singleSourceItem(id: "s3", fragment: "テビチ"),
            ])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー"), segment(id: "s3", rawText: "テビチ"),
        ])

        let result = await parser.analyze(request)

        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == [["s1"], ["s3"]])
        #expect(result.failures == [
            MenuUnderstandingFailure(scope: .sources([MenuUnderstandingSourceID("s2")]), reason: .duplicateCandidateConflict, retryability: .notRetryable),
        ])
        #expect(result.isPartialSuccess)
    }

    @Test func analyzeKeepsTheValidCandidateWhenOnlyOneOfTwoOverlappingChunksValidatesTheSameBoundaryItem() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, prompt, _ in
            let visible = parsePromptLines(prompt)
            if visible.count >= 3 {
                throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too big"))
            }
            let visibleIDs = Set(visible.map { $0.id })
            if visibleIDs == ["s1", "s2"] {
                // 左chunkは、s2に加えて存在しないsourceを参照してしまい、mapping失敗する。
                return try jsonPayloadWithRawSourceReferences(items: [
                    (sourceReferences: [("s1", "ラフテー")], baseDishCandidates: ["ラフテー"]),
                    (sourceReferences: [("s2", "ミミガー"), ("s99", "捏造")], baseDishCandidates: ["ミミガー"]),
                ])
            }
            return try jsonForSingleSourceDishes(visible)
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ミミガー"), segment(id: "s3", rawText: "テビチ"),
        ])

        let result = await parser.analyze(request)

        #expect(result.items.map { $0.reference.sourceReferences.map(\.sourceID.rawValue) } == [["s1"], ["s2"], ["s3"]])
        #expect(result.failures.contains {
            $0.reason == .sourceMappingInvalid(.unknownSourceID(MenuUnderstandingSourceID("s99")))
        })
        #expect(result.isPartialSuccess)
    }

    @Test func analyzeRejectsRatherThanSilentlyDedupsTwoOccurrencesOfTheIdenticalDishNameWithinTheSameSource() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try jsonPayload(items: [
                singleSourceItem(id: "s1", fragment: "唐揚げ定食"),
                singleSourceItem(id: "s1", fragment: "唐揚げ定食"),
            ])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "唐揚げ定食 唐揚げ定食")])

        let result = await parser.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures.count == 2)
        for failure in result.failures {
            #expect(failure.reason == .sourceMappingInvalid(.ambiguousFragmentOccurrence(MenuUnderstandingSourceID("s1"))))
            #expect(failure.retryability == .notRetryable)
        }
    }

    @Test func analyzeAssignsContinuousOrdinalsAfterReconcileWithItemScopedFailuresReferencingTheFinalItem() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try jsonPayload(items: [
                singleSourceItem(id: "s1", fragment: "ラフテー"),
                singleSourceItem(id: "s2", fragment: "ゴーヤーチャンプルー", explicitIngredients: ["ゴーヤー", "捏造食材"]),
            ])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1", rawText: "ラフテー"), segment(id: "s2", rawText: "ゴーヤーチャンプルー")])

        let result = await parser.analyze(request)

        #expect(result.items.map(\.reference.ordinal) == [0, 1])
        #expect(result.items[1].explicitIngredients == ["ゴーヤー"])
        #expect(result.failures.count == 1)
        #expect(result.failures[0].scope == .item(result.items[1].reference))
        #expect(result.failures[0].reason == .itemValidationFailed(.explicitIngredientsNotInSource(["捏造食材"])))
    }

    // MARK: - analyze(): rawText / analysisText provenance contract (FIX-005)

    @Test func analyzeAcceptsARawFragmentThatDiffersFromTheAnalysisTextWhileOriginalTextStaysRaw() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try jsonPayload(items: [
                singleSourceItem(id: "s1", fragment: "ゴーヤー・チャンプルー", baseDishCandidates: ["ゴーヤーチャンプルー"]),
            ])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ゴーヤー・チャンプルー 1,280円", analysisText: "ゴーヤーチャンプルー"),
        ])

        let result = await parser.analyze(request)

        #expect(result.failures.isEmpty)
        #expect(result.items.count == 1)
        #expect(result.items[0].reference.originalText == "ゴーヤー・チャンプルー")
        #expect(result.items[0].reference.sourceReferences == [
            MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "ゴーヤー・チャンプルー"),
        ])
        #expect(result.items[0].baseDishCandidates == ["ゴーヤーチャンプルー"])
    }

    @Test func analyzeRejectsAFragmentThatMatchesOnlyTheAnalysisTextAndNotTheRawText() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try jsonPayload(items: [singleSourceItem(id: "s1", fragment: "ゴーヤーチャンプルー")])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ゴーヤー・チャンプルー 1,280円", analysisText: "ゴーヤーチャンプルー"),
        ])

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

    @Test func analyzeStrictlyValidatesFragmentsAgainstRawTextAcrossNormalizationAndOcrCorrectionScenarios() async throws {
        struct Scenario {
            let name: String
            let rawText: String
            let analysisText: String
            let fragment: String
            let expectSuccess: Bool
        }
        let scenarios = [
            Scenario(name: "末尾価格除去", rawText: "ラフテー 980円", analysisText: "ラフテー", fragment: "ラフテー", expectSuccess: true),
            Scenario(name: "文字列途中の価格除去", rawText: "ラフテー 980円 セット", analysisText: "ラフテー セット", fragment: "ラフテー セット", expectSuccess: false),
            Scenario(name: "記号・空白正規化", rawText: "ラフテー　（大）", analysisText: "ラフテー(大)", fragment: "ラフテー(大)", expectSuccess: false),
            Scenario(name: "全半角変換", rawText: "ラフテー", analysisText: "ﾗﾌﾃｰ", fragment: "ﾗﾌﾃｰ", expectSuccess: false),
            Scenario(name: "OCR補正", rawText: "ラフテ一", analysisText: "ラフテー", fragment: "ラフテー", expectSuccess: false),
        ]

        for scenario in scenarios {
            let runner = FakeFoundationModelsRequestRunner()
            runner.resultProvider = { _, _, _ in try jsonPayload(items: [singleSourceItem(id: "s1", fragment: scenario.fragment)]) }
            let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
            let request = MenuUnderstandingRequest(segments: [
                segment(id: "s1", rawText: scenario.rawText, analysisText: scenario.analysisText),
            ])

            let result = await parser.analyze(request)

            if scenario.expectSuccess {
                #expect(result.failures.isEmpty, "scenario: \(scenario.name)")
                #expect(result.items.count == 1, "scenario: \(scenario.name)")
            } else {
                #expect(result.items.isEmpty, "scenario: \(scenario.name)")
                #expect(result.failures == [
                    MenuUnderstandingFailure(
                        scope: .sources([MenuUnderstandingSourceID("s1")]),
                        reason: .sourceMappingInvalid(.sourceFragmentMismatch(MenuUnderstandingSourceID("s1"))),
                        retryability: .notRetryable
                    ),
                ], "scenario: \(scenario.name)")
            }
        }
    }

    @Test func analyzeRejectsAnAnalysisNormalizedExplicitIngredientNotPresentAsARawSurfaceForm() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try jsonPayload(items: [
                singleSourceItem(id: "s1", fragment: "ゴーヤーチャンプルー", explicitIngredients: ["ゴーヤー", "苦瓜"]),
            ])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1", rawText: "ゴーヤーチャンプルー", analysisText: "苦瓜チャンプルー"),
        ])

        let result = await parser.analyze(request)

        #expect(result.items.count == 1)
        #expect(result.items[0].explicitIngredients == ["ゴーヤー"])
        #expect(result.failures == [
            MenuUnderstandingFailure(
                scope: .item(result.items[0].reference),
                reason: .itemValidationFailed(.explicitIngredientsNotInSource(["苦瓜"])),
                retryability: .notRetryable
            ),
        ])
    }

    @Test func analyzeRejectsAnExplicitIngredientFabricatedByConcatenatingFragmentsAcrossASourceBoundary() async throws {
        let runner = FakeFoundationModelsRequestRunner()
        runner.resultProvider = { _, _, _ in
            try jsonPayload(items: [
                GeneralDishItem(
                    sourceReferences: [("sA", "炙り島豚"), ("sB", "肉のせ沖縄そば")],
                    baseDishCandidates: ["沖縄そば"],
                    explicitIngredients: ["豚肉"]
                ),
            ])
        }
        let parser = makeParser(runner: runner, availabilityProvider: FakeAvailabilityProvider())
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "sA", rawText: "炙り島豚"), segment(id: "sB", rawText: "肉のせ沖縄そば"),
        ])

        let result = await parser.analyze(request)

        #expect(result.items.count == 1)
        #expect(result.items[0].explicitIngredients.isEmpty)
        #expect(result.failures == [
            MenuUnderstandingFailure(
                scope: .item(result.items[0].reference),
                reason: .itemValidationFailed(.explicitIngredientsNotInSource(["豚肉"])),
                retryability: .notRetryable
            ),
        ])
    }

    // MARK: - Helpers

    private func segment(id: String, rawText: String = "raw", analysisText: String? = nil) -> MenuUnderstandingSourceSegment {
        MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID(id), rawText: rawText, confidence: 0.9, boundingBox: .zero, analysisText: analysisText)
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

/// FIX-005以降、`MenuUnderstandingPrompt.prompt(for:)`はsource一覧をJSON配列（`sourceID`・
/// `rawText`・`analysisText`）で表す。chunking関連のfake runnerが、実際に渡されたsegment集合に
/// 応じて応答内容を変えるために、そのJSONを`(id, rawText)`の配列へ分解する。
private func parsePromptLines(_ prompt: String) -> [(id: String, text: String)] {
    guard let data = prompt.data(using: .utf8),
          let entries = try? JSONDecoder().decode([PromptSourceEntryForTests].self, from: data) else {
        return []
    }
    return entries.map { ($0.sourceID, $0.rawText) }
}

private struct PromptSourceEntryForTests: Decodable {
    let sourceID: String
    let rawText: String
    let analysisText: String?
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

// MARK: - General-purpose DTO builders for FIX-005 tests (multi-source items, custom field arrays)

private struct GeneralDishItem {
    let sourceReferences: [(id: String, fragment: String)]
    var baseDishCandidates: [String] = []
    var explicitIngredients: [String] = []
    var preparationMethods: [String] = []
    var modifiers: [String] = []
    var unknownTerms: [String] = []
}

/// 単一sourceのitemを組み立てる。
private func singleSourceItem(
    id: String,
    fragment: String,
    baseDishCandidates: [String]? = nil,
    explicitIngredients: [String] = [],
    preparationMethods: [String] = [],
    modifiers: [String] = [],
    unknownTerms: [String] = []
) -> GeneralDishItem {
    GeneralDishItem(
        sourceReferences: [(id: id, fragment: fragment)],
        baseDishCandidates: baseDishCandidates ?? [fragment],
        explicitIngredients: explicitIngredients,
        preparationMethods: preparationMethods,
        modifiers: modifiers,
        unknownTerms: unknownTerms
    )
}

private func jsonPayload(items: [GeneralDishItem]) throws -> GeneratedContent {
    let payload = SimpleDishPayload(items: items.map { item in
        SimpleDishPayload.Item(
            sourceReferences: item.sourceReferences.map { SimpleDishPayload.Item.Reference(sourceID: $0.id, fragment: $0.fragment) },
            baseDishCandidates: item.baseDishCandidates,
            explicitIngredients: item.explicitIngredients,
            preparationMethods: item.preparationMethods,
            modifiers: item.modifiers,
            unknownTerms: item.unknownTerms
        )
    })
    let data = try JSONEncoder().encode(payload)
    return try GeneratedContent(json: String(data: data, encoding: .utf8)!)
}

private func jsonPayloadWithRawSourceReferences(
    items: [(sourceReferences: [(sourceID: String, fragment: String)], baseDishCandidates: [String])]
) throws -> GeneratedContent {
    let payload = SimpleDishPayload(items: items.map { item in
        SimpleDishPayload.Item(
            sourceReferences: item.sourceReferences.map { SimpleDishPayload.Item.Reference(sourceID: $0.sourceID, fragment: $0.fragment) },
            baseDishCandidates: item.baseDishCandidates,
            explicitIngredients: [],
            preparationMethods: [],
            modifiers: [],
            unknownTerms: []
        )
    })
    let data = try JSONEncoder().encode(payload)
    return try GeneratedContent(json: String(data: data, encoding: .utf8)!)
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
