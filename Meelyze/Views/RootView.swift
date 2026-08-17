import SwiftUI
import SwiftData

/// 初期設定完了状態に応じて、S01（初期設定フロー）またはS06（メニュー撮影導線）へrootを切り替える
/// Root Gate。
///
/// 初期設定完了後はS01〜S05をback stackへ残さず、`ScanView`へrootそのものを切り替える
/// （`docs/ui-design.md`「Navigation / Sheet / Loading / Error方針」Root gateの行）。`ScanView`は
/// 選択済み表示言語で表示するため、新規完了時は保存直後の`UserProfile`から、再起動時は復元した
/// `UserProfile`からそれぞれ`displayLanguage`を引き継ぐ。
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var destination: Destination?
    @State private var cameraService: CameraService = RootView.makeCameraService()
    @State private var ocrService: OCRService = RootView.makeOCRService()

    private enum Destination {
        case onboarding
        case scan(DisplayLanguage)
    }

    var body: some View {
        Group {
            if let destination {
                switch destination {
                case .onboarding:
                    OnboardingFlowView(profileRepository: profileRepository) { profile in
                        self.destination = .scan(profile.displayLanguage)
                    }
                case .scan(let displayLanguage):
                    ScanView(displayLanguage: displayLanguage, cameraService: cameraService, ocrService: ocrService)
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
        if let profile, profile.isInitialSetupCompleted {
            destination = .scan(profile.displayLanguage)
        } else {
            destination = .onboarding
        }
    }

    /// UI Testからの実カメラ依存排除。`UITEST_OCR_STUB_MODE`環境変数が指定された場合は
    /// `StubCameraService`を使う（`Meelyze/Services/UITestScanStubs.swift`参照）。
    private static func makeCameraService() -> CameraService {
        guard ProcessInfo.processInfo.environment["UITEST_OCR_STUB_MODE"] != nil else {
            return AVFoundationCameraService()
        }
        return StubCameraService()
    }

    /// UI Testからの実Vision依存排除。`UITEST_OCR_STUB_MODE`が`StubOCRService.Mode`の値
    /// （`empty` / `success`）を指定する場合は`StubOCRService`を使う。
    private static func makeOCRService() -> OCRService {
        guard
            let rawMode = ProcessInfo.processInfo.environment["UITEST_OCR_STUB_MODE"],
            let mode = StubOCRService.Mode(rawValue: rawMode)
        else {
            return VisionOCRService()
        }
        return StubOCRService(mode: mode)
    }
}

#Preview {
    RootView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
