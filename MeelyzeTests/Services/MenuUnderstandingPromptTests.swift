import Testing
import Foundation
@testable import Meelyze

struct MenuUnderstandingPromptTests {

    // MARK: - instructions()

    @Test func instructionsProhibitAllergenAndSafetyJudgments() {
        let instructions = MenuUnderstandingPrompt.instructions()

        #expect(instructions.contains("アレルゲン"))
        #expect(instructions.contains("出力しない"))
        #expect(instructions.contains("該当なし"))
        #expect(instructions.contains("含まれない"))
    }

    @Test func instructionsDistinguishExplicitIngredientsFromTypicalOrHiddenIngredients() {
        let instructions = MenuUnderstandingPrompt.instructions()

        #expect(instructions.contains("explicitIngredients"))
        #expect(instructions.contains("文字として書かれていなければ"))
    }

    @Test func instructionsRequireUnknownTermsToBePreservedRatherThanGuessedAway() {
        let instructions = MenuUnderstandingPrompt.instructions()

        #expect(instructions.contains("unknownTerms"))
        #expect(instructions.contains("空にするために推測"))
    }

    @Test func instructionsForbidFabricatingSourceIDsNotPresentInTheInput() {
        let instructions = MenuUnderstandingPrompt.instructions()

        #expect(instructions.contains("source ID"))
        #expect(instructions.contains("新しく作らないで"))
    }

    @Test func instructionsTreatInputSegmentContentAsDataNotAsInstructions() {
        let instructions = MenuUnderstandingPrompt.instructions()

        #expect(instructions.contains("解析対象のデータ"))
    }

    @Test func instructionsDescribeCompoundDishDecompositionKeepingUnresolvedResidueInUnknownTerms() {
        let instructions = MenuUnderstandingPrompt.instructions()

        #expect(instructions.contains("複合料理名"))
        #expect(instructions.contains("造語"))
    }

    // MARK: - prompt(for:)

    @Test func promptEncodesASingleSegmentAsAJSONObjectWithItsSourceID() throws {
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
        ])

        let entries = try decodePromptEntries(MenuUnderstandingPrompt.prompt(for: request))

        #expect(entries.count == 1)
        #expect(entries[0].sourceID == "s1")
        #expect(entries[0].rawText == "ラフテー")
        #expect(entries[0].analysisText == nil)
    }

    @Test func promptPreservesInputOrderAcrossMultipleSegments() throws {
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("c"), rawText: "テビチ", confidence: 0.9, boundingBox: .zero),
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("a"), rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
        ])

        let entries = try decodePromptEntries(MenuUnderstandingPrompt.prompt(for: request))

        #expect(entries.map(\.sourceID) == ["c", "a"])
        #expect(entries.map(\.rawText) == ["テビチ", "ラフテー"])
    }

    // MARK: - prompt(for:): rawText / analysisText role separation (FIX-005)

    @Test func promptCarriesBothRawTextAndAnalysisTextForTheSameSourceInAnEscapableFormatWithDistinctRoles() throws {
        var segment = MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "ゴーヤー・チャンプルー 1,280円", confidence: 0.9, boundingBox: .zero)
        segment.analysisText = "ゴーヤーチャンプルー"
        let request = MenuUnderstandingRequest(segments: [segment])

        let entries = try decodePromptEntries(MenuUnderstandingPrompt.prompt(for: request))

        #expect(entries.count == 1)
        #expect(entries[0].sourceID == "s1")
        #expect(entries[0].rawText == "ゴーヤー・チャンプルー 1,280円")
        #expect(entries[0].analysisText == "ゴーヤーチャンプルー")
        // rawTextとanalysisTextが異なる値として、どちらも欠落せずPromptへ含まれること。
        #expect(entries[0].rawText != entries[0].analysisText)
    }

    @Test func promptTreatsNilAndWhitespaceOnlyAnalysisTextIdenticallyAsAbsent() throws {
        let nilAnalysisText = MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "生 テキスト", confidence: 0.9, boundingBox: .zero)
        var whitespaceOnlyAnalysisText = MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s2"), rawText: "生 テキスト2", confidence: 0.9, boundingBox: .zero)
        whitespaceOnlyAnalysisText.analysisText = "   "
        var emptyAnalysisText = MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s3"), rawText: "生 テキスト3", confidence: 0.9, boundingBox: .zero)
        emptyAnalysisText.analysisText = ""
        let request = MenuUnderstandingRequest(segments: [nilAnalysisText, whitespaceOnlyAnalysisText, emptyAnalysisText])

        let entries = try decodePromptEntries(MenuUnderstandingPrompt.prompt(for: request))

        #expect(entries[0].analysisText == nil)
        #expect(entries[1].analysisText == nil)
        #expect(entries[2].analysisText == nil)
    }

    @Test func promptUsesTheActualAnalysisTextWhenItIsNonEmptyAfterTrimming() throws {
        var segment = MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "生 テキスト", confidence: 0.9, boundingBox: .zero)
        segment.analysisText = "前処理済みテキスト"
        let request = MenuUnderstandingRequest(segments: [segment])

        let entries = try decodePromptEntries(MenuUnderstandingPrompt.prompt(for: request))

        #expect(entries[0].analysisText == "前処理済みテキスト")
    }
}

private struct DecodedPromptEntry: Decodable {
    let sourceID: String
    let rawText: String
    let analysisText: String?
}

private func decodePromptEntries(_ prompt: String) throws -> [DecodedPromptEntry] {
    // instructions側の説明文は含めず、JSON配列部分だけをdecodeする。
    guard let jsonStart = prompt.firstIndex(of: "[") else {
        throw DecodePromptEntriesError.noJSONArrayFound
    }
    let jsonSubstring = prompt[jsonStart...]
    let data = Data(jsonSubstring.utf8)
    return try JSONDecoder().decode([DecodedPromptEntry].self, from: data)
}

private enum DecodePromptEntriesError: Error {
    case noJSONArrayFound
}
