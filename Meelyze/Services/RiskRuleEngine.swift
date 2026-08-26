import Foundation

/// TASK-031のFact（DB由来）とLLM由来のPositive/Negativeシグナルから、三値とEvidenceを安全側へ
/// 集約する決定論的なRule Engine。料理DBを保存・検索するRepository層やSwiftDataへは一切依存しない
/// pure Swiftで、値型の入出力だけを扱う。
///
/// 判定優先順位（`task/README-issue17.md`「該当なしの必要条件」「LLM Positiveの扱い」「複数解釈」）:
/// 1. いずれかのFactが選択済みtargetとの確定的な一致（`confirmed` / `typical`）を持てば`likelyContains`
/// 2. 一致がなく、かつ未知語・未解決・曖昧候補・DB取得失敗・`variesByStore`のいずれの不確実性もなければ
///    `noRecordedMatch`（対象targetについてFactが1件もない場合もこの不確実性に含める）
/// 3. 上記いずれにも該当しなければ`undetermined`
/// その上で、LLM Positiveシグナルは`noRecordedMatch`のみを`undetermined`へ単調に押し上げる補助Evidence
/// として使う。LLM Negativeシグナルは判定へ一切影響しない（安全根拠として使わない）。
struct RiskRuleEngine {
    init() {}

    /// UserProfileが選択した`targets`すべてについて、1項目分の`[RiskFact]`と`[RiskLLMSignal]`から
    /// 判定結果を返す。`facts`・`llmSignals`に一切登場しないtargetでも`.undetermined`を返し、
    /// 選択済みtargetが結果から静かに欠落することを防ぐ（欠落はUIに「安全」と誤読されかねないため）。
    /// target の並び順は`targets`をそのまま保ち、末尾に`facts`・`llmSignals`にだけ登場した
    /// target（本来は起こらない想定の防御的なケース）を初出順で追加する。
    func evaluate(targets: [RiskTarget], facts: [RiskFact], llmSignals: [RiskLLMSignal] = []) -> [RiskEvaluationResult] {
        orderedTargets(explicitTargets: targets, facts: facts, llmSignals: llmSignals).map { target in
            evaluate(
                target: target,
                facts: facts.filter { $0.target == target },
                llmSignals: llmSignals.filter { $0.target == target }
            )
        }
    }

    private func orderedTargets(
        explicitTargets: [RiskTarget],
        facts: [RiskFact],
        llmSignals: [RiskLLMSignal]
    ) -> [RiskTarget] {
        var seen = Set<RiskTarget>()
        return (explicitTargets + facts.map(\.target) + llmSignals.map(\.target)).filter { seen.insert($0).inserted }
    }

    private func evaluate(target: RiskTarget, facts: [RiskFact], llmSignals: [RiskLLMSignal]) -> RiskEvaluationResult {
        let hasConfirmedMatch = facts.contains { fact in
            fact.resolution == .resolved
                && fact.databaseMatches.contains { $0.confidence == .confirmed || $0.confidence == .typical }
        }
        // Factが1件もない（DBを一度も確認できていない）ことも、`noRecordedMatch`を妨げる不確実性として扱う。
        // 対象料理の解決が一意であることが「該当なし」の必要条件であるため（README「該当なしの必要条件」）。
        let hasUnresolvedUncertainty = facts.isEmpty || facts.contains { $0.resolution != .resolved }
        let hasVariesByStoreUncertainty = facts.contains { fact in
            fact.resolution == .resolved && fact.databaseMatches.contains { $0.confidence == .variesByStore }
        }

        var determination: RiskDetermination
        if hasConfirmedMatch {
            determination = .likelyContains
        } else if hasUnresolvedUncertainty || hasVariesByStoreUncertainty {
            determination = .undetermined
        } else {
            determination = .noRecordedMatch
        }

        // LLM Negativeは安全根拠として一切使わない（読み飛ばす）。LLM Positiveは、DBが確認した
        // `noRecordedMatch`に矛盾する場合のみ、少なくとも`undetermined`へ単調に押し上げる。
        let positiveSignals = llmSignals.filter { $0.polarity == .positive }
        if determination == .noRecordedMatch, !positiveSignals.isEmpty {
            determination = .undetermined
        }

        let databaseEvidence = facts.flatMap(\.evidence)
        let llmEvidence = positiveSignals.map { signal in
            RiskEvidence(kind: .llmInference, sourceEvidence: signal.sourceEvidence, inferredOrigin: .llmPositiveInference)
        }

        return RiskEvaluationResult(target: target, determination: determination, evidence: databaseEvidence + llmEvidence)
    }
}
