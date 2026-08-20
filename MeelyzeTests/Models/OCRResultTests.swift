import Testing
import Foundation
@testable import Meelyze

struct OCRResultTests {

    @Test func observationHoldsTextConfidenceAndBoundingBoxTogether() {
        let observation = RecognizedTextObservation(
            text: "唐揚げ定食",
            confidence: 0.92,
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05)
        )

        #expect(observation.text == "唐揚げ定食")
        #expect(observation.confidence == 0.92)
        #expect(observation.boundingBox == CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05))
    }

    @Test func preservesOneToOneCorrespondenceBetweenTextAndBoundingBoxAcrossMultipleObservations() {
        let first = RecognizedTextObservation(
            text: "唐揚げ定食",
            confidence: 0.92,
            boundingBox: CGRect(x: 0, y: 0, width: 0.2, height: 0.1)
        )
        let second = RecognizedTextObservation(
            text: "味噌汁",
            confidence: 0.4,
            boundingBox: CGRect(x: 0, y: 0.2, width: 0.2, height: 0.1)
        )

        let result = OCRResult(observations: [first, second])

        #expect(result.observations[0].text == "唐揚げ定食")
        #expect(result.observations[0].boundingBox == first.boundingBox)
        #expect(result.observations[1].text == "味噌汁")
        #expect(result.observations[1].boundingBox == second.boundingBox)
    }

    @Test func emptyResultRepresentsNoTextDetected() {
        let result = OCRResult(observations: [])

        #expect(result.isEmpty == true)
    }

    @Test func lowConfidencePartialRecognitionIsNotTreatedAsEmpty() {
        let lowConfidence = RecognizedTextObservation(text: "?", confidence: 0.1, boundingBox: .zero)

        let result = OCRResult(observations: [lowConfidence])

        #expect(result.isEmpty == false)
    }

    @Test func equatableComparesByObservationContent() {
        let a = OCRResult(observations: [RecognizedTextObservation(text: "A", confidence: 0.5, boundingBox: .zero)])
        let b = OCRResult(observations: [RecognizedTextObservation(text: "A", confidence: 0.5, boundingBox: .zero)])
        let c = OCRResult(observations: [])

        #expect(a == b)
        #expect(a != c)
    }
}
