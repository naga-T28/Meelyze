import Foundation
import SwiftUI
import Translation

/// `DisplayLanguage`からApple Translation Frameworkの`Locale.Language`への対応。
extension DisplayLanguage {
    var translationLanguage: Locale.Language {
        switch self {
        case .english: Locale.Language(identifier: "en")
        case .traditionalChinese: Locale.Language(identifier: "zh-Hant")
        case .simplifiedChinese: Locale.Language(identifier: "zh-Hans")
        case .korean: Locale.Language(identifier: "ko")
        }
    }
}

/// `TranslationSession.translate(_:)`の呼び出しに必要な最小限の操作を抽象化するProtocol。
/// `TranslationSession.Response`にはテストコードから構築できる公開イニシャライザがないため、
/// `VisionOCRService`が`VNRecognizedTextObservation`に対して行ったのと同様に、Sessionの実際の
/// 呼び出し1つだけをこのProtocol境界へ切り出し、テストではSessionそのものではなくこのProtocolに
/// 準拠したfakeへ差し替える。
protocol DishTranslationSessionPerforming: Sendable {
    /// メソッド名を`translate`ではなく`performTranslation(of:)`にしているのは、`TranslationSession`
    /// 自身が持つ`translate(_:) async throws -> TranslationSession.Response`と名前が衝突し、
    /// extension内での呼び出しが自己再帰になることを避けるため。
    func performTranslation(of text: String) async throws -> String
}

extension TranslationSession: DishTranslationSessionPerforming {
    func performTranslation(of text: String) async throws -> String {
        try await translate(text).targetText
    }
}

/// `DishNameTranslationService`のApple Translation Framework実装。
///
/// Translation Frameworkは`TranslationSession`をSwiftUIの`.translationTask(_:action:)`修飾子経由でしか
/// 取得できず（View非依存の直接初期化APIを提供しない）、ViewModel/Service層から独立してSessionを
/// 得ることができない。そのため本クラスは`@Observable`にし、`dishNameTranslationSession(using:)`
/// （本ファイル下部のView拡張）でView階層へ組み込むことを前提にした橋渡し役として設計する。
///
/// - `translate(_:to:)`が呼ばれると`configuration`を更新し、`.translationTask`修飾子が新しい
///   Sessionを提供するのを待つ（`handleSessionAvailable`経由）。
/// - 同一の対象言語に対する2件目以降の呼び出しは、既に確立済みの`activeSession`を再利用し、
///   `.translationTask`の再トリガーを待たない。
/// - Session確立前に呼ばれた翻訳要求は`pendingRequests`に保持し、Session確立後にまとめて処理する。
///
/// **制約**: 1インスタンスにつき同時に1つの対象言語のみを扱う前提とする。`activeTargetLanguage`は
/// 直近の`translate(_:to:)`呼び出しの対象言語のみを保持するため、Session未確立の状態で異なる対象
/// 言語へ連続して呼び出すと、後着の言語のSessionが先着の要求にも使われてしまう可能性がある。
/// S08/S09は画面ごとに固定の`UserProfile.displayLanguage`のみを対象言語として呼び出すため、
/// 実運用でこの状況は発生しない。
@Observable
@MainActor
final class AppleDishNameTranslationService: DishNameTranslationService {
    private(set) var configuration: TranslationSession.Configuration?

    private var activeSession: (any DishTranslationSessionPerforming)?
    private var activeTargetLanguage: Locale.Language?
    private var pendingRequests: [PendingRequest] = []

    private struct PendingRequest {
        let text: String
        let continuation: CheckedContinuation<String?, Never>
    }

    func translate(_ japaneseText: String, to language: DisplayLanguage) async -> String? {
        guard !japaneseText.isEmpty else { return nil }
        let targetLanguage = language.translationLanguage

        if let activeSession, activeTargetLanguage == targetLanguage {
            return await Self.performTranslate(japaneseText, using: activeSession)
        }

        activeTargetLanguage = targetLanguage
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "ja"),
            target: targetLanguage
        )

        return await withCheckedContinuation { continuation in
            pendingRequests.append(PendingRequest(text: japaneseText, continuation: continuation))
        }
    }

    /// `dishNameTranslationSession(using:)`が付与する`.translationTask`から呼ばれる。Session確立時に
    /// 保留中の要求をまとめて処理し、以後の呼び出しのために`activeSession`として保持する。
    /// `internal`（既定）にしているのは、`@testable import`経由でテストからfakeを注入できるようにする
    /// ため（`fileprivate`だと`@testable import`でも越境できない）。
    func handleSessionAvailable(_ session: any DishTranslationSessionPerforming) async {
        activeSession = session
        let requests = pendingRequests
        pendingRequests.removeAll()
        for request in requests {
            let result = await Self.performTranslate(request.text, using: session)
            request.continuation.resume(returning: result)
        }
    }

    private static func performTranslate(_ text: String, using session: any DishTranslationSessionPerforming) async -> String? {
        try? await session.performTranslation(of: text)
    }
}

private struct DishNameTranslationSessionModifier: ViewModifier {
    let service: AppleDishNameTranslationService

    func body(content: Content) -> some View {
        content.translationTask(service.configuration) { session in
            await service.handleSessionAvailable(session)
        }
    }
}

extension View {
    /// `AppleDishNameTranslationService`が発行する翻訳要求を実際に処理できるようにする。S08/S09の
    /// ルートViewへ一度だけ適用する想定（`docs/technology-selection.md`§4: ViewModelはApple
    /// Frameworkを直接importしないため、Translation Frameworkとの結線はView層のこの1箇所に閉じる）。
    func dishNameTranslationSession(using service: AppleDishNameTranslationService) -> some View {
        modifier(DishNameTranslationSessionModifier(service: service))
    }
}
