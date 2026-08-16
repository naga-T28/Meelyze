import SwiftUI

/// S04/S05 アレルゲン・食事制限選択画面。
///
/// 特定原材料8品目・特定原材料に準ずるもの20品目を区別できる形で複数選択でき、あわせてMVP対象の
/// 食事制限区分を複数選択できる。0件選択（アレルギーなし）でも「プロファイルを保存」へ進める。
struct AllergenDietaryRestrictionView: View {
    @State private var viewModel: AllergenDietaryRestrictionViewModel

    /// 保存に成功した時点で、保存済み`UserProfile`とともに呼び出される。
    var onSave: (UserProfile) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)]

    init(
        hasAgreedToDisclaimer: Bool,
        disclaimerAgreedAt: Date?,
        displayLanguage: DisplayLanguage,
        profileRepository: ProfileRepository,
        onSave: @escaping (UserProfile) -> Void = { _ in }
    ) {
        _viewModel = State(
            initialValue: AllergenDietaryRestrictionViewModel(
                hasAgreedToDisclaimer: hasAgreedToDisclaimer,
                disclaimerAgreedAt: disclaimerAgreedAt,
                displayLanguage: displayLanguage,
                profileRepository: profileRepository
            )
        )
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    chipSection(
                        title: "アレルゲン（特定原材料・表示義務8品目）",
                        items: viewModel.mandatoryAllergenItems,
                        label: viewModel.displayName(for:),
                        isSelected: viewModel.isSelected(_:),
                        onTap: viewModel.toggle(_:)
                    )

                    chipSection(
                        title: "アレルゲン（特定原材料に準ずるもの・表示推奨20品目）",
                        items: viewModel.recommendedAllergenItems,
                        label: viewModel.displayName(for:),
                        isSelected: viewModel.isSelected(_:),
                        onTap: viewModel.toggle(_:)
                    )

                    chipSection(
                        title: "食事制限",
                        items: viewModel.dietaryRestrictionCategories,
                        label: viewModel.displayName(for:),
                        isSelected: viewModel.isSelected(_:),
                        onTap: viewModel.toggle(_:)
                    )
                }
                .padding()
            }

            Divider()

            Button {
                if let profile = try? viewModel.saveProfile() {
                    onSave(profile)
                }
            } label: {
                Text("プロファイルを保存")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .accessibilityIdentifier("AllergenDietaryRestrictionSaveButton")
        }
        .navigationTitle("アレルゲン・食事制限")
    }

    @ViewBuilder
    private func chipSection<Item: Identifiable & Hashable>(
        title: String,
        items: [Item],
        label: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        onTap: @escaping (Item) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    ChoiceChipView(title: label(item), isSelected: isSelected(item)) {
                        onTap(item)
                    }
                }
            }
        }
    }
}

#Preview {
    final class PreviewProfileRepository: ProfileRepository {
        func currentProfile() throws -> UserProfile? { nil }
        func save(_ profile: UserProfile) throws {}
    }

    return NavigationStack {
        AllergenDietaryRestrictionView(
            hasAgreedToDisclaimer: true,
            disclaimerAgreedAt: Date(),
            displayLanguage: .english,
            profileRepository: PreviewProfileRepository()
        )
    }
}
