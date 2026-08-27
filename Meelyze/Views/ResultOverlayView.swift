import SwiftUI
import UIKit

/// S08 判定結果オーバーレイ画面。撮影したメニュー画像上に、料理ごとの三値判定結果をBounding Boxの
/// 実位置へ重畳表示する（`docs/mvp-scope.md` §2.4, `docs/requirements.md` NFR-4.6, AC-1.1）。
///
/// 画像内の位置を保持するため、危険度順への並べ替えは行わない。VoiceOver走査順のみ
/// `含有の可能性が高い`→`判定不可`→`収録データ上は該当なし`の順に調整する
/// （`docs/ui-design.md`「三値判定表示ルール」。ユーザー確認済み: 別建ての結果一覧ビューは作らない）。
///
/// 「店員に確認」ボタン自体はIssue #21が後から追加するため、本Viewでは作らない
/// （`docs/ui-design.md`実装責任境界表「#21 | S10とS08/S09からの常設導線」）。S09（料理詳細）への
/// 遷移は`NavigationStack`＋軽量なHashable route（`MenuUnderstandingItemReference.ordinal`）で行う
/// （`OnboardingFlowView`と同じパターン）。S09本体はTASK-051の`DishDetailView`。
struct ResultOverlayView: View {
    let imageData: Data
    let summary: MenuAnalysisSummary
    let displayLanguage: DisplayLanguage
    let translationService: any DishNameTranslationService
    var onRetake: () -> Void
    var onRetryAnalysis: (() -> Void)?

    @State private var path: [Int] = []
    @State private var translatedNames: [Int: String] = [:]

    private let boundingBoxConverter = BoundingBoxConverter()

    private var uiImage: UIImage? { UIImage(data: imageData) }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    imageView
                    ForEach(summary.items, id: \.reference.ordinal) { item in
                        overlayCard(for: item, containerSize: geometry.size)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                topNotices
            }
            .safeAreaInset(edge: .bottom) {
                retakeButton
            }
            .navigationDestination(for: Int.self) { ordinal in
                destinationView(for: ordinal)
            }
        }
        .task(id: summary.items.map(\.reference.ordinal)) {
            await translateAllDishNames()
        }
    }

    // MARK: - Image + overlay

    @ViewBuilder
    private var imageView: some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            Color.black
        }
    }

    private func overlayCard(for item: MenuAnalysisItemResult, containerSize: CGSize) -> some View {
        let rect = boundingBoxConverter.convertUnion(
            item.boundingBoxes,
            imageSize: uiImage?.size ?? containerSize,
            containerSize: containerSize
        ) ?? CGRect(origin: .zero, size: containerSize)
        let determination = item.overallDetermination ?? .undetermined
        let evidence = item.results.flatMap(\.evidence)
        let matchedNames = item.results
            .filter { $0.determination == .likelyContains }
            .map { $0.target.localizedName(for: displayLanguage) }
        let reasonText = determination == .undetermined
            ? UndeterminedReason.from(evidence)?.message(for: displayLanguage)
            : nil

        return RiskResultCardView(
            style: .compactOverlay,
            japaneseDishName: item.reference.originalText,
            translatedDishName: translatedNames[item.reference.ordinal],
            determination: determination,
            matchedTargetNames: matchedNames,
            reasonText: reasonText,
            displayLanguage: displayLanguage
        ) {
            path.append(item.reference.ordinal)
        }
        .position(x: rect.midX, y: rect.midY)
        .accessibilitySortPriority(sortPriority(for: determination))
    }

    /// `docs/ui-design.md`「三値判定表示ルール」: 別途表示する結果summary/listとVoiceOver走査順は
    /// 含有の可能性が高い→判定不可→収録データ上は該当なしの順とする。画像内の表示位置自体は
    /// 並べ替えない（`.position`はBounding Box由来のまま）。
    private func sortPriority(for determination: RiskDetermination) -> Double {
        switch determination {
        case .likelyContains: 3
        case .undetermined: 2
        case .noRecordedMatch: 1
        }
    }

    // MARK: - Notices

    @ViewBuilder
    private var topNotices: some View {
        VStack(spacing: 8) {
            if summary.hasModelUnavailableCondition {
                ErrorStateCardView(
                    displayLanguage: displayLanguage,
                    onRetry: summary.isModelUnavailableFailureRetryable ? onRetryAnalysis : nil
                )
            }
            SafetyNoticeView(variant: .persistentResultNotice, displayLanguage: displayLanguage)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// TASK-053で3段階の修正を経た:
    /// 1. 当初`.buttonStyle(.bordered)` + `.background(.regularMaterial)`が、有効な撮影画像がない
    ///    場合（本Viewの`imageView`が黒背景にフォールバックする場合）に`.regularMaterial`が暗く
    ///    合成され、既定の青文字とのコントラストがダークモードで断続的に"Contrast failed"となった。
    /// 2. 白文字＋`Color.accentColor`背景（`OCRFailureView`と同じパターン）へ変更したところ、今度は
    ///    ライトモードで白文字とiOSシステム標準の青とのコントラストが4.5:1をわずかに下回り、
    ///    断続的に失敗した（手動計算で約4.02:1）。
    /// 3. `.foregroundStyle(.primary)` + `Color(.systemBackground)`へ変更したが、`Button`の既定style
    ///    がlabelへ自動的にaccent tintを適用するため`.foregroundStyle(.primary)`が効かず、文字は
    ///    引き続きシステム標準の青のまま描画され、同じ約4.02:1のコントラストで失敗し続けた
    ///    （要素スクリーンショットで確認: 枠線だけでなく文字自体も青だった）。
    /// `.buttonStyle(.plain)`でButtonの自動tintを無効化し、`.foregroundStyle(.primary)`が実際に
    /// 適用されるようにして解決した。状態の視覚的な識別はボーダーの色（accentColor、非文字要素として
    /// WCAG 1.4.11の3:1基準を満たせばよい）だけで表現する。
    private var retakeButton: some View {
        Button(action: onRetake) {
            Text(ResultOverlayText.retake.value(for: displayLanguage))
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .padding()
        .background(Color(.systemBackground))
        .accessibilityIdentifier("ResultOverlayRetakeButton")
    }

    // MARK: - Navigation

    /// S09（料理詳細・判定根拠）。TASK-051の`DishDetailView`を表示する。
    @ViewBuilder
    private func destinationView(for ordinal: Int) -> some View {
        if let item = summary.items.first(where: { $0.reference.ordinal == ordinal }) {
            DishDetailView(
                item: item,
                translatedDishName: translatedNames[ordinal],
                displayLanguage: displayLanguage
            )
        }
    }

    // MARK: - Translation

    private func translateAllDishNames() async {
        for item in summary.items {
            let ordinal = item.reference.ordinal
            guard translatedNames[ordinal] == nil else { continue }
            if let translated = await translationService.translate(item.reference.originalText, to: displayLanguage) {
                translatedNames[ordinal] = translated
            }
        }
    }
}

private enum ResultOverlayText {
    static let retake = LocalizedText(
        english: "Retake Photo",
        traditionalChinese: "重新拍攝",
        simplifiedChinese: "重新拍摄",
        korean: "다시 촬영"
    )
}
