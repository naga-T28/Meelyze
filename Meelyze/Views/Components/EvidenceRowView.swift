import SwiftUI

/// `RiskEvidence`のkindをDB由来／LLM由来／未解決の3系統に分類する（Issue #20完了条件
/// 「DB由来とLLM由来の補助情報を区別できる」）。`internal`にしているのはテストから直接検証する
/// ため（`UndeterminedReason`と同じ設計判断）。
enum EvidenceOrigin: Equatable {
    case database
    case llm
    case unresolved

    init(kind: RiskEvidenceKind) {
        switch kind {
        case .explicit, .normalized, .dishDatabase: self = .database
        case .llmInference: self = .llm
        case .unknown: self = .unresolved
        }
    }

    var label: LocalizedText {
        switch self {
        case .database: EvidenceRowText.databaseOrigin
        case .llm: EvidenceRowText.llmOrigin
        case .unresolved: EvidenceRowText.unresolvedOrigin
        }
    }

    var color: Color {
        switch self {
        case .database: .blue
        case .llm: .purple
        case .unresolved: .gray
        }
    }
}

/// 1件の`RiskEvidence`（Issue #17）を行単位で表示する。OCR原文・正規化結果・DB照合結果・
/// LLM由来の補助情報・unknown情報を、DB由来／LLM由来の区別を示すタグとともに表示する
/// （S09、`docs/ui-design.md`「料理詳細・判定根拠」）。判定そのものは再計算しない。
struct EvidenceRowView: View {
    let evidence: RiskEvidence
    let displayLanguage: DisplayLanguage

    private var origin: EvidenceOrigin { EvidenceOrigin(kind: evidence.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            originBadge

            if let rawText = ocrOriginalText {
                labeledLine(label: EvidenceRowText.ocrOriginal, value: rawText)
            }
            if let normalizedText = normalizedTextIfChanged {
                labeledLine(label: EvidenceRowText.normalized, value: normalizedText)
            }
            if let canonicalName = evidence.resolvedEntity?.canonicalName {
                labeledLine(label: EvidenceRowText.databaseMatch, value: canonicalName)
            }
            // 以下`.caption`テキストは`RiskResultCardView`と同じ理由（TASK-053で判明: `.secondary`は
            // ライトモードでAAコントラスト基準の4.5:1を満たさない）で`.primary`を使う。
            if case .llmPositiveInference = evidence.inferredOrigin {
                Text(EvidenceRowText.llmInferenceNote.value(for: displayLanguage))
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            if evidence.kind == .unknown {
                Text(unknownDescription)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            if evidence.isHiddenIngredient {
                Text(EvidenceRowText.hiddenIngredient.value(for: displayLanguage))
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("EvidenceRowView_\(originIdentifier)")
    }

    private var originBadge: some View {
        Text(origin.label.value(for: displayLanguage))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(origin.color.opacity(0.15)))
            .foregroundStyle(origin.color)
    }

    private var ocrOriginalText: String? {
        let text = evidence.sourceEvidence.map(\.rawText).joined(separator: "\u{3001}")
        return text.isEmpty ? nil : text
    }

    private var normalizedTextIfChanged: String? {
        guard let normalization = evidence.normalization, normalization.normalizedText != normalization.originalText else {
            return nil
        }
        return normalization.normalizedText
    }

    private var unknownDescription: String {
        UndeterminedReason.from([evidence])?.message(for: displayLanguage)
            ?? EvidenceRowText.unresolvedGeneric.value(for: displayLanguage)
    }

    private func labeledLine(label: LocalizedText, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label.value(for: displayLanguage))
                .font(.caption.bold())
                .foregroundStyle(.primary)
            Text(value)
                .font(.caption)
        }
    }

    private var originIdentifier: String {
        switch origin {
        case .database: "database"
        case .llm: "llm"
        case .unresolved: "unresolved"
        }
    }
}

private enum EvidenceRowText {
    static let ocrOriginal = LocalizedText(
        english: "OCR text",
        traditionalChinese: "OCR原文",
        simplifiedChinese: "OCR原文",
        korean: "OCR 원문"
    )

    static let normalized = LocalizedText(
        english: "Normalized",
        traditionalChinese: "正規化結果",
        simplifiedChinese: "正规化结果",
        korean: "정규화 결과"
    )

    static let databaseMatch = LocalizedText(
        english: "Matched record",
        traditionalChinese: "資料庫比對結果",
        simplifiedChinese: "数据库比对结果",
        korean: "데이터베이스 일치 결과"
    )

    static let llmInferenceNote = LocalizedText(
        english: "AI-inferred possibility, not confirmed by our database.",
        traditionalChinese: "由AI推論的可能性，尚未經資料庫確認。",
        simplifiedChinese: "由AI推断的可能性，尚未经数据库确认。",
        korean: "AI가 추론한 가능성이며 데이터베이스로 확인되지 않았습니다."
    )

    static let unresolvedGeneric = LocalizedText(
        english: "Could not be resolved.",
        traditionalChinese: "無法解析。",
        simplifiedChinese: "无法解析。",
        korean: "확인할 수 없습니다."
    )

    static let hiddenIngredient = LocalizedText(
        english: "Hidden ingredient (not named on the menu)",
        traditionalChinese: "隱藏食材（菜單上未標示）",
        simplifiedChinese: "隐藏食材（菜单上未标示）",
        korean: "숨은 재료 (메뉴에 표기되지 않음)"
    )

    /// DB由来（explicit/normalized/dishDatabase）とLLM由来（llmInference）・未解決（unknown）を
    /// 区別するためのタグ文言（Issue #20完了条件「DB由来とLLM由来の補助情報を区別できる」）。
    static let databaseOrigin = LocalizedText(
        english: "Database",
        traditionalChinese: "資料庫",
        simplifiedChinese: "数据库",
        korean: "데이터베이스"
    )

    static let llmOrigin = LocalizedText(
        english: "AI Inference",
        traditionalChinese: "AI推論",
        simplifiedChinese: "AI推断",
        korean: "AI 추론"
    )

    static let unresolvedOrigin = LocalizedText(
        english: "Unresolved",
        traditionalChinese: "未解決",
        simplifiedChinese: "未解决",
        korean: "미해결"
    )
}
