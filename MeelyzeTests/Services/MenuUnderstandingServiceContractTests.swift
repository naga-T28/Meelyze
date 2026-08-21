import Testing
import Foundation
@testable import Meelyze

/// `MenuUnderstandingService`がFoundation Modelsなしで準拠・差し替え可能であることを示す
/// fake実装。TASK-025以降の決定的なUnit Test基盤として、Protocol契約だけをテストする。
private actor FakeMenuUnderstandingService: MenuUnderstandingService {
    private let stubbedAvailability: MenuUnderstandingAvailability
    private let itemsBySourceID: [String: ParsedMenuItem]

    init(availability: MenuUnderstandingAvailability, itemsBySourceID: [String: ParsedMenuItem] = [:]) {
        self.stubbedAvailability = availability
        self.itemsBySourceID = itemsBySourceID
    }

    func availability() async -> MenuUnderstandingAvailability {
        stubbedAvailability
    }

    func analyze(_ request: MenuUnderstandingRequest) async -> MenuUnderstandingResult {
        if let invalidReason = request.validateSourceIDs() {
            return MenuUnderstandingResult(
                request: request,
                items: [],
                availability: stubbedAvailability,
                failures: [.invalidInput(invalidReason)]
            )
        }

        if case .unavailable(let reason) = stubbedAvailability {
            return MenuUnderstandingResult(
                request: request,
                items: [],
                availability: stubbedAvailability,
                failures: [
                    MenuUnderstandingFailure(scope: .request, reason: .modelUnavailable(reason), retryability: .notRetryable),
                ]
            )
        }

        var items: [ParsedMenuItem] = []
        var failures: [MenuUnderstandingFailure] = []
        for segment in request.segments {
            if let item = itemsBySourceID[segment.id.rawValue] {
                items.append(item)
            } else {
                failures.append(
                    MenuUnderstandingFailure(
                        scope: .sources([segment.id]),
                        reason: .generationFailed(.unknown),
                        retryability: .retryable
                    )
                )
            }
        }
        return MenuUnderstandingResult(request: request, items: items, availability: stubbedAvailability, failures: failures)
    }
}

struct MenuUnderstandingServiceContractTests {

    @Test func fakeServiceReportsStubbedAvailabilityWithoutCaching() async {
        let service = FakeMenuUnderstandingService(availability: .unavailable(.appleIntelligenceNotEnabled))

        let availability = await service.availability()

        #expect(availability == .unavailable(.appleIntelligenceNotEnabled))
    }

    @Test func analyzeReturnsRequestScopedInvalidInputFailureWithoutFabricatingItems() async {
        let service = FakeMenuUnderstandingService(availability: .available)
        let request = MenuUnderstandingRequest(segments: [
            segment(id: "s1"),
            segment(id: "s1"),
        ])

        let result = await service.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.failures == [.invalidInput(.duplicateSourceID(MenuUnderstandingSourceID("s1")))])
        #expect(result.isTotalFailure == true)
    }

    @Test func analyzeReturnsAllSuccessfulItemsWhenEverySourceResolves() async {
        let itemS1 = item(sourceID: "s1", fragment: "ラフテー")
        let itemS2 = item(sourceID: "s2", fragment: "ソーキそば")
        let service = FakeMenuUnderstandingService(
            availability: .available,
            itemsBySourceID: ["s1": itemS1, "s2": itemS2]
        )
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1"), segment(id: "s2")])

        let result = await service.analyze(request)

        #expect(result.items == [itemS1, itemS2])
        #expect(result.failures.isEmpty)
        #expect(result.isTotalFailure == false)
        #expect(result.isPartialSuccess == false)
    }

    @Test func analyzeKeepsSuccessfulItemsWhenOneSourceFailsPartialSuccess() async {
        let itemS1 = item(sourceID: "s1", fragment: "ラフテー")
        let service = FakeMenuUnderstandingService(
            availability: .available,
            itemsBySourceID: ["s1": itemS1]
        )
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1"), segment(id: "s2")])

        let result = await service.analyze(request)

        #expect(result.items == [itemS1])
        #expect(result.failures == [
            MenuUnderstandingFailure(scope: .sources([MenuUnderstandingSourceID("s2")]), reason: .generationFailed(.unknown), retryability: .retryable),
        ])
        #expect(result.isPartialSuccess == true)
    }

    @Test func analyzeReturnsTotalFailureWithoutItemsWhenModelIsUnavailable() async {
        let service = FakeMenuUnderstandingService(availability: .unavailable(.deviceNotEligible))
        let request = MenuUnderstandingRequest(segments: [segment(id: "s1")])

        let result = await service.analyze(request)

        #expect(result.items.isEmpty)
        #expect(result.availability == .unavailable(.deviceNotEligible))
        #expect(result.isTotalFailure == true)
    }

    // MARK: - Helpers

    private func segment(id: String) -> MenuUnderstandingSourceSegment {
        MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID(id), rawText: id, confidence: 0.9, boundingBox: .zero)
    }

    private func item(sourceID: String, fragment: String) -> ParsedMenuItem {
        ParsedMenuItem(
            reference: MenuUnderstandingItemReference(
                ordinal: 0,
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
