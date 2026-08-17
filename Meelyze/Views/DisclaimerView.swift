import SwiftUI

/// S01 初回起動・免責事項画面。
///
/// 免責事項本文と安全非保証の注意文（`SafetyNoticeView`）をスクロールで隠れない初期表示位置に示し、
/// 同意しない限り初期設定を先へ進められないようにする。この画面は表示言語選択（S02）より前に
/// 表示されるため、選択言語に依存せず英語で固定表示する。S04/S05以降は選択された表示言語で表示する
/// （`Meelyze/Views/AllergenDietaryRestrictionView.swift` `Meelyze/Views/ScanView.swift`参照）。
struct DisclaimerView: View {
    @State private var viewModel = DisclaimerViewModel()

    /// 同意して「Agree and Continue」が押された時点で、同意日時とともに呼び出される。
    var onContinue: (Date) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Disclaimer")
                        .font(.largeTitle)
                        .bold()

                    SafetyNoticeView(variant: .disclaimerConsent)

                    Text("Meelyze shows reference information estimating the possible presence of allergens or dietary-restricted ingredients, based on the text of a photographed menu, AI analysis, and its recorded data. This assessment is not exhaustive — any dish or ingredient that cannot be confirmed against the recorded data will be shown as \"Undetermined.\"")
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
                        Text("I understand and agree to the above")
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
                    Text("Agree and Continue")
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
