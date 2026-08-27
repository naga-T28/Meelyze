import Testing
@testable import Meelyze

/// `docs/ui-design.md`「三値判定表示ルール」の表示対応表・コントラスト基準に対する
/// `RiskDetermination`の色・アイコン・ラベル拡張の適合性を検証する。
struct RiskBadgeViewTests {
    @Test func likelyContainsMatchesUIDesignColorTokens() {
        #expect(RiskDetermination.likelyContains.foregroundHex == 0xB42318)
        #expect(RiskDetermination.likelyContains.backgroundHex == 0xFEF3F2)
        #expect(RiskDetermination.likelyContains.borderHex == 0xB42318)
        #expect(RiskDetermination.likelyContains.sfSymbolName == "exclamationmark.triangle.fill")
    }

    @Test func noRecordedMatchMatchesUIDesignColorTokens() {
        #expect(RiskDetermination.noRecordedMatch.foregroundHex == 0x344054)
        #expect(RiskDetermination.noRecordedMatch.backgroundHex == 0xF2F4F7)
        #expect(RiskDetermination.noRecordedMatch.borderHex == 0x475467)
        #expect(RiskDetermination.noRecordedMatch.sfSymbolName == "info.circle.fill")
    }

    @Test func undeterminedMatchesUIDesignColorTokens() {
        #expect(RiskDetermination.undetermined.foregroundHex == 0x93370D)
        #expect(RiskDetermination.undetermined.backgroundHex == 0xFFFAEB)
        #expect(RiskDetermination.undetermined.borderHex == 0xB54708)
        #expect(RiskDetermination.undetermined.sfSymbolName == "questionmark.diamond.fill")
    }

    /// 「収録データ上は該当なし」にチェック・盾・笑顔など安全認定を連想させるSF Symbolを
    /// 使わないことを明示的に固定する（`docs/ui-design.md`「三値判定表示ルール」）。
    @Test func noRecordedMatchDoesNotUseSafetyEndorsingSymbol() {
        let bannedSymbols = ["checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.shield", "checkmark.shield.fill", "face.smiling"]
        #expect(!bannedSymbols.contains(RiskDetermination.noRecordedMatch.sfSymbolName))
    }

    @Test func allThreeStatesHaveDistinctSymbolsAndColors() {
        let states: [RiskDetermination] = [.likelyContains, .noRecordedMatch, .undetermined]
        #expect(Set(states.map(\.sfSymbolName)).count == 3)
        #expect(Set(states.map(\.foregroundHex)).count == 3)
    }

    @Test func displayLabelIsProvidedForAllMVPLanguagesAndAllStates() {
        let states: [RiskDetermination] = [.likelyContains, .noRecordedMatch, .undetermined]
        let languages: [DisplayLanguage] = [.english, .traditionalChinese, .simplifiedChinese, .korean]

        for state in states {
            for language in languages {
                #expect(!state.displayLabel(for: language).isEmpty)
            }
        }
    }

    @Test func displayLabelsAreDistinctAcrossStatesForEachLanguage() {
        let languages: [DisplayLanguage] = [.english, .traditionalChinese, .simplifiedChinese, .korean]
        for language in languages {
            let labels = [
                RiskDetermination.likelyContains.displayLabel(for: language),
                RiskDetermination.noRecordedMatch.displayLabel(for: language),
                RiskDetermination.undetermined.displayLabel(for: language)
            ]
            #expect(Set(labels).count == 3)
        }
    }

    /// `収録データ上は`の限定を省略しない（`docs/ui-design.md`表示対応表の必須注記）。英語版では
    /// "Records"という語で同じ限定（DB照合結果であることの明示）を維持していることを確認する。
    @Test func noRecordedMatchEnglishLabelPreservesRecordsQualifier() {
        #expect(RiskDetermination.noRecordedMatch.displayLabel(for: .english).localizedCaseInsensitiveContains("record"))
    }

    @Test func exactEnglishLabelsMatchExpectedCopy() {
        #expect(RiskDetermination.likelyContains.displayLabel(for: .english) == "Likely Contains")
        #expect(RiskDetermination.noRecordedMatch.displayLabel(for: .english) == "No Match in Records")
        #expect(RiskDetermination.undetermined.displayLabel(for: .english) == "Undetermined")
    }
}
