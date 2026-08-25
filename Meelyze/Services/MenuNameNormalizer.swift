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

        let longSoundNormalized = Self.normalizeOCRLongSoundMarks(normalized)
        if longSoundNormalized != normalized {
            normalized = longSoundNormalized
            changes.append(.ocrLongSoundNormalized)
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

    private static func normalizeOCRLongSoundMarks(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        for index in scalars.indices where scalars[index].value == 0x4E00 {
            let hasKanaBefore = index > scalars.startIndex && isKanaOrLongSound(scalars[scalars.index(before: index)])
            let hasKanaAfter = scalars.index(after: index) < scalars.endIndex && isKanaOrLongSound(scalars[scalars.index(after: index)])
            if hasKanaBefore || hasKanaAfter {
                scalars[index] = "ー"
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func isKanaOrLongSound(_ scalar: UnicodeScalar) -> Bool {
        (0x3041...0x3096).contains(scalar.value)
            || (0x30A1...0x30FA).contains(scalar.value)
            || scalar.value == 0x30FC
    }
}
