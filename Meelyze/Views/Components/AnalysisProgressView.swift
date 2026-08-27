import SwiftUI

/// S07 OCR・解析中の表示。状態モデルはIssue #19が提供済みの`MenuAnalysisViewModel.AnalysisState`を
/// そのまま使う（本Viewは表示専用で、状態を再判定しない）。
///
/// **既知の制約**: `docs/ui-design.md`「Loading」節はFigma上の4フェーズ（文字を読み取り中／
/// 料理名を整理／データベースと照合／判定結果を作成）を`AnalysisProgressView`へ表示するとしているが、
/// `AnalysisState`（Issue #19）は`idle/processing/completed/failed`の4状態のみを公開し、
/// `processing`中のフェーズ単位の進捗を区別しない。フェーズ単位の状態を追加するには
/// `MenuAnalysisService`/`RiskEvaluationService`（Issue #17/#19の既存・テスト済みコード）へ進捗報告
/// の仕組みを新設する必要があり、これは本タスク（表示専用、既存状態モデルをそのまま使う前提）の
/// 範囲を超える。架空の進捗率・フェーズを表示しない（`docs/ui-design.md`: 「処理時間から作った
/// 架空の割合は表示せず」）という原則を優先し、本Viewは実際に区別できる情報（processing中である
/// こと）だけを、フェーズを特定しない一般的な文言で示す。フェーズ単位の追跡が必要になった場合は
/// 別Issueで状態モデル自体の拡張を検討する。
struct AnalysisProgressView: View {
    let displayLanguage: DisplayLanguage

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            Text(AnalysisProgressText.message.value(for: displayLanguage))
                .font(.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AnalysisProgressText.message.value(for: displayLanguage))
        // processingへ入った時点でVoiceOverへ状態変化を通知する（フェーズ内訳がなくても、解析が
        // 開始されたこと自体は明確に伝える）。
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("AnalysisProgressView")
    }
}

private enum AnalysisProgressText {
    static let message = LocalizedText(
        english: "Analyzing the menu\u{2026}",
        traditionalChinese: "正在解析菜單\u{2026}",
        simplifiedChinese: "正在解析菜单\u{2026}",
        korean: "메뉴를 분석하고 있습니다\u{2026}"
    )
}

#Preview {
    AnalysisProgressView(displayLanguage: .english)
}
