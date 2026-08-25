import Foundation

/// OCR sourceの`rawText`を保持したまま、Issue #15のLLMへ渡す`analysisText`を作る前処理。
struct MenuTextPreprocessor {
    func preprocess(_ segments: [MenuUnderstandingSourceSegment]) -> MenuTextPreprocessingResult {
        var processedSegments: [MenuUnderstandingSourceSegment] = []
        var evidence: [MenuTextPreprocessingEvidence] = []

        for segment in segments {
            let processed = preprocess(segment.rawText)
            var nextSegment = segment
            nextSegment.analysisText = processed.analysisText
            processedSegments.append(nextSegment)
            evidence.append(
                MenuTextPreprocessingEvidence(
                    sourceID: segment.id,
                    rawText: segment.rawText,
                    analysisText: processed.analysisText,
                    confidence: segment.confidence,
                    boundingBox: segment.boundingBox,
                    changes: processed.changes
                )
            )
        }

        return MenuTextPreprocessingResult(segments: processedSegments, evidence: evidence)
    }

    private func preprocess(_ rawText: String) -> (analysisText: String?, changes: [MenuTextPreprocessingChange]) {
        var text = rawText
        var changes: [MenuTextPreprocessingChange] = []

        let withoutPrices = Self.replacingMatches(
            in: text,
            pattern: #"(?:[¥￥]\s*\d{1,3}(?:,\d{3})*|[¥￥]\s*\d+|\d{1,3}(?:,\d{3})*\s*(?:円|yen)|\d+\s*(?:円|yen))"#,
            with: ""
        )
        if withoutPrices != text {
            text = withoutPrices
            changes.append(.priceRemoved)
        }

        let normalizedWhitespace = Self.replacingMatches(in: text, pattern: #"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedWhitespace != text {
            text = normalizedWhitespace
            changes.append(.whitespaceNormalized)
        }

        guard !text.isEmpty, text != rawText else { return (nil, changes) }
        return (text, changes)
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
