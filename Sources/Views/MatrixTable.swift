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
//
//  Cluster headers pin. `database.*` stays at the top of the pane while any of its rows
//  is on screen, so a long cluster never leaves the operator scrolled into unlabeled
//  rows. Only the frozen half pins, because the label lives there. The two halves stay
//  aligned through it: a pinned header still occupies its space in the scroll content
//  and is only repositioned, so the blank band the environment half draws in its place
//  keeps every row on its own baseline.

import SwiftUI

struct MatrixTable: View {
    let model: AppModel

    @State private var entryWidth = Theme.Metrics.entryColumn
    /// The body's horizontal scroll offset, mirrored onto the header band.
    @State private var horizontalOffset: CGFloat = 0
    /// The body's vertical scroll offset, which decides which cluster header is pinned.
    @State private var verticalOffset: CGFloat = 0

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
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offset in
            verticalOffset = offset
        }
        // The pinned cluster header, drawn over both halves.
        //
        // `pinnedViews` on the frozen stack would pin only that half. The label would
        // then cover an Entry name on the left while that row's cells stayed visible on
        // the right, which reads as a header sitting beside another row's values. This
        // band spans the whole width, so the row it covers is covered in both halves.
        .overlay(alignment: .top) {
            if let header = Self.pinnedHeader(sections: sections, offset: verticalOffset) {
                clusterHeader(label: header.label, count: header.count)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
    }

    /// Which cluster header floats at the top of the pane at a given scroll offset.
    ///
    /// Nil while the section's own header is still on screen — its inline copy is doing
    /// the job, and drawing a second one over it would double the label. Nil also for a
    /// section with no header, which is what ungrouped rows are.
    static func pinnedHeader(sections: [MatrixSection], offset: CGFloat)
        -> (label: String, count: Int)?
    {
        var top: CGFloat = 0
        for section in sections {
            let headerHeight = section.header == nil ? 0 : Theme.Metrics.headerHeight
            let height = headerHeight + CGFloat(section.rows.count) * Theme.Metrics.rowHeight
            if offset < top + height {
                guard offset > top, let header = section.header else { return nil }
                return header
            }
            top += height
        }
        return nil
    }

    private var frozenColumn: some View {
        LazyVStack(spacing: 0) {
            ForEach(sections) { section in
                Section {
                    // Keyed by the row's index into the matrix, which is unique across
                    // the whole table. Keying by position within the section repeats
                    // 0, 1, 2 in every section, and a lazy stack renders only the first
                    // section that claims them.
                    ForEach(section.rows, id: \.index) { row in
                        frozenRow(
                            index: row.index, zebra: row.zebra, groupLabel: row.groupLabel
                        )
                    }
                } header: {
                    if let header = section.header {
                        clusterHeader(label: header.label, count: header.count)
                    }
                }
            }
        }
        .frame(width: frozenWidth)
    }

    /// The rendered list, nested into its clusters. A section is what pins; a flat list
    /// has nothing to pin.
    private var sections: [MatrixSection] {
        MatrixItem.sections(model.items)
    }

    private var environmentColumns: some View {
        ScrollView(.horizontal) {
            // A VStack, not a LazyVStack. A lazy stack inside a horizontal ScrollView
            // measures each row against the visible width instead of the content width,
            // and every row collapses to its last cell.
            VStack(spacing: 0) {
                ForEach(sections) { section in
                    if section.header != nil {
                        // The band the label sits over. It occupies the same space the
                        // header does in the other half, which is what keeps the two
                        // halves on the same baseline.
                        Color.clear
                            .frame(height: Theme.Metrics.headerHeight)
                            .background(.bar)
                    }
                    ForEach(section.rows, id: \.index) { row in
                        environmentRow(index: row.index, zebra: row.zebra)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Theme.Metrics.headerHeight)
        // Opaque, because it is drawn over the rows it scrolls past.
        .background(.bar)
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
