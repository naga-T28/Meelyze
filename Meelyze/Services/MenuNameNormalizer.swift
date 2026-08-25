import Foundation

/// LLMが抽出した料理名・明示食材候補を、Alias Dictionary検索前の決定論的な表記へ寄せる。
struct MenuNameNormalizer {
    func normalize(_ text: String) -> MenuNameNormalizationEvidence {
        var normalized = text
        var changes: [MenuNameNormalizationChange] = []

        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != normalized {
            normalized = trimmed
            changes.append(.trimmed)
        }

        let folded = normalized.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja-JP"))
        if folded != normalized {
            normalized = folded
            changes.append(.widthAndCaseFolded)
        }

        let katakana = Self.hiraganaToKatakana(normalized)
        if katakana != normalized {
            normalized = katakana
            changes.append(.hiraganaConvertedToKatakana)
        }

        let withoutSeparators = normalized
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "・", with: "")
            .replacingOccurrences(of: "･", with: "")
        if withoutSeparators != normalized {
            normalized = withoutSeparators
            changes.append(.separatorsRemoved)
        }

        return MenuNameNormalizationEvidence(originalText: text, normalizedText: normalized, changes: changes)
    }

    private static func hiraganaToKatakana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            let value = scalar.value
            if (0x3041...0x3096).contains(value), let converted = UnicodeScalar(value + 0x60) {
                return converted
            }
            return scalar
        }))
    }
}
