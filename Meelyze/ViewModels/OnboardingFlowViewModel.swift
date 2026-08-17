import Foundation

/// S01（同意）→S02（表示言語）→S04/S05（アレルゲン・食事制限、保存）の入力をメモリ上で保持したまま
/// 画面間を受け渡す共有状態。
///
/// 画面ごとの部分保存はせず、S04/S05完了時に`ProfileRepository`へ一度だけ書き込む設計と整合させる
/// ため、本ViewModelは同意日時・表示言語をメモリ上で中継するだけで、それ自体はSwiftDataへ書き込まない
/// （`task/README-issue11.md`「前提となる設計判断」参照）。
@Observable
final class OnboardingFlowViewModel {
    var path: [OnboardingRoute] = []
    private(set) var disclaimerAgreedAt: Date?
    private(set) var displayLanguage: DisplayLanguage?

    let profileRepository: ProfileRepository

    init(profileRepository: ProfileRepository) {
        self.profileRepository = profileRepository
    }

    /// S01の同意完了を受けてS02へ遷移する。
    func recordDisclaimerAgreement(at agreedAt: Date) {
        disclaimerAgreedAt = agreedAt
        path.append(.languageSelection)
    }

    /// S02の言語選択完了を受けてS04/S05へ遷移する。
    func recordDisplayLanguage(_ language: DisplayLanguage) {
        displayLanguage = language
        path.append(.allergenDietaryRestriction)
    }
}

/// 初期設定フロー内の遷移先。`NavigationStack`のpathは軽量なHashable route値とし、
/// ドメインモデル本体をpathの運搬手段にしない（`docs/ui-design.md`「Navigation」方針）。
enum OnboardingRoute: Hashable {
    case languageSelection
    case allergenDietaryRestriction
    // S03（翻訳用言語データ準備案内）はIssue #22の担当範囲であり本タスクでは実装しない。
    // languageSelectionとallergenDietaryRestrictionの間に差し込めるよう、caseを追加できる
    // 余地をここに残す（`task/README-issue11.md`遷移ルール、K04参照）。
}
