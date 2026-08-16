import SwiftUI

/// メニュー撮影導線の最小プレースホルダ。
///
/// カメラ・Apple Vision OCRの実装はIssue #14の範囲であり、本タスクでは実装しない。初期設定完了後の
/// 遷移先を確保するための識別可能な表示のみを提供し、#14がこのViewを差し替える。
struct ScanView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("メニュー撮影は準備中です")
                .font(.title2)
                .bold()
                .accessibilityIdentifier("ScanPlaceholderLabel")
        }
        .padding()
    }
}

#Preview {
    ScanView()
}
