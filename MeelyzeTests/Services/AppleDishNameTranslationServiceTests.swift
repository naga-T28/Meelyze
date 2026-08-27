import Testing
import Foundation
@testable import Meelyze

@MainActor
struct AppleDishNameTranslationServiceTests {
    @Test func translateReturnsNilForEmptyText() async {
        let service = AppleDishNameTranslationService()
        let result = await service.translate("", to: .english)
        #expect(result == nil)
    }

    @Test func translateReusesActiveSessionForSameTargetLanguageWithoutWaitingForANewSession() async {
        let service = AppleDishNameTranslationService()

        // 1件目の呼び出しでSessionを確立する（`translate`経由。`activeTargetLanguage`は
        // `translate`内でのみ設定されるため、`handleSessionAvailable`を先に単独で呼ぶと
        // 対象言語が一致せず`translate`が永久に保留される。実運用でも常にこの順序で発生する）。
        let firstTask = Task { await service.translate("ラフテー", to: .english) }
        await Task.yield()
        await Task.yield()
        await service.handleSessionAvailable(FakeDishTranslationSession(result: .success("Braised Pork Belly")))
        let firstResult = await firstTask.value
        #expect(firstResult == "Braised Pork Belly")

        // 2件目（同一対象言語）は、新たなSession確立を待たず、既存の`activeSession`を同期的に再利用する。
        let secondResult = await service.translate("ゴーヤーチャンプルー", to: .english)
        #expect(secondResult == "Braised Pork Belly")
    }

    @Test func translateReturnsNilWhenSessionThrows() async {
        let service = AppleDishNameTranslationService()

        let task = Task { await service.translate("ラフテー", to: .english) }
        await Task.yield()
        await Task.yield()
        await service.handleSessionAvailable(FakeDishTranslationSession(result: .failure(FakeTranslationError.unavailable)))
        let result = await task.value

        #expect(result == nil)
    }

    /// Session未確立時に呼ばれた翻訳要求は、`handleSessionAvailable`が呼ばれるまで保留され、
    /// 呼ばれた時点でまとめて処理される（`docs/ui-design.md`のUI側は`.translationTask`の
    /// 確立タイミングを制御できないため、この保留処理が正しく動く必要がある）。
    @Test func translateCalledBeforeSessionAvailableIsQueuedAndResolvedOnceSessionArrives() async {
        let service = AppleDishNameTranslationService()

        let task = Task { await service.translate("ゴーヤーチャンプルー", to: .english) }
        await Task.yield()
        await Task.yield()

        await service.handleSessionAvailable(FakeDishTranslationSession(result: .success("Goya Champuru")))
        let result = await task.value

        #expect(result == "Goya Champuru")
    }

    @Test func translationLanguageMapsAllMVPLanguagesToDistinctLocaleLanguages() {
        let languages: [DisplayLanguage] = [.english, .traditionalChinese, .simplifiedChinese, .korean]
        let identifiers = Set(languages.map(\.translationLanguage.minimalIdentifier))
        #expect(identifiers.count == 4)
        #expect(DisplayLanguage.english.translationLanguage.minimalIdentifier == "en")
        #expect(DisplayLanguage.korean.translationLanguage.minimalIdentifier == "ko")
    }
}

private struct FakeDishTranslationSession: DishTranslationSessionPerforming {
    let result: Result<String, Error>

    func performTranslation(of text: String) async throws -> String {
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

private enum FakeTranslationError: Error {
    case unavailable
}
