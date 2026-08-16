import SwiftUI

/// S01→S02→S04/S05を`NavigationStack`で結線した初期設定フロー。
///
/// 標準のBack/edge-swipeを維持するため、独自の戻るバーは実装しない。
struct OnboardingFlowView: View {
    @State private var viewModel: OnboardingFlowViewModel

    /// S04/S05の保存が成功し、初期設定が完了した時点で保存済み`UserProfile`とともに呼び出される。
    var onSetupCompleted: (UserProfile) -> Void

    init(
        profileRepository: ProfileRepository,
        onSetupCompleted: @escaping (UserProfile) -> Void
    ) {
        _viewModel = State(initialValue: OnboardingFlowViewModel(profileRepository: profileRepository))
        self.onSetupCompleted = onSetupCompleted
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            DisclaimerView { agreedAt in
                viewModel.recordDisclaimerAgreement(at: agreedAt)
            }
            .navigationDestination(for: OnboardingRoute.self) { route in
                switch route {
                case .languageSelection:
                    LanguageSelectionView { language in
                        viewModel.recordDisplayLanguage(language)
                    }
                case .allergenDietaryRestriction:
                    if let agreedAt = viewModel.disclaimerAgreedAt, let language = viewModel.displayLanguage {
                        AllergenDietaryRestrictionView(
                            hasAgreedToDisclaimer: true,
                            disclaimerAgreedAt: agreedAt,
                            displayLanguage: language,
                            profileRepository: viewModel.profileRepository,
                            onSave: onSetupCompleted
                        )
                    }
                }
            }
        }
    }
}
