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

    /// 価格・メニュー番号・装飾記号を除去し、意味解析に使える文字列を残す正規化チェーン。
    /// `preprocess(_:)`と`hasNoAnalyzableContent(_:)`の両方がこの結果を共有する。
    private func stripNonDishText(from rawText: String) -> (text: String, changes: [MenuTextPreprocessingChange]) {
        var text = rawText
        var changes: [MenuTextPreprocessingChange] = []

        let withoutPrices = Self.replacingMatches(
            in: text,
            pattern: #"(?i)(?:[¥￥]\s*\d+(?:,\d{3})*|\d{1,3}(?:,\d{3})+\s*(?:円|yen)|\d{2,6}\s*(?:円|yen))"#,
            with: ""
        )
        if withoutPrices != text {
            text = withoutPrices
            changes.append(.priceRemoved)
        }

        let withoutMenuNumbers = Self.replacingMatches(
            in: text,
            pattern: #"(?i)(?:^|\s)(?:No\.?\s*|#)\d{1,3}(?=\s|[.)．、:：-]|$)|^\s*\d{1,3}\s*[.)．、:：-]\s*"#,
            with: " "
        )
        if withoutMenuNumbers != text {
            text = withoutMenuNumbers
            changes.append(.menuNumberRemoved)
        }

        // ★☆等の装飾記号は行頭・行末の連続にのみ適用し、料理名内部（例: サイズ・辛さの記号的表記）は対象外にする。
        let withoutNoiseSymbols = Self.replacingMatches(
            in: text,
            pattern: #"^[\s　]*(?:[\-‐‑–—=＊*・･.．、:：/／|｜【】\[\]（）()★☆]+[\s　]*)+|(?:[\s　]*[\-‐‑–—=＊*・･.．、:：/／|｜【】\[\]（）()★☆]+)+[\s　]*$"#,
            with: ""
        )
        if withoutNoiseSymbols != text {
            text = withoutNoiseSymbols
            changes.append(.noiseSymbolRemoved)
        }

        let normalizedWhitespace = Self.replacingMatches(in: text, pattern: #"\s+"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedWhitespace != text {
            text = normalizedWhitespace
            changes.append(.whitespaceNormalized)
        }

        return (text, changes)
    }

    private func preprocess(_ rawText: String) -> (analysisText: String?, changes: [MenuTextPreprocessingChange]) {
        let stripped = stripNonDishText(from: rawText)
        guard !stripped.text.isEmpty, stripped.text != rawText else { return (nil, stripped.changes) }
        return (stripped.text, stripped.changes)
    }

    /// `rawText`が価格・メニュー番号・装飾記号のみで構成され、除去後に料理名として意味のある文字が
    /// 一切残らないかどうかを判定する。`MenuAnalysisService`のFoundation Models利用不可時
    /// フォールバック（OCRセグメント1件を1判定対象itemとみなす）が、価格だけのセグメント等を
    /// 無意味な判定対象にしないために使う（FIX-013）。
    func hasNoAnalyzableContent(_ rawText: String) -> Bool {
        stripNonDishText(from: rawText).text.isEmpty
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
