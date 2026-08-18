import SwiftUI

/// 子ビューを自然サイズのまま並べ、行の幅に収まらなくなったら次の行へ折り返すレイアウト。
///
/// `LazyVGrid(.adaptive)`は列幅が行内で均一になるため、品目名の長さによっては短い列に余分な
/// 余白が生じたり、長い品目名が列幅に収まらず省略されたりする（Issue #24参照）。本レイアウトは
/// 各チップをその内容が必要とする幅のみで配置するため、両方の問題を解消する。
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)

        let height = rows.reduce(CGFloat(0)) { partialHeight, row in
            partialHeight + row.maxHeight + (partialHeight > 0 ? verticalSpacing : 0)
        }
        let width = rows.map(\.width).max() ?? 0

        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)

        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(element.size)
                )
                x += element.size.width + horizontalSpacing
            }
            y += row.maxHeight + verticalSpacing
        }
    }

    private struct RowElement {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var elements: [RowElement] = []
        var width: CGFloat = 0
        var maxHeight: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let measurementProposal = maxWidth.isFinite
                ? ProposedViewSize(width: maxWidth, height: nil)
                : ProposedViewSize.unspecified
            let size = subview.sizeThatFits(measurementProposal)
            let spacingBeforeElement = currentRow.elements.isEmpty ? 0 : horizontalSpacing
            let projectedWidth = currentRow.width + spacingBeforeElement + size.width

            if !currentRow.elements.isEmpty && projectedWidth > maxWidth {
                rows.append(currentRow)
                currentRow = Row()
            }

            let spacing = currentRow.elements.isEmpty ? 0 : horizontalSpacing
            currentRow.elements.append(RowElement(subview: subview, size: size))
            currentRow.width += spacing + size.width
            currentRow.maxHeight = max(currentRow.maxHeight, size.height)
        }

        if !currentRow.elements.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }
}
