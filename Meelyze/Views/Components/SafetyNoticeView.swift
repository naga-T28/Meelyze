import SwiftUI

/// 安全性を保証しないことを常時示す注意表示。
///
/// `docs/ui-design.md`「非断定表現ルール」「店員確認の常時表示」は、任意の文面`String`ではなく
/// semantic variantを受け取ることで、画面・言語間で固定された意味を維持するよう定めている。
/// 各variantの文言はこのView内でのみ管理し、呼び出し側からは差し替えられない。
struct SafetyNoticeView: View {
    enum Variant {
        /// S01 免責事項同意画面（`DisclaimerView`）向け。同意前に表示する安全非保証の注意文。
        case disclaimerConsent
    }

    let variant: Variant

    var body: some View {
        Label {
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("SafetyNoticeView")
    }

    private var message: String {
        switch variant {
        case .disclaimerConsent:
            return "Regardless of the result, please confirm the actual ingredients and cooking method with staff. This app does not guarantee your safety."
        }
    }
}

#Preview {
    SafetyNoticeView(variant: .disclaimerConsent)
        .padding()
}
