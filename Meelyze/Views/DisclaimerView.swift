import SwiftUI

/// S01 初回起動・免責事項画面。
///
/// 免責事項本文と安全非保証の注意文（`SafetyNoticeView`）をスクロールで隠れない初期表示位置に示し、
/// 同意しない限り初期設定を先へ進められないようにする。
struct DisclaimerView: View {
    @State private var viewModel = DisclaimerViewModel()

    /// 同意して「同意して続ける」が押された時点で、同意日時とともに呼び出される。
    var onContinue: (Date) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("免責事項")
                        .font(.largeTitle)
                        .bold()

                    SafetyNoticeView(variant: .disclaimerConsent)

                    Text("Meelyzeは、撮影したメニューの文字とAI解析、収録データをもとに、アレルゲン・食事制限対象食材が含まれる可能性を推定する参考情報を表示するアプリです。判定は完全ではなく、収録データで確認できない料理・食材は「判定不可」として表示されます。")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }

            Divider()

            VStack(spacing: 16) {
                Button {
                    viewModel.hasAgreed.toggle()
                } label: {
                    HStack {
                        Image(systemName: viewModel.hasAgreed ? "checkmark.square.fill" : "square")
                            .foregroundStyle(viewModel.hasAgreed ? Color.accentColor : Color.secondary)
                        Text("上記の内容を理解し、同意します")
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DisclaimerAgreeToggle")
                .accessibilityAddTraits(viewModel.hasAgreed ? [.isSelected] : [])

                Button {
                    if let agreedAt = viewModel.agreedAt {
                        onContinue(agreedAt)
                    }
                } label: {
                    Text("同意して続ける")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceed)
                .accessibilityIdentifier("DisclaimerContinueButton")
            }
            .padding()
        }
    }
}

#Preview {
    DisclaimerView()
}
