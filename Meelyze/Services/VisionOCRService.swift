import Vision
import ImageIO
import Foundation

/// `OCRService`のApple Vision実装。`VNRecognizeTextRequest`を用いて画像から文字列を認識する。
/// 認識言語ヒントは日本語（`ja-JP`）優先に固定し、誤認識を抑制する（FR-1.2）。料理名の意味解釈・
/// 価格や店名等の除外は行わない（`docs/technology-selection.md`§5、FR-1.3は将来のNormalization/
/// Menu Understanding関連Issueの範囲）。
///
/// Vision呼び出し自体（`performRequest`）を注入可能にしている。`VNRecognizedTextObservation`
/// `VNRecognizedText`には公開イニシャライザがなく実行環境なしに構築できないため、実行環境依存を
/// 減らして0件抽出・処理失敗時の`OCRResult`/`OCRError`表現を検証できるようにするための設計
/// （`task/TASK-021-vision-ocr-service.md`）。
struct VisionOCRService: OCRService {
    typealias RecognitionHandler = @Sendable (Data) throws -> [RecognizedTextObservation]

    private let performRequest: RecognitionHandler

    init() {
        self.init(performRequest: Self.performVisionRequest)
    }

    /// テスト用: Vision呼び出しを差し替えられるinit。
    init(performRequest: @escaping RecognitionHandler) {
        self.performRequest = performRequest
    }

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        do {
            let performRequest = self.performRequest
            let observations = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<[RecognizedTextObservation], Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try performRequest(imageData))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            return OCRResult(observations: observations)
        } catch let error as OCRError {
            throw error
        } catch {
            throw OCRError.recognitionRequestFailed
        }
    }

    private static let performVisionRequest: RecognitionHandler = { imageData in
        guard
            let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw OCRError.invalidImageData
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ja-JP"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return VisionOCRService.map(request.results ?? [])
    }

    /// `VNRecognizedTextObservation`（またはテスト用スタブ）を`RecognizedTextObservation`へ変換する。
    /// 上位候補が取得できない観測結果は除外し、取得できたものは文字列・Confidence・Bounding Boxの
    /// 対応関係を1件ずつ保ったまま変換する。
    static func map(_ observations: [VisionTextObservationConvertible]) -> [RecognizedTextObservation] {
        observations.compactMap { observation in
            guard let candidate = observation.topRecognizedCandidate else { return nil }
            return RecognizedTextObservation(
                text: candidate.text,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
}

/// `VNRecognizedTextObservation`から`RecognizedTextObservation`への変換に必要な最小限の情報を
/// 抽象化するProtocol。Visionの`VNRecognizedTextObservation` `VNRecognizedText`には公開イニシャライザが
/// ないため、テストではVision型の代わりにこのProtocolに準拠したスタブを使ってマッピングロジック
/// （Confidence・Bounding Boxの対応関係、候補なし時の除外）を検証する。
protocol VisionTextObservationConvertible {
    var boundingBox: CGRect { get }
    var topRecognizedCandidate: (text: String, confidence: Float)? { get }
}

extension VNRecognizedTextObservation: VisionTextObservationConvertible {
    var topRecognizedCandidate: (text: String, confidence: Float)? {
        guard let candidate = topCandidates(1).first else { return nil }
        return (candidate.string, candidate.confidence)
    }
}
