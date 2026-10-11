import SwiftUI

/// Matriz de botones para ajustar la fecha límite: la primera fila fija una hora, la segunda suma y la tercera resta.
struct QuickAdjustGridView: View {
    let grid: QuickAdjustGrid
    /// Fila, columna y celda tocada.
    let onSelect: (_ row: Int, _ column: Int, _ cell: QuickAdjustGrid.Cell) -> Void

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(grid.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                        Button {
                            onSelect(rowIndex, columnIndex, cell)
                        } label: {
                            QuickAdjustCellLabel(cell: cell)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        .tint(rowIndex == 0 ? Color.brand : Color.secondary)
                        .accessibilityLabel(cell.accessibilityLabel)
                    }
                }
            }
        }
    }
}

struct QuickAdjustCellLabel: View {
    let cell: QuickAdjustGrid.Cell

    var body: some View {
        let parts = cell.labelParts
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.value)
                .font(.body.weight(.medium))
                .monospacedDigit()
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.caption)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(.primary)
    }
}
