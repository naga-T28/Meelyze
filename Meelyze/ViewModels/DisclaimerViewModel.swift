import Foundation

/// S01 免責事項同意画面（`DisclaimerView`）の同意状態を保持する。
///
/// このViewModelはApple Frameworkや`ProfileRepository`の具象実装に依存しない。同意状態と同意日時を
/// 公開するところまでを責務とし、SwiftDataへの実際の書き込みはTASK-017の`OnboardingFlowViewModel`が
/// S04/S05完了時に一括して行う（`task/README-issue11.md`「前提となる設計判断」参照）。
@Observable
final class DisclaimerViewModel {
    var hasAgreed: Bool = false {
        didSet {
            guard hasAgreed != oldValue else { return }
            agreedAt = hasAgreed ? Date() : nil
        }
    }

    private(set) var agreedAt: Date?

    /// 未同意の間はPrimary CTAを無効化するための判定。
    var canProceed: Bool { hasAgreed }
}
