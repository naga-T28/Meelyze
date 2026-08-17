import SwiftUI

/// メニュー撮影導線の最小プレースホルダ。
///
/// カメラ・Apple Vision OCRの実装はIssue #14の範囲であり、本タスクでは実装しない。初期設定完了後の
/// 遷移先を確保するための識別可能な表示のみを提供し、#14がこのViewを差し替える。この画面はS02で
/// 表示言語が確定した後に到達するため、選択済み表示言語で表示する。
struct ScanView: View {
    let displayLanguage: DisplayLanguage

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(ScanViewText.placeholder.value(for: displayLanguage))
                .font(.title2)
                .bold()
                .accessibilityIdentifier("ScanPlaceholderLabel")
        }
        .padding()
    }
}

/// `ScanView`の画面chrome文言。MVP対象4言語で固定の意味を維持する。
private enum ScanViewText {
    static let placeholder = LocalizedText(
        english: "Menu scanning is coming soon",
        traditionalChinese: "菜單拍攝功能準備中",
        simplifiedChinese: "菜单拍摄功能准备中",
        korean: "메뉴 촬영 기능은 준비 중입니다"
    )
}

#Preview {
    ScanView(displayLanguage: .english)
}
