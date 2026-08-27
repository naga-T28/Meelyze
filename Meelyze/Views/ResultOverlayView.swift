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
                    // `imageView`は`.aspectRatio(.fit)`でレターボックス（余白）付きに縮小表示されるため、
                    // 明示的にコンテナ全体の`.frame`を与えて中央寄せさせる。これがないとZStackの
                    // `.topLeading`揃えにより画像自体が左上へ寄って描画され、`BoundingBoxConverter`が
                    // 前提とする「中央寄せのレターボックス」とズレて、タグの表示位置が実際の料理名の
                    // 位置から少しずれる。
                    imageView
                        .frame(width: geometry.size.width, height: geometry.size.height)
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
        let imageSize = uiImage?.size ?? containerSize
        let lineRects = item.boundingBoxes.map {
            boundingBoxConverter.convert($0, imageSize: imageSize, containerSize: containerSize)
        }
        let rect = boundingBoxConverter.convertUnion(
            item.boundingBoxes,
            imageSize: imageSize,
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
        let fontSize = OverlayTagFontMetrics.fontSize(forLineHeights: lineRects.map(\.height))
        // `topNotices`（常時注意文・E02バナー）はこのZStackより前面（`.overlay(alignment: .top)`）に
        // 不透明な背景で描画されるため、タグがその領域へ重なると視覚的に隠れるだけでなく、
        // `XCTest.performAccessibilityAudit()`のコントラスト判定がタグと`topNotices`の色を混在させて
        // 誤って"Contrast failed"と判定することを確認した（FIX-015作業ログ参照）。料理がメニュー写真の
        // 上部に写っている場合に実際に起こりうるため、タグの中心Yを`topNotices`の下端付近より
        // 上へは配置しない。`topNotices`の実高さを`GeometryReader`＋`PreferenceKey`で動的に測る
        // 実装を試したが、`.overlay(alignment:)`内の背景`GeometryReader`が常に高さ0を報告し
        // 機能しなかったため（原因未特定）、既定のDynamic Typeサイズ・E02バナーなしの場合を想定した
        // 固定値へ変更した。E02バナー表示時や大きなDynamic Typeサイズでは`topNotices`がこの値より
        // 高くなり得るため、その場合は本節の保護が及ばない可能性がある（既知の制約、FIX-015作業ログ参照）。
        let clampedMidY = max(rect.midY, Self.minimumCardMidY)

        return RiskResultCardView(
            style: .compactOverlay,
            japaneseDishName: item.reference.originalText,
            translatedDishName: translatedNames[item.reference.ordinal],
            determination: determination,
            matchedTargetNames: matchedNames,
            reasonText: reasonText,
            displayLanguage: displayLanguage,
            compactFontSize: fontSize
        ) {
            path.append(item.reference.ordinal)
        }
        .frame(minWidth: 44, minHeight: 44)
        .position(x: rect.midX, y: clampedMidY)
        .accessibilitySortPriority(sortPriority(for: determination))
    }

    /// タグの中心Yがこれより上（画面上端に近い側）に来ないようにする、`topNotices`
    /// （常時注意文・E02バナー）用の固定の逃げ幅。既定のDynamic Typeサイズ・E02バナーなしの場合の
    /// `topNotices`の実測高さ（安全余白込みで約190pt）を基準にした値であり、`topNotices`の実高さを
    /// 動的に測ってはいない。E02バナー表示時や大きなDynamic Typeサイズでは`topNotices`がこの値より
    /// 高くなり得るため、その場合はこの保護が及ばない可能性がある（既知の制約、FIX-015作業ログ参照）。
    private static let minimumCardMidY: CGFloat = 190

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

/// S08のタグの文字サイズを、対象料理のOCR文字の大きさに視覚的に近づけるための計算（FIX-014/015）。
/// カードの文字サイズがメニュー写真内の実際の文字サイズと無関係な固定値だったため、密なメニューでは
/// 隣接タグ同士が重なっていた。密集したメニューほど1行の文字が小さくなるため、文字サイズに比例して
/// 縮小させることで「重なりやすい状況ほどタグも小さくなる」自己補正が働く。
///
/// FIX-015で`.scaleEffect`（見た目だけを引き伸ばすtransform）による実装から、実際のフォントサイズを
/// 計算して`Text`/`Image`へ渡す方式へ変更した。`.scaleEffect`はSwiftUIの
/// `XCTest.performAccessibilityAudit()`のコントラスト判定が参照するアクセシビリティフレームと、
/// transform後の実際の描画ピクセルとの対応がタイミングによってはずれることがあり
/// （`ResultOverlayAccessibilityUITests`で単独実行時も含め約20〜25%の頻度で"Contrast failed"が
/// 再現し、指摘される要素・タイミングが実行のたびに変わる非決定的な挙動として観測された）、
/// 実際のトークン色（`RiskDetermination.foregroundColor`/`backgroundColor`、AA基準6:1以上で
/// 監査済み）自体が原因ではなく、transformとaudit側のフレーム計測のずれが原因と判断した。
/// ネイティブなフォントサイズ指定であれば、レイアウト・描画・アクセシビリティフレームが
/// 常に同じ値から計算されるため、この種のずれが原理的に発生しない。
///
/// `ResultOverlayView`のprivateロジックのままだとユニットテストしにくいため、TASK-048が
/// `hasModelUnavailableCondition`を`MenuAnalysisSummary`のextensionへ切り出したのと同じ理由で、
/// 独立した型として切り出す。
enum OverlayTagFontMetrics {
    /// OCR文字の代表的な行高（コンテナ座標系、約20pt）に対応させる基準フォントサイズ。
    /// `.subheadline`のデフォルトサイズ（約15pt）と合わせている。
    static let baselineFontSize: CGFloat = 15
    /// 基準フォントサイズに対応する行高（コンテナ座標系）。
    static let referenceLineHeight: CGFloat = 20
    /// 視認性・タップ領域を保つための下限（`.frame(minWidth:minHeight:)`の44ptで別途タップ領域自体は確保する）。
    static let minimumFontSize: CGFloat = 10
    /// メニュー内の見出し等の大きな文字に引きずられてタグが過度に肥大化しないための上限。
    static let maximumFontSize: CGFloat = 22

    /// `lineHeights`（コンテナ座標系に変換済みの、1項目を構成する各Bounding Boxの高さ）から
    /// フォントサイズを計算する。複数行にまたがる項目のUNION矩形の高さをそのまま使うと行数に比例して
    /// 過大評価してしまうため、個々の行の高さの最大値を代表値として使う。
    static func fontSize(forLineHeights lineHeights: [CGFloat]) -> CGFloat {
        guard let representativeHeight = lineHeights.max(), representativeHeight.isFinite, representativeHeight > 0 else {
            return baselineFontSize
        }
        let rawFontSize = baselineFontSize * (representativeHeight / referenceLineHeight)
        return min(max(rawFontSize, minimumFontSize), maximumFontSize)
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
