import SwiftUI

/// 安全性を保証しないことを常時示す注意表示。
///
/// `docs/ui-design.md`「非断定表現ルール」「店員確認の常時表示」は、任意の文面`String`ではなく
/// semantic variantを受け取ることで、画面・言語間で固定された意味を維持するよう定めている。
/// 各variantの文言はこのView内でのみ管理し、呼び出し側からは差し替えられない。
///
/// 背景は不透明にする（`docs/ui-design.md`「コントラスト基準」: 「写真上へ直接文字を置かず、
/// 不透明なカード面を介して上記比率を維持する」）。TASK-053で、半透明の背景（`Color.orange.
/// opacity(0.12)`）を`ResultOverlayView`（S08）内で撮影画像の代わりに黒背景が表示される状況
/// （UI Testスタブ等、有効な画像が得られない場合）に重ねたところ、`.primary`文字色とのコントラストが
/// 不足し、Appleの自動アクセシビリティ監査で断続的に"Contrast failed"となることを発見した。
/// 背景を`Color(.systemBackground)`（不透明）に変更し、警告の視覚的な識別はアイコン色と枠線の
/// オレンジで表現することで、どのような背景の上に重なっても一定のコントラストを保証する。
struct SafetyNoticeView: View {
    enum Variant {
        /// S01 免責事項同意画面（`DisclaimerView`）向け。同意前に表示する安全非保証の注意文。
        case disclaimerConsent
        /// S08/S09（Issue #20）向け。判定結果にかかわらず常時・非折りたたみで表示する注意文
        /// （`docs/ui-design.md`「店員確認の常時表示」）。
        case persistentResultNotice
    }

    let variant: Variant
    /// `.persistentResultNotice`の表示言語。`.disclaimerConsent`はS02（表示言語選択）より前に
    /// 表示されるため選択言語が未確定であり、この値を無視して英語固定のまま表示する
    /// （`Meelyze/Models/LocalizedText.swift`のコメント参照）。既存呼び出し箇所を変更せずに
    /// 済むよう既定値を設ける。
    var displayLanguage: DisplayLanguage = .english

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
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var message: String {
        switch variant {
        case .disclaimerConsent:
            return "Regardless of the result, please confirm the actual ingredients and cooking method with staff. This app does not guarantee your safety."
        case .persistentResultNotice:
            return SafetyNoticeText.persistentResultNotice.value(for: displayLanguage)
        }
    }

    private var accessibilityIdentifier: String {
        switch variant {
        case .disclaimerConsent: "SafetyNoticeView"
        case .persistentResultNotice: "PersistentResultSafetyNoticeView"
        }
    }
}

/// `SafetyNoticeView`のMVP対象4言語文言。`docs/ui-design.md`「店員確認の常時表示」の固定文言を
/// そのまま翻訳する。禁止表現（安全断定等）は含めない。
private enum SafetyNoticeText {
    static let persistentResultNotice = LocalizedText(
        english: "Regardless of the result, please confirm the actual ingredients and cooking method with staff. This app does not guarantee your safety.",
        traditionalChinese: "無論判定結果為何，請務必向店員確認實際的食材與烹調方式。本應用程式並不保證您的飲食安全。",
        simplifiedChinese: "无论判定结果如何，请务必向店员确认实际的食材与烹饪方式。本应用程序并不保证您的饮食安全。",
        korean: "판정 결과와 관계없이 실제 재료와 조리 방법을 직원에게 확인해 주세요. 이 앱은 안전을 보장하지 않습니다."
    )
}

#Preview {
    VStack(spacing: 16) {
        SafetyNoticeView(variant: .disclaimerConsent)
        SafetyNoticeView(variant: .persistentResultNotice, displayLanguage: .english)
    }
    .padding()
}
