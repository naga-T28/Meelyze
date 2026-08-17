import SwiftUI

/// 選択チップ（Selected / Unselected variant）。
///
/// 表示値とタップintentのみを受け取るpure presentationとし、選択状態の保持や保存処理を内包しない。
/// 選択状態と保存処理はViewModelが所有する（`docs/ui-design.md`「共通UIコンポーネント」参照）。
struct ChoiceChipView: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color(.separator))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    HStack {
        ChoiceChipView(title: "卵", isSelected: true) {}
        ChoiceChipView(title: "乳", isSelected: false) {}
    }
    .padding()
}
