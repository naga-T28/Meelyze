import SwiftUI

/// S02 表示言語選択画面。
///
/// MVP対象4言語から表示言語を1つ選択する。この画面は表示言語が確定する前に表示されるため、
/// 画面chrome（見出し・CTA）は英語で固定表示する。各言語自体の行ラベルは選択言語に依存せず
/// 自称（endonym）で表示する（`task/TASK-015-language-selection-screen.md`参照）。
struct LanguageSelectionView: View {
    @State private var viewModel = LanguageSelectionViewModel()

    /// 表示言語が選択され、「次へ」が押された時点で呼び出される。
    var onContinue: (DisplayLanguage) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(viewModel.availableLanguages) { language in
                        Button {
                            viewModel.select(language)
                        } label: {
                            HStack {
                                Text(language.endonymLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.isSelected(language) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityIdentifier("LanguageRow_\(language.rawValue)")
                        .accessibilityAddTraits(viewModel.isSelected(language) ? .isSelected : [])
                    }
                } header: {
                    Text("Select your display language")
                }
            }

            Divider()

            Button {
                if let selected = viewModel.selectedLanguage {
                    onContinue(selected)
                }
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceed)
            .padding()
            .accessibilityIdentifier("LanguageSelectionContinueButton")
        }
        .navigationTitle("Display Language")
    }
}

#Preview {
    NavigationStack {
        LanguageSelectionView()
    }
}
