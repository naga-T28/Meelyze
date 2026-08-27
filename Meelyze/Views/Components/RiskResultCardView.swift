import SwiftUI

/// `RiskTarget`（Issue #17）の表示名。既存の`AllergenItem.localizedName(for:)` /
/// `DietaryRestrictionCategory.localizedName(for:)`（S04/S05のアレルゲン・食事制限選択画面が
/// 使用済み）へそのまま委譲する。
extension RiskTarget {
    func localizedName(for language: DisplayLanguage) -> String {
        switch self {
        case .allergen(let item): item.localizedName(for: language)
        case .dietaryRestriction(let category): category.localizedName(for: language)
        }
    }
}

/// 料理名・三値バッジ・判明済み対象食材をまとめた結果カード。S08の画像上重畳（`.compactOverlay`）と
/// S09の詳細表示（`.detailed`）の両方で使う（`docs/ui-design.md`「共通UIコンポーネント」）。
///
/// `matchedTargetNames`は、渡された`determination`（バッジに表示する主状態）に関わらず常に表示する。
/// 主状態が「判定不可」であっても、既に判明している「含有の可能性が高い」対象（Positive Evidence）が
/// 別途存在する場合はそれを隠さない、という`docs/ui-design.md`「三値判定表示ルール」の要件を満たす
/// ため、フィルタリングは呼び出し側（TASK-048/051）が`MenuItemRiskEvaluation.results`から
/// `determination == .likelyContains`の対象を集める形で行い、本Viewは受け取った内容を無条件に表示する。
struct RiskResultCardView: View {
    enum Style: Equatable {
        /// S08: 撮影画像上へ重畳する、コンパクトな表示。
        case compactOverlay
        /// S09: 料理詳細画面の見出しとして使う、余白の広い表示。
        case detailed
    }

    let style: Style
    /// OCR原文（日本語）。母語訳が取得できない場合でも常に表示する。
    let japaneseDishName: String
    /// 母語訳（TASK-047の`DishNameTranslationService`が提供）。翻訳不可時は`nil`。
    let translatedDishName: String?
    let determination: RiskDetermination
    /// 判明済みの対象食材・食事制限の表示名（呼び出し側が対象言語で解決済みのもの）。
    let matchedTargetNames: [String]
    /// 判定不可の理由（E02/E03、`UndeterminedReason.message(for:)`が提供）。`nil`なら表示しない。
    let reasonText: String?
    let displayLanguage: DisplayLanguage
    /// `.compactOverlay`でタップ時にS09へ遷移させる場合に指定する。`.detailed`では通常nil。
    var onSelectDetail: (() -> Void)?

    init(
        style: Style,
        japaneseDishName: String,
        translatedDishName: String? = nil,
        determination: RiskDetermination,
        matchedTargetNames: [String] = [],
        reasonText: String? = nil,
        displayLanguage: DisplayLanguage,
        onSelectDetail: (() -> Void)? = nil
    ) {
        self.style = style
        self.japaneseDishName = japaneseDishName
        self.translatedDishName = translatedDishName
        self.determination = determination
        self.matchedTargetNames = matchedTargetNames
        self.reasonText = reasonText
        self.displayLanguage = displayLanguage
        self.onSelectDetail = onSelectDetail
    }

    var body: some View {
        Group {
            if let onSelectDetail {
                Button(action: onSelectDetail) { cardBody }
                    .buttonStyle(.plain)
            } else {
                cardBody
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityIdentifier("RiskResultCardView_\(identifierSuffix)")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            dishNameView
            RiskBadgeView(determination: determination, displayLanguage: displayLanguage)
            if !matchedTargetNames.isEmpty {
                // `determination.foregroundColor`は`RiskBadgeView`が使う`determination.backgroundColor`
                // との組み合わせでのみコントラストが検証された固定色であり、ダークモードでは
                // `Color(.systemBackground)`（ここでの実際の背景）と組み合わせるとコントラストが
                // 不足する（TASK-053で発見）。三値の色分けは`RiskBadgeView`（自身の固定背景と対で使う）
                // が担うため、この補助テキストは背景に関わらず安全な色を使う。
                //
                // 当初`.secondary`にしていたが、`.font(.caption)`という小さいサイズとの組み合わせで
                // Appleの自動アクセシビリティ監査が断続的に"Contrast failed"を報告することが判明した
                // （`.secondary`は「主要文字より控えめ」という意図的なデザインであり、`.primary`ほど
                // 強くコントラストを保証しない）。`Color(.systemBackground)`との組み合わせで確実に
                // 監査を通すため、本Viewの補助テキストはすべて`.primary`を使う。
                Text(matchedTargetNames.joined(separator: "\u{3001}"))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reasonText, !reasonText.isEmpty {
                Text(reasonText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(style == .compactOverlay ? 8 : 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                // `determination.borderColor`（TASK-045）は`RiskBadgeView`自身の固定`backgroundColor`
                // との組み合わせでのみコントラストが検証された色であり、`cardBackground`
                // （システム標準の適応的背景）に対してはダークモードでコントラスト不足になりうる
                // （TASK-053で発見した"Pork"文字色の問題と同じ根本原因）。色・アイコン・完全ラベルの
                // 3要素はカード内の`RiskBadgeView`が単体で満たしているため、カード外枠は状態色を
                // 重複させず、どちらのモードでも安全な標準のseparator色を使う。
                .strokeBorder(Color(.separator), lineWidth: 1)
        )
    }

    private var dishNameView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(japaneseDishName)
                .font(.subheadline.bold())
            if let translatedDishName, translatedDishName != japaneseDishName {
                // `matchedTargetNames`/`reasonText`と同じ理由（上記コメント参照）で`.primary`を使う。
                Text(translatedDishName)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }

    /// `.compactOverlay`は写真の上に直接乗るため、完全に不透明なカード面を介してコントラスト比を
    /// 維持する（`docs/ui-design.md`「コントラスト基準」: 写真上へ直接文字を置かない）。TASK-053で、
    /// 半透明背景（`SafetyNoticeView`の`Color.orange.opacity(0.12)`）が黒背景と重なった際に
    /// アクセシビリティ監査の"Contrast failed"を断続的に引き起こすことを発見して以来、本Viewでも
    /// 半透明（`.opacity(0.96)`）ではなく完全な不透明色に統一する。
    private var cardBackground: Color {
        Color(.systemBackground)
    }

    private var identifierSuffix: String {
        switch style {
        case .compactOverlay: "compact"
        case .detailed: "detailed"
        }
    }

    /// 状態・対象料理・判明している対象食材・店員確認の推奨を含める
    /// （`docs/ui-design.md`「三値判定表示ルール」のaccessibilityLabel要件）。
    private var accessibilityLabelText: String {
        var parts: [String] = []
        if let translatedDishName, !translatedDishName.isEmpty {
            parts.append(translatedDishName)
        } else {
            parts.append(japaneseDishName)
        }
        parts.append(determination.displayLabel(for: displayLanguage))
        if !matchedTargetNames.isEmpty {
            parts.append(matchedTargetNames.joined(separator: ", "))
        }
        if let reasonText, !reasonText.isEmpty {
            parts.append(reasonText)
        }
        parts.append(RiskResultCardText.staffConfirmation.value(for: displayLanguage))
        return parts.joined(separator: ". ")
    }
}

/// `RiskResultCardView`のaccessibilityLabelに含める、店員確認推奨の短い定型句。
/// 常時表示される`SafetyNoticeView.persistentResultNotice`の全文とは別に、VoiceOverで個々の
/// カードを読み上げた際にも単独で完結した案内になるようにする。
private enum RiskResultCardText {
    static let staffConfirmation = LocalizedText(
        english: "Please confirm with staff.",
        traditionalChinese: "請向店員確認。",
        simplifiedChinese: "请向店员确认。",
        korean: "직원에게 확인해 주세요."
    )
}

#Preview {
    VStack(spacing: 16) {
        RiskResultCardView(
            style: .compactOverlay,
            japaneseDishName: "ラフテー",
            translatedDishName: "Braised Pork Belly",
            determination: .likelyContains,
            matchedTargetNames: ["Pork"],
            displayLanguage: .english
        ) {}
        RiskResultCardView(
            style: .detailed,
            japaneseDishName: "沖縄そば",
            translatedDishName: "Okinawa Soba",
            determination: .undetermined,
            displayLanguage: .english
        )
    }
    .padding()
}
