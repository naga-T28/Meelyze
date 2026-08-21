import Testing
import Foundation
@testable import Meelyze

struct MenuUnderstandingModelsTests {

    // MARK: - Source ID validation

    @Test func validateSourceIDsReturnsNilForUniqueNonEmptyIDs() {
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1"),
            segment(id: "s2"),
        ])

        #expect(request.validateSourceIDs() == nil)
    }

    @Test func validateSourceIDsDetectsEmptyID() {
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1"),
            segment(id: ""),
        ])

        #expect(request.validateSourceIDs() == .emptySourceID(index: 1))
    }

    @Test func validateSourceIDsDetectsDuplicateID() {
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1"),
            segment(id: "s2"),
            segment(id: "s1"),
        ])

        #expect(request.validateSourceIDs() == .duplicateSourceID(MenuUnderstandingSourceID("s1")))
    }

    @Test func requestPreservesCallerProvidedSegmentOrderWithoutReordering() {
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "c"),
            segment(id: "a"),
            segment(id: "b"),
        ])

        #expect(request.segments.map(\.id.rawValue) == ["c", "a", "b"])
    }

    // MARK: - analysisText does not affect rawText/originalText

    @Test func settingAnalysisTextDoesNotChangeRawTextOrOtherOCRMetadata() {
        var segment = segment(id: "s1", rawText: "唐揚げ定食", confidence: 0.8, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))
        segment.analysisText = "唐揚げ定食（前処理後）"

        #expect(segment.rawText == "唐揚げ定食")
        #expect(segment.confidence == 0.8)
        #expect(segment.boundingBox == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - MenuUnderstandingItemReference / originalText construction

    @Test func itemReferenceConstructsOriginalTextFromSingleSourceFragment() {
        let reference = MenuUnderstandingItemReference(
            ordinal: 0,
            sourceReferences: [
                MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "ラフテー"),
            ],
            separator: "\n"
        )

        #expect(reference.originalText == "ラフテー")
    }

    @Test func itemReferenceConstructsOriginalTextDeterministicallyFromMultipleSourceFragmentsInOrder() {
        let reference = MenuUnderstandingItemReference(
            ordinal: 0,
            sourceReferences: [
                MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "島豚の炙り"),
                MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s2"), rawFragment: "沖縄そば"),
            ],
            separator: "\n"
        )

        #expect(reference.originalText == "島豚の炙り\n沖縄そば")
        #expect(reference.sourceReferences.map(\.sourceID.rawValue) == ["s1", "s2"])
    }

    @Test func itemReferenceRespectsRequestDefinedSeparator() {
        let reference = MenuUnderstandingItemReference(
            ordinal: 0,
            sourceReferences: [
                MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "A"),
                MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s2"), rawFragment: "B"),
            ],
            separator: " / "
        )

        #expect(reference.originalText == "A / B")
    }

    // MARK: - MenuUnderstandingFailure.invalidInput

    @Test func invalidInputFailureIsRequestScopedAndNotRetryable() {
        let failure = MenuUnderstandingFailure.invalidInput(.emptySourceID(index: 0))

        #expect(failure.scope == .request)
        #expect(failure.reason == .invalidInput(.emptySourceID(index: 0)))
        #expect(failure.retryability == .notRetryable)
    }

    // MARK: - MenuUnderstandingResult: distinguishing total failure / partial success / total success

    @Test func resultWithItemsAndNoFailuresIsNeitherTotalFailureNorPartialSuccess() {
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])
        let result = MenuUnderstandingResult(
            request: request,
            items: [parsedItem(ordinal: 0, sourceID: "s1", fragment: "ラフテー")],
            availability: .available,
            failures: []
        )

        #expect(result.isTotalFailure == false)
        #expect(result.isPartialSuccess == false)
    }

    @Test func resultWithOnlyFailuresIsTotalFailure() {
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])
        let result = MenuUnderstandingResult(
            request: request,
            items: [],
            availability: .unavailable(.modelNotReady),
            failures: [.invalidInput(.emptySourceID(index: 0))]
        )

        #expect(result.isTotalFailure == true)
        #expect(result.isPartialSuccess == false)
    }

    @Test func resultWithItemsAndFailuresIsPartialSuccessAndNotTotalFailure() {
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1"), segment(id: "s2")])
        let result = MenuUnderstandingResult(
            request: request,
            items: [parsedItem(ordinal: 0, sourceID: "s1", fragment: "ラフテー")],
            availability: .available,
            failures: [
                MenuUnderstandingFailure(
                    scope: .sources([MenuUnderstandingSourceID("s2")]),
                    reason: .generationFailed(.unknown),
                    retryability: .retryable
                ),
            ]
        )

        #expect(result.isPartialSuccess == true)
        #expect(result.isTotalFailure == false)
        #expect(result.items.count == 1)
    }

    @Test func emptyItemsWithEmptyFailuresIsNotReportedAsAnyFailureCategory() {
        // 空のitemsだけを安全・該当なし・成功として扱わない設計の一部として、
        // items・failuresが両方空の状態は「全失敗」でも「部分成功」でもないことを確認する。
        let request = MenuUnderstandingRequest(segments: [])
        let result = MenuUnderstandingResult(
            request: request,
            items: [],
            availability: .available,
            failures: []
        )

        #expect(result.isTotalFailure == false)
        #expect(result.isPartialSuccess == false)
        #expect(result.items.isEmpty)
    }

    // MARK: - Failure scope carries an item reference only when boundaries were resolved

    @Test func itemScopedFailureCarriesTheResolvedItemReference() {
        let itemReference = MenuUnderstandingItemReference(
            ordinal: 0,
            sourceReferences: [MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID("s1"), rawFragment: "ゴーヤーチャンプルー")],
            separator: "\n"
        )
        let failure = MenuUnderstandingFailure(
            scope: .item(itemReference),
            reason: .generationFailed(.unknown),
            retryability: .notRetryable
        )

        guard case let .item(reference) = failure.scope else {
            Issue.record("Expected .item scope")
            return
        }
        #expect(reference == itemReference)
    }

    // MARK: - Helpers

    private func segment(
        id: String,
        rawText: String = "raw",
        confidence: Float = 0.9,
        boundingBox: CGRect = .zero
    ) -> MenuUnderstandingSourceSegment {
        MenuUnderstandingSourceSegment(
            id: MenuUnderstandingSourceID(id),
            rawText: rawText,
            confidence: confidence,
            boundingBox: boundingBox
        )
    }

    private func parsedItem(ordinal: Int, sourceID: String, fragment: String) -> ParsedMenuItem {
        ParsedMenuItem(
            reference: MenuUnderstandingItemReference(
                ordinal: ordinal,
                sourceReferences: [MenuUnderstandingSourceReference(sourceID: MenuUnderstandingSourceID(sourceID), rawFragment: fragment)],
                separator: "\n"
            ),
            baseDishCandidates: [fragment],
            explicitIngredients: [],
            preparationMethods: [],
            modifiers: [],
            unknownTerms: []
        )
    }
}
