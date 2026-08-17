import SwiftUI

/// S06（メニュー撮影）固有のfeature component。撮影ガイド枠と案内文言を表示する
/// （`docs/ui-design.md`「Feature-specific Component」。他画面での再利用が確認されるまでは
/// S06専用の設計・文言のまま維持する）。
struct CameraGuideOverlayView: View {
    let message: String

    var body: some View {
        VStack {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.top, 24)
                .accessibilityIdentifier("CameraGuideMessage")

            Spacer()

            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                .padding(.horizontal, 24)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)

            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("CameraGuideOverlay")
    }
}

#Preview {
    ZStack {
        Color.black
        CameraGuideOverlayView(message: "Fit the menu within the frame")
    }
    .ignoresSafeArea()
}
