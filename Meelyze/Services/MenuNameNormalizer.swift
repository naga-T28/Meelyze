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

    /// 漢数字「一」(U+4E00)がOCRによる長音記号「ー」の誤認識である、確認済みの語だけを補正する。
    ///
    /// 文字位置（直前・直後の文字種）による推測は行わない。過去に位置推測（直前がカタカナ、
    /// 直後がひらがな/漢字でない場合のみ変換）を採用していたが、「メニュー一」（直前が長音記号、
    /// 末尾で「直後」チェックが働かない）を「メニューー」へ誤変換する反例があり、位置推測そのものを
    /// 廃止した。ここに掲げる有限辞書のキーだけを対象に部分文字列置換する。
    private static let knownOCRLongSoundCorrections: [String: String] = [
        "ラフテ一": "ラフテー"
    ]

    private static func normalizeOCRLongSoundMarks(_ text: String) -> String {
        knownOCRLongSoundCorrections.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}
