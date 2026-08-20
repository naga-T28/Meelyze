import SwiftUI

/// S06（メニュー撮影）固有のfeature component。撮影操作を行うシャッターボタン
/// （`docs/ui-design.md`「Feature-specific Component」。他画面での再利用が確認されるまでは
/// S06専用の設計のまま維持する）。
struct ShutterButtonView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(.white)
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.6), lineWidth: 4)
                        .frame(width: 84, height: 84)
                )
        }
        .accessibilityIdentifier("ShutterButton")
        .accessibilityLabel("Shutter")
    }
}

#Preview {
    ZStack {
        Color.black
        ShutterButtonView {}
    }
    .ignoresSafeArea()
}
