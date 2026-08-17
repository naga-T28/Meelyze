import Testing
import Foundation
@testable import Meelyze

struct VisionOCRServiceTests {

    @Test func recognizesMultipleObservationsPreservingTextConfidenceAndBoundingBoxCorrespondence() async throws {
        let first = RecognizedTextObservation(
            text: "唐揚げ定食",
            confidence: 0.92,
            boundingBox: CGRect(x: 0, y: 0, width: 0.3, height: 0.1)
        )
        let second = RecognizedTextObservation(
            text: "味噌汁",
            confidence: 0.35,
            boundingBox: CGRect(x: 0, y: 0.2, width: 0.2, height: 0.08)
        )
        let service = VisionOCRService { _ in [first, second] }

        let result = try await service.recognizeText(in: Data([0x01]))

        #expect(result.observations == [first, second])
        #expect(result.isEmpty == false)
    }

    @Test func lowConfidencePartialRecognitionIsNotTreatedAsFailure() async throws {
        let lowConfidence = RecognizedTextObservation(text: "?", confidence: 0.05, boundingBox: .zero)
        let service = VisionOCRService { _ in [lowConfidence] }

        let result = try await service.recognizeText(in: Data([0x01]))

        #expect(result.isEmpty == false)
        #expect(result.observations == [lowConfidence])
    }

    @Test func noObservationsReturnsEmptyResultRatherThanThrowing() async throws {
        let service = VisionOCRService { _ in [] }

        let result = try await service.recognizeText(in: Data([0x01]))

        #expect(result.isEmpty == true)
    }

    @Test func invalidImageDataErrorIsPropagatedAsIs() async {
        let service = VisionOCRService { _ in throw OCRError.invalidImageData }

        do {
            _ = try await service.recognizeText(in: Data())
            Issue.record("Expected OCRError.invalidImageData to be thrown")
        } catch {
            #expect(error as? OCRError == .invalidImageData)
        }
    }

    @Test func unexpectedFailureIsWrappedAsRecognitionRequestFailed() async {
        struct SomeOtherError: Error {}
        let service = VisionOCRService { _ in throw SomeOtherError() }

        do {
            _ = try await service.recognizeText(in: Data([0x01]))
            Issue.record("Expected OCRError.recognitionRequestFailed to be thrown")
        } catch {
            #expect(error as? OCRError == .recognitionRequestFailed)
        }
    }

    @Test func mapExtractsTopCandidateTextConfidenceAndBoundingBoxTogether() {
        let source = FakeVisionTextObservation(
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05),
            topRecognizedCandidate: (text: "唐揚げ定食", confidence: 0.92)
        )

        let mapped = VisionOCRService.map([source])

        #expect(mapped == [RecognizedTextObservation(text: "唐揚げ定食", confidence: 0.92, boundingBox: source.boundingBox)])
    }

    @Test func mapExcludesObservationsWithoutATopCandidate() {
        let noCandidate = FakeVisionTextObservation(boundingBox: .zero, topRecognizedCandidate: nil)

        let mapped = VisionOCRService.map([noCandidate])

        #expect(mapped.isEmpty)
    }

    @Test func mapPreservesOneToOneOrderingAcrossMultipleObservations() {
        let first = FakeVisionTextObservation(
            boundingBox: CGRect(x: 0, y: 0, width: 0.2, height: 0.1),
            topRecognizedCandidate: (text: "唐揚げ定食", confidence: 0.92)
        )
        let second = FakeVisionTextObservation(
            boundingBox: CGRect(x: 0, y: 0.2, width: 0.2, height: 0.1),
            topRecognizedCandidate: (text: "味噌汁", confidence: 0.4)
        )

        let mapped = VisionOCRService.map([first, second])

        #expect(mapped[0].text == "唐揚げ定食")
        #expect(mapped[0].boundingBox == first.boundingBox)
        #expect(mapped[1].text == "味噌汁")
        #expect(mapped[1].boundingBox == second.boundingBox)
    }
}

private struct FakeVisionTextObservation: VisionTextObservationConvertible {
    let boundingBox: CGRect
    let topRecognizedCandidate: (text: String, confidence: Float)?
}
