import SwiftUI

/// E01 OCR失敗フォールバック表示。Visionが文字を1件も抽出できない、またはOCR処理を完了できない
/// 場合に、S06から置き換えて表示する（`docs/ui-design.md`「異常系UI」E01）。
///
/// 料理が未抽出のため三値判定バッジ等は表示せず、「アレルゲンなし」など安全結果に見える文言も
/// 使わない。主操作「再撮影」でS06へ戻す。失敗はここでは判定履歴として保存しない。
struct OCRFailureView: View {
    let displayLanguage: DisplayLanguage
    let onRetake: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text(OCRFailureText.title.value(for: displayLanguage))
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("OCRFailureTitle")

                Text(OCRFailureText.message.value(for: displayLanguage))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(OCRFailureText.tips(for: displayLanguage), id: \.self) { tip in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .accessibilityHidden(true)
                        Text(tip)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("OCRFailureTips")

            Spacer()

            Button(action: onRetake) {
                Text(OCRFailureText.retakeButton.value(for: displayLanguage))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .accessibilityIdentifier("OCRFailureRetakeButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// `OCRFailureView`の画面chrome文言。MVP対象4言語で固定の意味を維持する。
private enum OCRFailureText {
    static let title = LocalizedText(
        english: "Couldn't read the menu text",
        traditionalChinese: "無法辨識菜單文字",
        simplifiedChinese: "无法识别菜单文字",
        korean: "메뉴 텍스트를 읽을 수 없습니다"
    )

    static let message = LocalizedText(
        english: "Adjust the brightness, angle, and distance, then take the photo again.",
        traditionalChinese: "請調整亮度、角度與距離後重新拍攝。",
        simplifiedChinese: "请调整亮度、角度与距离后重新拍摄。",
        korean: "밝기, 각도, 거리를 조정한 후 다시 촬영해주세요."
    )

    private static let brightPlace = LocalizedText(
        english: "Find a bright place",
        traditionalChinese: "請在明亮處拍攝",
        simplifiedChinese: "请在明亮处拍摄",
        korean: "밝은 곳에서 촬영해주세요"
    )

    private static let frontalAngle = LocalizedText(
        english: "Shoot from a front-facing angle",
        traditionalChinese: "請以接近正面的角度拍攝",
        simplifiedChinese: "请以接近正面的角度拍摄",
        korean: "정면에 가까운 각도로 촬영해주세요"
    )

    private static let getCloser = LocalizedText(
        english: "Get closer to the dish names",
        traditionalChinese: "請靠近料理名稱拍攝",
        simplifiedChinese: "请靠近菜品名称拍摄",
        korean: "요리 이름에 가까이 다가가주세요"
    )

    static let retakeButton = LocalizedText(
        english: "Retake Photo",
        traditionalChinese: "重新拍攝",
        simplifiedChinese: "重新拍摄",
        korean: "다시 촬영"
    )

    static func tips(for language: DisplayLanguage) -> [String] {
        [brightPlace, frontalAngle, getCloser].map { $0.value(for: language) }
    }
}

#Preview {
    OCRFailureView(displayLanguage: .english) {}
}
