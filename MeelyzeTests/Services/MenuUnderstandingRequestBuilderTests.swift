import Testing
import Foundation
@testable import Meelyze

struct MenuUnderstandingRequestBuilderTests {
    @Test func buildsSegmentsInReadingOrderPreservingTextConfidenceAndBoundingBox() {
        // `firstBox`は`secondBox`より下（y値が小さい。Visionの座標系は原点左下）に位置するため、
        // 読み取り順（上→下）では`secondBox`（ラフテー）が先になる。FIX-010: `build(from:)`は
        // Vision観測順ではなく`OCRReadingOrderSorter`による読み取り順でsegmentを構築するため、
        // 入力順（沖縄そばが先）とsegment順は一致しない。
        let builder = MenuUnderstandingRequestBuilder()
        let firstBox = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        let secondBox = CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.1)
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: firstBox),
            RecognizedTextObservation(text: "ラフテー", confidence: 0.8, boundingBox: secondBox)
        ])

        let output = builder.build(from: ocrResult)

        #expect(output.request.segments.count == 2)
        #expect(output.request.segments[0].rawText == "ラフテー")
        #expect(output.request.segments[0].confidence == 0.8)
        #expect(output.request.segments[0].boundingBox == secondBox)
        #expect(output.request.segments[0].analysisText == nil)
        #expect(output.request.segments[1].rawText == "沖縄そば")
        #expect(output.request.segments[1].confidence == 0.9)
        #expect(output.request.segments[1].boundingBox == firstBox)
    }

    @Test func generatesUniqueNonEmptySourceIDsThatPassValidation() {
        let builder = MenuUnderstandingRequestBuilder()
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: .zero),
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.85, boundingBox: .zero)
        ])

        let output = builder.build(from: ocrResult)

        #expect(output.request.validateSourceIDs() == nil)
        let ids = output.request.segments.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
    }

    @Test func sourceMapRecoversOriginalObservationByID() throws {
        let builder = MenuUnderstandingRequestBuilder()
        let box = CGRect(x: 0.05, y: 0.15, width: 0.2, height: 0.05)
        let observation = RecognizedTextObservation(text: "ゴーヤーチャンプルー", confidence: 0.72, boundingBox: box)
        let ocrResult = OCRResult(observations: [observation])

        let output = builder.build(from: ocrResult)

        let id = try #require(output.request.segments.first?.id)
        let recovered = try #require(output.sourceMap[id])
        #expect(recovered == observation)
        #expect(recovered.boundingBox == box)
    }

    @Test func excludesWhitespaceOnlyObservationsFromSegmentsAndSourceMap() {
        let builder = MenuUnderstandingRequestBuilder()
        let ocrResult = OCRResult(observations: [
            RecognizedTextObservation(text: "沖縄そば", confidence: 0.9, boundingBox: .zero),
            RecognizedTextObservation(text: "   ", confidence: 0.5, boundingBox: .zero),
            RecognizedTextObservation(text: "", confidence: 0.4, boundingBox: .zero)
        ])

        let output = builder.build(from: ocrResult)

        #expect(output.request.segments.count == 1)
        #expect(output.request.segments[0].rawText == "沖縄そば")
        #expect(output.sourceMap.count == 1)
    }

    @Test func emptyOCRResultProducesEmptyRequestWithoutCrashing() {
        let builder = MenuUnderstandingRequestBuilder()

        let output = builder.build(from: OCRResult(observations: []))

        #expect(output.request.segments.isEmpty)
        #expect(output.sourceMap.isEmpty)
        #expect(output.request.validateSourceIDs() == nil)
    }
}
