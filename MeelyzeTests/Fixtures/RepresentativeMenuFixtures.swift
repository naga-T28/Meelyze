import Foundation
@testable import Meelyze

/// TASK-026が要求する代表メニューケース。各ケースは、入力source segmentと、Foundation Modelsが
/// 返したと想定するStructured Output（JSON）、およびそこから決定論的に導出されるべき
/// `ParsedMenuItem`の期待値を組にして保持する。
///
/// 実モデルの生成内容そのもの（候補の言い回し・順序の揺れ）を固定するのではなく、`FoundationModelsMenuParser`
/// のadapter境界（Structured Output → domain mapping、source対応、`originalText`構成、
/// 未知語保持、明示食材非捏造）を決定的に検証するために用いる。
struct RepresentativeMenuCase: Sendable {
    let name: String
    let segments: [(id: String, rawText: String)]
    let modelResponseJSON: String
    let expectedItems: [ExpectedParsedMenuItem]
}

struct ExpectedParsedMenuItem: Sendable {
    let sourceIDs: [String]
    let originalText: String
    let baseDishCandidates: [String]
    let explicitIngredients: [String]
    let preparationMethods: [String]
    let modifiers: [String]
    let unknownTerms: [String]
}

enum RepresentativeMenuFixtures {
    static let all: [RepresentativeMenuCase] = {
        var cases: [RepresentativeMenuCase] = [
            // 明示食材: 複数の食材が原文に明記されている場合、料理名候補と分離して保持できること。
            singleSegmentCase(
                name: "明示食材（島豆腐と豚肉のゴーヤーチャンプルー）",
                rawText: "島豆腐と豚肉のゴーヤーチャンプルー",
                baseDishCandidates: ["ゴーヤーチャンプルー"],
                explicitIngredients: ["島豆腐", "豚肉"]
            ),
            // 複合料理名候補: 複合語をより粒度の細かい候補と共に保持できること。
            singleSegmentCase(
                name: "複合料理名候補（ソーキそば）",
                rawText: "ソーキそば",
                baseDishCandidates: ["ソーキそば", "そば"]
            ),
            // 調理方法・修飾表現: 「炙り」（調理方法）と「大盛り」（修飾表現）を分離して保持できること。
            singleSegmentCase(
                name: "調理方法・修飾表現（炙りソーキそば（大盛り））",
                rawText: "炙りソーキそば（大盛り）",
                baseDishCandidates: ["ソーキそば"],
                preparationMethods: ["炙り"],
                modifiers: ["大盛り"]
            ),
            // 未知の造語: 既知のベース候補（ラフテー）と未解決部分（もあい風）を同時に保持できること。
            singleSegmentCase(
                name: "未知の造語を含む料理名（もあい風ラフテー）",
                rawText: "もあい風ラフテー",
                baseDishCandidates: ["ラフテー"],
                unknownTerms: ["もあい風"]
            ),
            // docs/mvp-scope.md記載の代表3文字列。
            singleSegmentCase(
                name: "mvp-scope: 島豚の炙り沖縄そば 1,280円",
                rawText: "島豚の炙り沖縄そば 1,280円",
                baseDishCandidates: ["沖縄そば"],
                explicitIngredients: ["島豚"],
                preparationMethods: ["炙り"]
            ),
            singleSegmentCase(
                name: "mvp-scope: 特製ゴーヤーチャンプルー",
                rawText: "特製ゴーヤーチャンプルー",
                baseDishCandidates: ["ゴーヤーチャンプルー"],
                modifiers: ["特製"]
            ),
            singleSegmentCase(
                name: "mvp-scope: 県産和牛のにんにく醤油焼き",
                rawText: "県産和牛のにんにく醤油焼き",
                explicitIngredients: ["県産和牛", "にんにく"],
                preparationMethods: ["醤油焼き"]
            ),
        ]

        // 単純な既知料理（沖縄のシードDishを含む）: 単一source・単一itemの基本形。
        for dish in ["ラフテー", "ソーキ", "ミミガー", "テビチ", "ゴーヤーチャンプルー", "沖縄そば"] {
            cases.append(
                singleSegmentCase(name: "単純な既知料理（\(dish)）", rawText: dish, baseDishCandidates: [dish])
            )
        }

        // 複数行: 3つの独立したOCR sourceがそれぞれ独立した項目へ分割され、入力順が保持されること。
        cases.append(multiLineCase())

        return cases
    }()

    private static func singleSegmentCase(
        name: String,
        rawText: String,
        baseDishCandidates: [String] = [],
        explicitIngredients: [String] = [],
        preparationMethods: [String] = [],
        modifiers: [String] = [],
        unknownTerms: [String] = []
    ) -> RepresentativeMenuCase {
        let item = FixtureAnalysisPayload.Item(
            sourceReferences: [FixtureAnalysisPayload.Item.SourceReference(sourceID: "s1", fragment: rawText)],
            baseDishCandidates: baseDishCandidates,
            explicitIngredients: explicitIngredients,
            preparationMethods: preparationMethods,
            modifiers: modifiers,
            unknownTerms: unknownTerms
        )
        return RepresentativeMenuCase(
            name: name,
            segments: [(id: "s1", rawText: rawText)],
            modelResponseJSON: jsonString(for: [item]),
            expectedItems: [
                ExpectedParsedMenuItem(
                    sourceIDs: ["s1"],
                    originalText: rawText,
                    baseDishCandidates: baseDishCandidates,
                    explicitIngredients: explicitIngredients,
                    preparationMethods: preparationMethods,
                    modifiers: modifiers,
                    unknownTerms: unknownTerms
                ),
            ]
        )
    }

    private static func multiLineCase() -> RepresentativeMenuCase {
        let dishes = [(id: "s1", text: "ラフテー"), (id: "s2", text: "ミミガー"), (id: "s3", text: "テビチ")]
        let items = dishes.map { dish in
            FixtureAnalysisPayload.Item(
                sourceReferences: [FixtureAnalysisPayload.Item.SourceReference(sourceID: dish.id, fragment: dish.text)],
                baseDishCandidates: [dish.text],
                explicitIngredients: [],
                preparationMethods: [],
                modifiers: [],
                unknownTerms: []
            )
        }
        return RepresentativeMenuCase(
            name: "複数行（ラフテー / ミミガー / テビチ）",
            segments: dishes.map { ($0.id, $0.text) },
            modelResponseJSON: jsonString(for: items),
            expectedItems: dishes.map { dish in
                ExpectedParsedMenuItem(
                    sourceIDs: [dish.id],
                    originalText: dish.text,
                    baseDishCandidates: [dish.text],
                    explicitIngredients: [],
                    preparationMethods: [],
                    modifiers: [],
                    unknownTerms: []
                )
            }
        )
    }
}

/// `FoundationModelsMenuParser`内のprivate DTOと同じJSON形状を独立に再現する、fixture専用の
/// Codableミラー型。private DTOへは依存せず、`GeneratedContent(json:)`へ渡す文字列を組み立てる
/// ためだけに使う。
private struct FixtureAnalysisPayload: Encodable {
    struct Item: Encodable {
        struct SourceReference: Encodable {
            let sourceID: String
            let fragment: String
        }
        let sourceReferences: [SourceReference]
        let baseDishCandidates: [String]
        let explicitIngredients: [String]
        let preparationMethods: [String]
        let modifiers: [String]
        let unknownTerms: [String]
    }
    let items: [Item]
}

private func jsonString(for items: [FixtureAnalysisPayload.Item]) -> String {
    let payload = FixtureAnalysisPayload(items: items)
    let data = try! JSONEncoder().encode(payload)
    return String(data: data, encoding: .utf8)!
}
