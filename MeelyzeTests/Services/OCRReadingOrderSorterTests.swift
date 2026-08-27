import Testing
import Foundation
@testable import Meelyze

struct OCRReadingOrderSorterTests {
    @Test func twoColumnLayoutOrdersLeftColumnTopToBottomThenRightColumnTopToBottom() {
        // デモメニュー画像（「お食事」列・「一品料理・おつまみ」列）を単純化した回帰アンカー。
        let leftTop = RecognizedTextObservation(text: "沖縄そば", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.05))
        let leftBottom = RecognizedTextObservation(text: "ゴーヤーチャンプルー", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.05))
        let rightTop = RecognizedTextObservation(text: "ラフテー", confidence: 1, boundingBox: CGRect(x: 0.5, y: 0.65, width: 0.2, height: 0.05))
        let rightBottom = RecognizedTextObservation(text: "海ぶどう", confidence: 1, boundingBox: CGRect(x: 0.5, y: 0.35, width: 0.2, height: 0.05))

        // Vision観測順を模した、絶対Y降順の交互混在入力（列を無視した順序）。
        let input = [rightTop, leftTop, rightBottom, leftBottom]

        let sorted = OCRReadingOrderSorter.sorted(input)

        #expect(sorted.map(\.text) == ["沖縄そば", "ゴーヤーチャンプルー", "ラフテー", "海ぶどう"])
    }

    @Test func singleColumnLayoutSortsByYDescendingOnly() {
        let top = RecognizedTextObservation(text: "top", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.05))
        let middle = RecognizedTextObservation(text: "middle", confidence: 1, boundingBox: CGRect(x: 0.12, y: 0.5, width: 0.2, height: 0.05))
        let bottom = RecognizedTextObservation(text: "bottom", confidence: 1, boundingBox: CGRect(x: 0.08, y: 0.2, width: 0.2, height: 0.05))

        let sorted = OCRReadingOrderSorter.sorted([middle, top, bottom])

        #expect(sorted.map(\.text) == ["top", "middle", "bottom"])
    }

    @Test func smallGapBelowThresholdKeepsItemsInTheSameColumn() {
        // 左端の差が0.02（閾値0.06未満）なので同一列とみなされ、Y降順のみで並び替わる。
        let lowerLeftEdge = RecognizedTextObservation(text: "price", confidence: 1, boundingBox: CGRect(x: 0.10, y: 0.4, width: 0.1, height: 0.05))
        let higherLeftEdge = RecognizedTextObservation(text: "name", confidence: 1, boundingBox: CGRect(x: 0.12, y: 0.6, width: 0.1, height: 0.05))

        let sorted = OCRReadingOrderSorter.sorted([lowerLeftEdge, higherLeftEdge])

        #expect(sorted.map(\.text) == ["name", "price"])
    }

    @Test func largeGapAboveThresholdSplitsIntoSeparateColumns() {
        // 左端の差が0.3（閾値0.06超）なので別列とみなされ、Y位置に関わらず左列が先になる。
        let leftLowY = RecognizedTextObservation(text: "left", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.05))
        let rightHighY = RecognizedTextObservation(text: "right", confidence: 1, boundingBox: CGRect(x: 0.4, y: 0.9, width: 0.1, height: 0.05))

        let sorted = OCRReadingOrderSorter.sorted([rightHighY, leftLowY])

        #expect(sorted.map(\.text) == ["left", "right"])
    }

    @Test func threeColumnLayoutGroupsEachColumnSeparately() {
        let first = RecognizedTextObservation(text: "col1", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.05))
        let second = RecognizedTextObservation(text: "col2", confidence: 1, boundingBox: CGRect(x: 0.4, y: 0.9, width: 0.1, height: 0.05))
        let third = RecognizedTextObservation(text: "col3", confidence: 1, boundingBox: CGRect(x: 0.7, y: 0.5, width: 0.1, height: 0.05))

        let sorted = OCRReadingOrderSorter.sorted([second, third, first])

        #expect(sorted.map(\.text) == ["col1", "col2", "col3"])
    }

    @Test func emptyArrayIsReturnedUnchanged() {
        #expect(OCRReadingOrderSorter.sorted([]).isEmpty)
    }

    @Test func singleElementArrayIsReturnedUnchanged() {
        let only = RecognizedTextObservation(text: "only", confidence: 1, boundingBox: CGRect(x: 0.3, y: 0.5, width: 0.1, height: 0.05))

        #expect(OCRReadingOrderSorter.sorted([only]) == [only])
    }

    @Test func tiedBoundingBoxesPreserveOriginalRelativeOrder() {
        let box = CGRect(x: 0.2, y: 0.4, width: 0.1, height: 0.05)
        let first = RecognizedTextObservation(text: "first", confidence: 1, boundingBox: box)
        let second = RecognizedTextObservation(text: "second", confidence: 1, boundingBox: box)

        let sorted = OCRReadingOrderSorter.sorted([first, second])

        #expect(sorted.map(\.text) == ["first", "second"])
    }
}
