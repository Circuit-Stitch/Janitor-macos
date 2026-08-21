//  MatrixTable.swift
//  The drift matrix: a frozen STATE and ENTRY pair on the left, and one column per
//  Environment scrolling horizontally beside them.
//
//  The freeze pane is the point. An Application can have more Environments than fit,
//  and an Entry name that scrolls out of view makes the row it labels unreadable. So
//  the left two columns never move horizontally, and the header band tracks the body's
//  horizontal offset so the Environment names stay over their own columns.
//
//  Rows come from the core already assembled: cluster headers, data rows, zebra
//  stripes, and which prefix each row's header already shows. This view renders that
//  list. It does not decide it.

import SwiftUI

struct MatrixTable: View {
    let model: AppModel

    @State private var entryWidth = Theme.Metrics.entryColumn
    /// The body's horizontal scroll offset, mirrored onto the header band.
    @State private var horizontalOffset: CGFloat = 0

    private var frozenWidth: CGFloat { Theme.Metrics.stateColumn + entryWidth }

    var body: some View {
        VStack(spacing: 0) {
            headerBand
            Divider()
            table
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Header band

    private var headerBand: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: Theme.Metrics.stateColumn)
            Text("ENTRY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: entryWidth, alignment: .leading)
                .padding(.leading, 8)
            columnResizer
            environmentHeaders
                .offset(x: -horizontalOffset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .frame(height: Theme.Metrics.headerHeight)
        .background(.bar)
    }

    private var environmentHeaders: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.matrix.environments.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Theme.Metrics.environmentColumn, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
    }

    /// Drag to widen or narrow the ENTRY column. Long Entry names are common, and the
    /// name is what the operator scans.
    private var columnResizer: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { drag in
                                entryWidth = max(
                                    Theme.Metrics.entryColumnMinimum,
                                    entryWidth + drag.translation.width
                                )
                            }
                    )
            }
    }

    // MARK: Body

    private var table: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                frozenColumn
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                environmentColumns
            }
        }
    }

    private var frozenColumn: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .header(let label, let count):
                    clusterHeader(label: label, count: count)
                case .row(let index, let zebra, let groupLabel):
                    frozenRow(index: index, zebra: zebra, groupLabel: groupLabel)
                }
            }
        }
        .frame(width: frozenWidth)
    }

    private var environmentColumns: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .header:
                        // Keeps the two halves on the same baseline. The label itself
                        // lives in the frozen half, over the names it groups.
                        Color.clear
                            .frame(height: Theme.Metrics.headerHeight)
                    case .row(let index, let zebra, _):
                        environmentRow(index: index, zebra: zebra)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, offset in
            horizontalOffset = offset
        }
    }

    // MARK: Rows

    private func clusterHeader(label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.Metrics.headerHeight)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func frozenRow(index: Int, zebra: Bool, groupLabel: String?) -> some View {
        let row = model.matrix.rows[index]
        let parts = model.displayNameParts(groupLabel: groupLabel, name: row.name)
        return HStack(spacing: 0) {
            Text(model.stateGlyph(row.state))
                .font(Theme.mono)
                .foregroundStyle(Theme.color(for: row.state))
                .frame(width: Theme.Metrics.stateColumn)
                .accessibilityLabel(stateDescription(row.state))
            HStack(spacing: 0) {
                Text(parts.prefix)
                    .foregroundStyle(.secondary)
                Text(parts.leaf)
                    .fontWeight(.medium)
            }
            .font(Theme.mono)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            badge(row.kind)
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(zebra ? Color(nsColor: .underPageBackgroundColor).opacity(0.5) : .clear)
        .contextMenu {
            Button("Copy Entry Name") { model.copyName(row.name) }
        }
    }

    private func environmentRow(index: Int, zebra: Bool) -> some View {
        let row = model.matrix.rows[index]
        return HStack(spacing: 0) {
            ForEach(Array(row.cells.enumerated()), id: \.offset) { col, cell in
                CellView(
                    cell: cell,
                    environment: model.matrix.environments[col],
                    entryName: row.name,
                    revealedText: revealedText(row: index, col: col),
                    onPress: { model.beginReveal(row: index, col: col) },
                    onRelease: { model.endReveal() },
                    onCopy: { model.copyValue(row: index, col: col) }
                )
            }
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(zebra ? Color(nsColor: .underPageBackgroundColor).opacity(0.5) : .clear)
    }

    @ViewBuilder
    private func badge(_ kind: LeafKind?) -> some View {
        let text = model.badgeLabel(kind: kind)
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color(nsColor: .quaternaryLabelColor), in: .rect(cornerRadius: 3))
                .padding(.trailing, 6)
        }
    }

    /// The plaintext for one cell, which is non-nil for at most one cell in the whole
    /// matrix because the model holds a single optional.
    private func revealedText(row: Int, col: Int) -> String? {
        guard let revealed = model.revealed, revealed.row == row, revealed.col == col else {
            return nil
        }
        return revealed.text
    }

    private func stateDescription(_ state: EntryState) -> String {
        switch state {
        case .aligned: "Aligned"
        case .drift: "Drift"
        case .gap: "Gap"
        }
    }
}
