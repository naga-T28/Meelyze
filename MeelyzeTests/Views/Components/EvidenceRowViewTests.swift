import Testing
@testable import Meelyze

/// `EvidenceOrigin`の分類ロジック（Issue #20完了条件「DB由来とLLM由来の補助情報を区別できる」）を
/// 検証する。
struct EvidenceRowViewTests {
    @Test func explicitKindMapsToDatabase() {
        #expect(EvidenceOrigin(kind: .explicit) == .database)
    }

    @Test func normalizedKindMapsToDatabase() {
        #expect(EvidenceOrigin(kind: .normalized) == .database)
    }

    @Test func dishDatabaseKindMapsToDatabase() {
        #expect(EvidenceOrigin(kind: .dishDatabase) == .database)
    }

    @Test func llmInferenceKindMapsToLLM() {
        #expect(EvidenceOrigin(kind: .llmInference) == .llm)
    }

    @Test func unknownKindMapsToUnresolved() {
        #expect(EvidenceOrigin(kind: .unknown) == .unresolved)
    }

    @Test func databaseAndLLMOriginsAreVisuallyDistinct() {
        #expect(EvidenceOrigin.database.color != EvidenceOrigin.llm.color)
        #expect(EvidenceOrigin.database.label.value(for: .english) != EvidenceOrigin.llm.label.value(for: .english))
    }

    @Test func allOriginLabelsAreProvidedForAllMVPLanguages() {
        let languages: [DisplayLanguage] = [.english, .traditionalChinese, .simplifiedChinese, .korean]
        let origins: [EvidenceOrigin] = [.database, .llm, .unresolved]
        for origin in origins {
            for language in languages {
                #expect(!origin.label.value(for: language).isEmpty)
            }
        }
    }
}
