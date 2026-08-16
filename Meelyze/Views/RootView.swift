import SwiftUI
import SwiftData

/// 初期設定完了状態に応じて、S01（初期設定フロー）またはS06（メニュー撮影導線）へrootを切り替える
/// Root Gate。
///
/// 初期設定完了後はS01〜S05をback stackへ残さず、`ScanView`へrootそのものを切り替える
/// （`docs/ui-design.md`「Navigation / Sheet / Loading / Error方針」Root gateの行）。
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var destination: Destination?

    private enum Destination {
        case onboarding
        case scan
    }

    var body: some View {
        Group {
            if let destination {
                switch destination {
                case .onboarding:
                    OnboardingFlowView(profileRepository: profileRepository) { _ in
                        self.destination = .scan
                    }
                case .scan:
                    ScanView()
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if destination == nil {
                determineInitialDestination()
            }
        }
    }

    private var profileRepository: ProfileRepository {
        SwiftDataProfileRepository(modelContext: modelContext)
    }

    private func determineInitialDestination() {
        let profile = try? profileRepository.currentProfile()
        destination = (profile?.isInitialSetupCompleted == true) ? .scan : .onboarding
    }
}

#Preview {
    RootView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
