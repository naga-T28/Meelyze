import SwiftUI

/// `RiskDetermination`（Issue #17）の三値それぞれについて、`docs/ui-design.md`「三値判定表示ルール」の
/// 表示対応表が定める完全な状態ラベル・SF Symbols・色トークンを提供する。
///
/// `RiskResultCardView`（TASK-046）・`ErrorStateCardView`（TASK-050）など、同じ三値を扱う他の
/// Componentからも同一の値を参照できるようにし、色・アイコン・ラベルの重複定義によるズレを防ぐ。
/// 色は16進数RGB（`foregroundHex`等）としてもテスト可能な形で公開し、`docs/ui-design.md`のコントラスト
/// 測定値（AA適合）との対応を直接検証できるようにする。
extension RiskDetermination {
    /// 完全な状態ラベル。判定結果はアプリの中核情報であり、日本語原文のみで表示すると母語話者が
    /// 理解できないため、`LocalizedText`でMVP対象4言語へ翻訳した文言を返す
    /// （`docs/requirements.md` FR-5.3の対象言語）。
    func displayLabel(for language: DisplayLanguage) -> String {
        switch self {
        case .likelyContains: RiskDeterminationText.likelyContains.value(for: language)
        case .noRecordedMatch: RiskDeterminationText.noRecordedMatch.value(for: language)
        case .undetermined: RiskDeterminationText.undetermined.value(for: language)
        }
    }

    var sfSymbolName: String {
        switch self {
        case .likelyContains: "exclamationmark.triangle.fill"
        case .noRecordedMatch: "info.circle.fill"
        case .undetermined: "questionmark.diamond.fill"
        }
    }

    var foregroundHex: UInt32 {
        switch self {
        case .likelyContains: 0xB42318
        case .noRecordedMatch: 0x344054
        case .undetermined: 0x93370D
        }
    }

    var backgroundHex: UInt32 {
        switch self {
        case .likelyContains: 0xFEF3F2
        case .noRecordedMatch: 0xF2F4F7
        case .undetermined: 0xFFFAEB
        }
    }

    var borderHex: UInt32 {
        switch self {
        case .likelyContains: 0xB42318
        case .noRecordedMatch: 0x475467
        case .undetermined: 0xB54708
        }
    }

    var foregroundColor: Color { Color(hex: foregroundHex) }
    var backgroundColor: Color { Color(hex: backgroundHex) }
    var borderColor: Color { Color(hex: borderHex) }
}

/// `RiskBadgeView`の状態ラベル文言。MVP対象4言語で固定の意味を維持する
/// （`docs/ui-design.md`「非断定表現ルール」に反する表現を含まない）。
private enum RiskDeterminationText {
    static let likelyContains = LocalizedText(
        english: "Likely Contains",
        traditionalChinese: "可能含有",
        simplifiedChinese: "可能含有",
        korean: "함유 가능성 높음"
    )

    /// `収録データ上は`に相当する限定を省略しない（`docs/ui-design.md`表示対応表の必須注記）。
    static let noRecordedMatch = LocalizedText(
        english: "No Match in Records",
        traditionalChinese: "收錄資料中無相符",
        simplifiedChinese: "收录数据中无相符",
        korean: "등록된 데이터상 해당 없음"
    )

    static let undetermined = LocalizedText(
        english: "Undetermined",
        traditionalChinese: "無法判定",
        simplifiedChinese: "无法判定",
        korean: "판정 불가"
    )
}

/// #10で確定した三値判定を、色・アイコン・完全な状態ラベルの3要素で常に同時表示するバッジ。
/// `docs/ui-design.md`「三値判定表示ルール」を正とし、色またはアイコンだけで状態を表さない。
///
/// Issue #17/#19が返す`RiskDetermination`をそのまま表示するだけとし、View内でEvidenceから三値を
/// 再判定しない。料理名・判明済み対象食材・常時注意文を含めた完全なアクセシビリティ体験は、本Viewを
/// 組み込む`RiskResultCardView`（TASK-046）が`.accessibilityElement(children: .combine)`で
/// 結合する形で完成させる（本Viewの`accessibilityLabel`は状態そのものの完全な説明に留める）。
struct RiskBadgeView: View {
    let determination: RiskDetermination
    let displayLanguage: DisplayLanguage

    var body: some View {
        Label {
            Text(determination.displayLabel(for: displayLanguage))
                .font(.subheadline.bold())
        } icon: {
            Image(systemName: determination.sfSymbolName)
                .accessibilityHidden(true)
        }
        .foregroundStyle(determination.foregroundColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(determination.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(determination.borderColor, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(determination.displayLabel(for: displayLanguage))
        .accessibilityIdentifier("RiskBadgeView_\(identifierSuffix)")
    }

    private var identifierSuffix: String {
        switch determination {
        case .likelyContains: "likelyContains"
        case .noRecordedMatch: "noRecordedMatch"
        case .undetermined: "undetermined"
        }
    }
}

private extension Color {
    /// `0xRRGGBB`形式の16進数からColorを作る。`docs/ui-design.md`の色トークンをコード上でも
    /// 同じ表記のまま扱えるようにするための変換専用ヘルパー。
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        RiskBadgeView(determination: .likelyContains, displayLanguage: .english)
        RiskBadgeView(determination: .noRecordedMatch, displayLanguage: .english)
        RiskBadgeView(determination: .undetermined, displayLanguage: .english)
    }
    .padding()
}
