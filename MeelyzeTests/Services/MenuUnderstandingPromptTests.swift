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

    @Test func promptFormatsASingleSegmentWithItsSourceIDMarker() {
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
        ])

        #expect(MenuUnderstandingPrompt.prompt(for: request) == "[s1] ラフテー")
    }

    @Test func promptPreservesInputOrderAcrossMultipleSegments() {
        let request = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("c"), rawText: "テビチ", confidence: 0.9, boundingBox: .zero),
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("a"), rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
        ])

        #expect(MenuUnderstandingPrompt.prompt(for: request) == "[c] テビチ\n[a] ラフテー")
    }

    @Test func promptUsesAnalysisTextWhenPresentButFallsBackToRawTextOtherwise() {
        var withAnalysisText = MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "生 テキスト", confidence: 0.9, boundingBox: .zero)
        withAnalysisText.analysisText = "前処理済みテキスト"
        let withoutAnalysisText = MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s2"), rawText: "生 テキスト2", confidence: 0.9, boundingBox: .zero)
        let request = MenuUnderstandingRequest(segments: [withAnalysisText, withoutAnalysisText])

        let prompt = MenuUnderstandingPrompt.prompt(for: request)

        #expect(prompt == "[s1] 前処理済みテキスト\n[s2] 生 テキスト2")
    }
}
