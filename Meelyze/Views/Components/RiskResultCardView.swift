import SwiftUI
import UIKit

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
    /// `.compactOverlay`の文字サイズ（`ResultOverlayView`の`OverlayTagFontMetrics`が対象料理の
    /// OCR文字の高さから計算する）。`.detailed`では使わない。`.scaleEffect`によるtransformではなく
    /// 実際のフォントサイズとして渡すことで、`XCTest.performAccessibilityAudit()`のコントラスト判定が
    /// 参照するアクセシビリティフレームと実描画のずれを避ける（FIX-015）。
    var compactFontSize: CGFloat = 15
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
        compactFontSize: CGFloat = 15,
        onSelectDetail: (() -> Void)? = nil
    ) {
        self.style = style
        self.japaneseDishName = japaneseDishName
        self.translatedDishName = translatedDishName
        self.determination = determination
        self.matchedTargetNames = matchedTargetNames
        self.reasonText = reasonText
        self.displayLanguage = displayLanguage
        self.compactFontSize = compactFontSize
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

    @ViewBuilder
    private var cardBody: some View {
        switch style {
        case .compactOverlay: compactOverlayBody
        case .detailed: detailedBody
        }
    }

    /// S08（Google翻訳のカメラ翻訳のような、原文の上に直接載せる最小限のタグ）。FIX-015で
    /// 日本語原文・完全な状態ラベル文字列・判明済み対象食材・判定不可理由をすべて省略し、
    /// 翻訳済み料理名（翻訳不可時は日本語原文、`displayDishName`）とアイコンだけを表示する。
    /// これらの詳細情報自体は失われず、タップ後のS09（`.detailed`）と`accessibilityLabelText`
    /// （VoiceOver）には引き続きすべて含まれる。
    ///
    /// 「色またはアイコンだけで状態を表さない」（`docs/ui-design.md`「三値判定表示ルール」）は、
    /// アイコン（`RiskBadgeView(showsLabel: false)`）を色と同時に必ず表示することで満たす。
    /// 完全な状態ラベル文字列の省略は、タップ一つでS09へ到達できることを前提にした本Fixの
    /// 意図的な仕様変更であり、`docs/ui-design.md`側にも同時に反映済み。
    private var compactOverlayBody: some View {
        HStack(spacing: 4) {
            RiskBadgeView(determination: determination, displayLanguage: displayLanguage, showsLabel: false)
            Text(displayDishName)
                .fixedSize(horizontal: false, vertical: true)
        }
        // `compactFontSize`をHStack単位で適用し、アイコン（`RiskBadgeView`のSF Symbols）と文字の
        // 両方へ実際のフォントサイズとして伝播させる（`.scaleEffect`のtransformは使わない。上記
        // `compactFontSize`のコメント参照）。`UIFontMetrics`でDynamic Typeの設定値に応じて
        // 追加でスケールさせる（固定`.system(size:)`のままだと`XCTest.performAccessibilityAudit()`
        // が"Dynamic Type font sizes are unsupported"を報告する。FIX-015作業ログ参照）。
        .font(.system(size: UIFontMetrics.default.scaledValue(for: compactFontSize), weight: .bold))
        // `determination.foregroundColor`は`determination.backgroundColor`との組み合わせでのみ
        // コントラスト検証済み（`RiskBadgeView`と同一トークン）。`.primary`等の適応色は使わない。
        .foregroundStyle(determination.foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(determination.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(determination.borderColor, lineWidth: 1)
        )
    }

    /// 翻訳済み料理名。翻訳不可時は日本語原文を表示し、S08をブロックしない
    /// （`docs/ui-design.md`FR-4.4/AC-3.3の原則を踏襲、TASK-048と同じ判断）。
    private var displayDishName: String {
        guard let translatedDishName, !translatedDishName.isEmpty else { return japaneseDishName }
        return translatedDishName
    }

    /// S09（料理詳細画面の見出し）。日本語原文・翻訳・完全な三値バッジ・判明済み対象食材・
    /// 判定不可理由を余白広く表示する、変更前と同じ内容。
    private var detailedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            dishNameView
            RiskBadgeView(determination: determination, displayLanguage: displayLanguage)
            if !matchedTargetNames.isEmpty {
                // `.secondary`は`.font(.caption)`という小さいサイズとの組み合わせでAppleの自動
                // アクセシビリティ監査が断続的に"Contrast failed"を報告することが判明した
                // （TASK-053。「主要文字より控えめ」という意図的なデザインであり、`.primary`ほど
                // 強くコントラストを保証しないため）。`Color(.systemBackground)`との組み合わせで
                // 確実に監査を通すため、本Viewの補助テキストはすべて`.primary`を使う。
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                // `determination.borderColor`（TASK-045）は`RiskBadgeView`自身の固定`backgroundColor`
                // との組み合わせでのみコントラストが検証された色であり、`Color(.systemBackground)`
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
