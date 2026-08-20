import Testing
import Foundation
import FoundationModels
@testable import Meelyze

/// Apple Foundation Modelsを実際に利用できる物理iPhone上でだけ実行する、opt-inのlive model評価。
///
/// 通常の`xcodebuild test`（Simulator／CI）では実行されない（環境変数が存在しないため
/// `.enabled(if:)`がfalseとなり、Suite自体がskip扱いになる。この実行環境で
/// `MEELYZE_RUN_FOUNDATION_MODELS_LIVE_DEVICE_TESTS=1 xcodebuild test ...`および
/// `SIMCTL_CHILD_`prefix付きの両方を試したが、physical device非接続のこの環境ではSimulator
/// destinationへの通常のシェル環境変数forwardingは反映されずskipされたままだった。そのため
/// 実機実行時は、確実に動作するXcode GUIでの有効化を第一手段とする）。
///
/// 有効化するには、Apple Intelligenceと端末内モデルの準備が完了した物理iPhone実機
/// （`docs/device-verification.md`の手順で署名したビルド）上で、以下のいずれかの方法を使う。
///
/// 1. **Xcode GUI（推奨・動作確認済みの方法）**: Scheme編集（`Meelyze` → Edit Scheme → Test →
///    Arguments → Environment Variables）で`MEELYZE_RUN_FOUNDATION_MODELS_LIVE_DEVICE_TESTS=1`を
///    追加・有効化し、実機をdestinationに選んでTest Navigatorから`FoundationModelsLiveDeviceTests`
///    のみを実行する。
/// 2. **CLI**: 上記のScheme設定を有効化した状態で`xcodebuild test -project Meelyze.xcodeproj
///    -scheme Meelyze -destination 'platform=iOS,id=<接続した実機のUDID>'
///    -only-testing:MeelyzeTests/FoundationModelsLiveDeviceTests`を実行する（シェルの環境変数
///    prefixだけでは反映されない場合がある。実機での挙動は方法1のScheme設定と併用して確認する）。
///
/// このSuiteは`ScanViewModel`やS07画面等のパイプライン結線なしに`FoundationModelsMenuParser`単体を
/// 実機実行する。合格条件は出力文字列・候補順の完全一致ではなく、型の成立、入力sourceへの対応、
/// `originalText`保持、明示食材非捏造、未知要素の型としての保持、最終判定非生成という構造上／
/// 安全上の不変条件である。処理時間・メモリ・thermal state・連続実行時の安定性・オフライン動作は
/// このファイルだけでは自動計測できないため、実行者が`docs/device-verification.md`の実機手順に
/// 沿って手動で記録する（TASK-028作業ログの記入欄を参照）。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEELYZE_RUN_FOUNDATION_MODELS_LIVE_DEVICE_TESTS"] == "1"))
struct FoundationModelsLiveDeviceTests {

    @Test func systemLanguageModelIsAvailableAndSupportsJapanese() async throws {
        let model = SystemLanguageModel.default
        try #require(model.isAvailable, "この端末でApple Intelligence / Foundation Modelsが利用可能である必要がある")
        try #require(model.supportsLocale(FoundationModelsMenuParser.menuLocale), "ja-JPのlocale対応が必要")
    }

    @Test func representativeCasesProduceStructurallySafeResultsWithoutFinalJudgment() async throws {
        let parser = FoundationModelsMenuParser()
        let forbiddenSubstrings = ["アレルゲン", "アレルギー", "安全", "該当なし", "含まれない", "食べられ"]

        for fixture in RepresentativeMenuFixtures.all {
            let segments = fixture.segments.map {
                MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID($0.id), rawText: $0.rawText, confidence: 0.9, boundingBox: .zero)
            }
            let request = MenuUnderstandingRequest(segments: segments)
            let inputSourceIDs = Set(segments.map(\.id))
            let rawTextByID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0.rawText) })

            let start = ContinuousClock.now
            let result = await parser.analyze(request)
            let elapsed = start.duration(to: .now)

            // 型の成立・source対応: 成功した項目のsource参照はすべて入力に存在するIDであり、
            // Bounding Boxへ戻れる。
            for item in result.items {
                #expect(!item.reference.sourceReferences.isEmpty, "fixture: \(fixture.name)")
                for reference in item.reference.sourceReferences {
                    #expect(inputSourceIDs.contains(reference.sourceID), "fixture: \(fixture.name) unknown source \(reference.sourceID)")
                    if let rawText = rawTextByID[reference.sourceID] {
                        #expect(rawText.contains(reference.rawFragment), "fixture: \(fixture.name) fragment not found in raw text")
                    }
                }

                // 明示食材非捏造: パーサ自身のvalidationにより、fabricationは既にitem-scoped
                // failureとして分離されているはずだが、ここでも end-to-end に再確認する。
                let referencedText = item.reference.sourceReferences.map(\.rawFragment).joined()
                for ingredient in item.explicitIngredients {
                    #expect(referencedText.contains(ingredient), "fixture: \(fixture.name) explicit ingredient not in source text: \(ingredient)")
                }

                // 最終判定非生成: 型自体にアレルゲン・安全判定フィールドが存在しないことに加え、
                // 自由記述フィールドに安全方向の断定語が含まれていないことを確認する。
                let allText = ([item.baseDishCandidates, item.explicitIngredients, item.preparationMethods, item.modifiers, item.unknownTerms]
                    .flatMap { $0 } + [item.reference.originalText]).joined()
                for forbidden in forbiddenSubstrings {
                    #expect(!allText.contains(forbidden), "fixture: \(fixture.name) contains forbidden text: \(forbidden)")
                }
            }

            // Menu Understanding呼び出し単位（内部chunkを含む）の所要時間を記録する。10秒wrapperの
            // 実測値および全体3秒目標（NFR-1.1）への寄与は、この値を作業ログへ転記して評価する。
            print("[LiveDeviceTest] fixture=\(fixture.name) elapsed=\(elapsed) items=\(result.items.count) failures=\(result.failures.count) availability=\(result.availability)")
        }
    }

    @Test func freshSessionDoesNotLeakPriorMenuContextIntoTheNextAnalysis() async throws {
        let parser = FoundationModelsMenuParser()
        let first = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "ラフテー", confidence: 0.9, boundingBox: .zero),
        ])
        let second = MenuUnderstandingRequest(segments: [
            MenuUnderstandingSourceSegment(id: MenuUnderstandingSourceID("s1"), rawText: "特製ゴーヤーチャンプルー", confidence: 0.9, boundingBox: .zero),
        ])

        _ = await parser.analyze(first)
        let secondResult = await parser.analyze(second)

        // 直前メニュー固有の語（「ラフテー」）が、無関係な2件目の結果へ混入していないことを
        // 目視確認できるよう記録する。fresh sessionであれば、2件目の出力は2件目の入力からのみ
        // 構成されるはずである。
        for item in secondResult.items {
            #expect(!item.baseDishCandidates.contains("ラフテー"), "前回メニューの語がfresh sessionへ混入した可能性")
        }
    }
}
