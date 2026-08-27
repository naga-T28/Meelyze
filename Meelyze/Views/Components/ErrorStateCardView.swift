import SwiftUI

/// 判定不可（E02/E03）の理由を、`docs/ui-design.md`「異常系UI」の必須文言でユーザー向けに表現する。
///
/// - `.menuUnderstandingIncomplete`（E02）: Foundation Models利用不可・Menu Understanding未完了に
///   起因する。`RiskInferredOrigin.itemUnderstandingIncomplete`が根拠。
/// - `.databaseUnresolved`（E03）: DB未一致・Alias曖昧・DB取得失敗に起因する。
///   `RiskInferredOrigin.unresolvedTerm` `.ambiguousCandidates` `.databaseFetchFailed`、または
///   `kind == .unknown`で`inferredOrigin`が`nil`（Alias解決自体の失敗、
///   `DefaultMenuAnalysisService.undeterminedItemResult`参照）が根拠。
enum UndeterminedReason: Equatable {
    case menuUnderstandingIncomplete
    case databaseUnresolved

    func message(for language: DisplayLanguage) -> String {
        switch self {
        case .menuUnderstandingIncomplete: UndeterminedReasonText.menuUnderstandingIncomplete.value(for: language)
        case .databaseUnresolved: UndeterminedReasonText.databaseUnresolved.value(for: language)
        }
    }

    /// 対象の`RiskEvidence`一覧から該当理由を判定する。Menu Understanding起因を優先する
    /// （より根本的な原因であるため）。三値判定表示ルールが対象とする理由に該当しなければ`nil`
    /// （Evidence不足等、E02/E03のいずれでもない一般的な判定不可）。
    static func from(_ evidence: [RiskEvidence]) -> UndeterminedReason? {
        if evidence.contains(where: { evidence in
            if case .itemUnderstandingIncomplete = evidence.inferredOrigin { return true }
            return false
        }) {
            return .menuUnderstandingIncomplete
        }
        if evidence.contains(where: { evidence in
            switch evidence.inferredOrigin {
            case .unresolvedTerm, .ambiguousCandidates, .databaseFetchFailed: return true
            case .llmPositiveInference, .itemUnderstandingIncomplete, nil: return false
            }
        }) {
            return .databaseUnresolved
        }
        if evidence.contains(where: { $0.kind == .unknown && $0.inferredOrigin == nil }) {
            return .databaseUnresolved
        }
        return nil
    }
}

extension MenuAnalysisSummary {
    /// E02（メニュー解析利用不可）のInline banner表示条件。`docs/ui-design.md`のE02定義
    /// 「Foundation Modelsが非対応・利用不可・実行時エラーとなり…対象料理を解決できない場合」は
    /// 単純な利用不可（`.modelUnavailable`）だけでなく実行時エラー全般（`.generationFailed`
    /// `.sourceMappingInvalid`等）を含むため、Menu Understanding起因の失敗全般を対象とする。
    /// また、失敗が1件以上あるにもかかわらず`items`が1件もない場合（フォールバックが効かなかった
    /// 失敗理由の場合）も、ユーザーへ「解析できなかった」ことを示すため対象に含める。
    var hasModelUnavailableCondition: Bool {
        if !menuUnderstandingFailures.isEmpty { return true }
        if items.isEmpty && !failures.isEmpty { return true }
        return items.contains { item in
            item.results.flatMap(\.evidence).contains { evidence in
                if case .itemUnderstandingIncomplete = evidence.inferredOrigin { return true }
                return false
            }
        }
    }

    /// Menu Understanding起因の失敗一覧（利用不可・実行時エラーいずれも含む）。
    var menuUnderstandingFailures: [RiskEvaluationFailure] {
        failures.filter { failure in
            if case .menuUnderstanding = failure.reason { return true }
            return false
        }
    }

    /// 上記失敗のいずれかが一時的な実行エラーと判別できる場合のみ真（`docs/ui-design.md`:
    /// 再試行可否を推測で追加しない）。
    var isModelUnavailableFailureRetryable: Bool {
        menuUnderstandingFailures.contains { $0.retryability == .retryable }
    }
}

private enum UndeterminedReasonText {
    /// E02の対象料理向け理由（画面レベルのバナー文言はErrorStateCardTextを参照）。
    static let menuUnderstandingIncomplete = LocalizedText(
        english: "Analysis for this dish could not be completed.",
        traditionalChinese: "無法完成此料理的解析。",
        simplifiedChinese: "无法完成此菜品的解析。",
        korean: "이 요리에 대한 분석을 완료할 수 없었습니다."
    )

    /// E03の必須文言（`docs/ui-design.md`「異常系UI」E03行）をそのまま翻訳する。
    static let databaseUnresolved = LocalizedText(
        english: "This dish could not be matched to our records, so we cannot determine what it contains.",
        traditionalChinese: "此料理無法與收錄資料相符，因此無法判定其中含有的食材。",
        simplifiedChinese: "此菜品无法与收录数据相符，因此无法判定其中含有的食材。",
        korean: "이 요리는 등록된 데이터와 일치하지 않아 포함된 재료를 판정할 수 없습니다."
    )
}

/// E02（メニュー解析利用不可）のS08向けInline banner。E03は専用モーダル・バナーを設けず、
/// `RiskResultCardView`の`reasonText`（本ファイルの`UndeterminedReason.databaseUnresolved`）
/// だけで表現する（`docs/ui-design.md`「異常系UI」E03: "S08/S09のRiskResultCardView"）。
///
/// 成功済みの料理・Evidence・翻訳結果は`ResultOverlayView`側で保持したまま、本バナーは画面内に
/// 1つだけ追加表示する（未解決の項目だけを縮退させ、成功結果を隠さない）。
struct ErrorStateCardView: View {
    let displayLanguage: DisplayLanguage
    /// 一時的な実行エラーと判別できる場合のみ指定する（`docs/ui-design.md`: 再試行可否を推測で
    /// 追加しない）。
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(ErrorStateCardText.title.value(for: displayLanguage))
                    .font(.subheadline.bold())
            } icon: {
                Image(systemName: RiskDetermination.undetermined.sfSymbolName)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(RiskDetermination.undetermined.foregroundColor)

            // `.secondary`（adaptive）は本Viewの固定背景`RiskDetermination.undetermined.backgroundColor`
            // （モードに関わらず変化しない`0xFFFAEB`）と組み合わせると、ライトモードでは3:1台、
            // ダークモードでは`.secondary`が明るいグレーへ反転するため逆に背景と近づいてしまい、
            // どちらのモードでもAAの4.5:1を満たせない（TASK-053で判明した"Pork"文字色問題と対の
            // 逆パターン: 今度は固定背景に対して適応的な文字色を使ったことが原因）。titleと同じ
            // 固定色`RiskDetermination.undetermined.foregroundColor`を使い、背景色との組み合わせを
            // 固定ペアのまま保つ。
            Text(ErrorStateCardText.subtitle.value(for: displayLanguage))
                .font(.caption)
                .foregroundStyle(RiskDetermination.undetermined.foregroundColor)
                .fixedSize(horizontal: false, vertical: true)

            if let onRetry {
                Button(action: onRetry) {
                    Text(ErrorStateCardText.retry.value(for: displayLanguage))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ErrorStateCardRetryButton")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(RiskDetermination.undetermined.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(RiskDetermination.undetermined.borderColor, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ErrorStateCardView_E02InlineBanner")
    }
}

/// `ErrorStateCardView`（E02 Inline banner）の固定文言。`docs/ui-design.md`「異常系UI」E02行の
/// 必須文言をそのまま翻訳する。技術的なエラー名・コードは含めない。
private enum ErrorStateCardText {
    static let title = LocalizedText(
        english: "Some menu items could not be analyzed",
        traditionalChinese: "部分菜單項目無法解析",
        simplifiedChinese: "部分菜单项目无法解析",
        korean: "메뉴 일부를 분석할 수 없었습니다"
    )

    static let subtitle = LocalizedText(
        english: "Dishes that could not be checked are shown as \u{201C}Undetermined.\u{201D}",
        traditionalChinese: "無法確認的料理將顯示為「無法判定」。",
        simplifiedChinese: "无法确认的菜品将显示为“无法判定”。",
        korean: "확인할 수 없는 요리는 '판정 불가'로 표시됩니다."
    )

    static let retry = LocalizedText(
        english: "Retry",
        traditionalChinese: "重試",
        simplifiedChinese: "重试",
        korean: "다시 시도"
    )
}

#Preview {
    VStack(spacing: 16) {
        ErrorStateCardView(displayLanguage: .english) {}
        RiskResultCardView(
            style: .compactOverlay,
            japaneseDishName: "沖縄そば",
            determination: .undetermined,
            reasonText: UndeterminedReason.databaseUnresolved.message(for: .english),
            displayLanguage: .english
        )
    }
    .padding()
}
