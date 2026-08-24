//  MatrixTable.swift
//  The drift matrix: a frozen STATE and ENTRY pair on the left, and one column per
//  Environment scrolling horizontally beside them.
//
//  The freeze pane is the point. An Application can have more Environments than fit,
//  and an Entry name that scrolls out of view makes the row it labels unreadable. So
//  the left two columns never move horizontally, and the header band tracks the body's
//  horizontal offset so the Environment names stay over their own columns.
//
//  The two bands stay aligned because they are built from the same numbers. Each starts
//  after the same frozen width and the same hairline, and each steps by the same column
//  width. Padding sits inside those frames rather than outside, so a header cell and a
//  body cell are the same size and start in the same place.
//
//  Comparison columns divide the room left beside the frozen pair, down to a floor.
//  Above the floor they stretch, so a two-Environment Application in a wide window has
//  no empty gutter on the right. At the floor they stop shrinking and the region
//  scrolls instead.
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

import JanitorKit
import SwiftUI

struct MatrixTable: View {
    let model: AppModel

    /// The ENTRY column's width, seeded from what the core has stored.
    @State private var entryWidth: CGFloat
    /// The width the ENTRY column had when the resize press landed. The drag is measured
    /// from there, so the column tracks the cursor instead of running away from it.
    @State private var dragAnchor: CGFloat?
    /// The body's horizontal scroll offset, mirrored onto the header band.
    @State private var horizontalOffset: CGFloat = 0
    /// The body's vertical scroll offset, which decides which cluster header is pinned.
    @State private var verticalOffset: CGFloat = 0

    @MainActor
    init(model: AppModel) {
        self.model = model
        _entryWidth = State(initialValue: model.entryColumnWidth)
    }

    private var frozenWidth: CGFloat { MatrixLayout.frozenWidth(entryWidth: entryWidth) }

    /// One comparison column's width, given the room the band has.
    private func columnWidth(band: CGFloat) -> CGFloat {
        MatrixLayout.environmentColumnWidth(
            available: band, count: model.matrix.environments.count
        )
    }

    // The pane's width is what decides the layout, so it is read once and handed down.
    //
    // Without it the horizontal region asks for as much width as its columns need, the
    // matrix grows wider than the pane, and the whole table slides out from under the
    // header and the sidebar. Reading the width here and giving the region exactly what
    // is left makes every width in the table a function of the window instead.
    var body: some View {
        GeometryReader { proxy in
            let band = MatrixLayout.availableEnvironmentWidth(
                total: proxy.size.width, entryWidth: entryWidth
            )
            VStack(spacing: 0) {
                headerBand(band: band)
                Divider()
                table(band: band)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Header band

    private func headerBand(band: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Theme.Metrics.stateColumn)
                .accessibilityElement()
                .accessibilityLabel("State")
                .accessibilityIdentifier("statehdr")
            Text("ENTRY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .frame(width: entryWidth, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("entryhdr")
            columnResizer
            environmentHeaders(band: band)
                .offset(x: MatrixLayout.headerBandOffset(bodyContentOffset: horizontalOffset))
                .frame(width: band, alignment: .leading)
                .clipped()
        }
        .frame(height: Theme.Metrics.headerHeight)
        .background(.bar)
    }

    private func environmentHeaders(band: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(model.matrix.environments.enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: columnWidth(band: band), alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(name)
                    .accessibilityIdentifier("envhead-\(index)")
            }
        }
    }

    /// Drag to widen or narrow the ENTRY column. Long Entry names are common, and the
    /// name is what the operator scans.
    private var columnResizer: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: Theme.Metrics.dividerWidth)
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { drag in
                                let anchor = dragAnchor ?? entryWidth
                                dragAnchor = anchor
                                entryWidth = MatrixLayout.entryWidth(
                                    anchor: anchor, translation: drag.translation.width
                                )
                            }
                            .onEnded { drag in
                                let anchor = dragAnchor ?? entryWidth
                                entryWidth = MatrixLayout.entryWidth(
                                    anchor: anchor, translation: drag.translation.width
                                )
                                dragAnchor = nil
                                // Persisted on release, not while it moves: one write
                                // for one resize.
                                model.setEntryColumnWidth(entryWidth)
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Resize the Entry column")
                    .accessibilityIdentifier("entry-resize-handle")
            }
    }

    // MARK: Body

    private func table(band: CGFloat) -> some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                frozenColumn
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: Theme.Metrics.dividerWidth)
                environmentColumns(band: band)
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
            if let header = MatrixLayout.pinnedHeader(sections: sections, offset: verticalOffset) {
                clusterHeader(label: header.label, count: header.count, kind: "pinned")
                    .allowsHitTesting(false)
            }
        }
        .clipped()
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
                        clusterHeader(label: header.label, count: header.count, kind: "cluster")
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

    private func environmentColumns(band: CGFloat) -> some View {
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
                        environmentRow(index: row.index, zebra: row.zebra, band: band)
                    }
                }
            }
        }
        // Exactly the room the frozen pair left. A flexible width here lets the columns
        // decide how wide the region is, which is how the table outgrows its pane.
        .frame(width: band)
        .scrollIndicators(.visible)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, offset in
            horizontalOffset = offset
        }
    }

    // MARK: Rows

    /// One cluster header. `kind` separates the copy pinned at the top of the pane from
    /// the copy that scrolls with its rows, so a test can tell which one it found.
    private func clusterHeader(label: String, count: Int, kind: String) -> some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(count) entries")
        .accessibilityIdentifier("\(kind)-\(label)")
    }

    private func frozenRow(index: Int, zebra: Bool, groupLabel: String?) -> some View {
        let row = model.matrix.rows[index]
        let parts = model.displayNameParts(groupLabel: groupLabel, name: row.name)
        return HStack(spacing: 0) {
            Text(model.stateGlyph(row.state))
                .font(Theme.mono)
                .foregroundStyle(Theme.color(for: row.state))
                .frame(width: Theme.Metrics.stateColumn)
                .accessibilityElement()
                .accessibilityLabel(stateDescription(row.state))
                .accessibilityIdentifier("state-cell-\(index)")
            HStack(spacing: 0) {
                Text(parts.prefix)
                    .foregroundStyle(.secondary)
                Text(parts.leaf)
                    .fontWeight(.medium)
            }
            .font(Theme.mono)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A grouped row drops the prefix its header already shows, and a long name
            // truncates in the middle. Both draw less than the Entry is called, so the
            // whole name stays reachable: on hover, and to VoiceOver.
            .help(row.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityIdentifier("entry-cell-\(index)")
            badge(row.kind)
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(zebra ? Color(nsColor: .underPageBackgroundColor).opacity(0.5) : .clear)
        .contextMenu {
            Button("Copy Entry Name") { model.copyName(row.name) }
        }
    }

    private func environmentRow(index: Int, zebra: Bool, band: CGFloat) -> some View {
        let row = model.matrix.rows[index]
        return HStack(spacing: 0) {
            ForEach(Array(row.cells.enumerated()), id: \.offset) { col, cell in
                CellView(
                    cell: cell,
                    width: columnWidth(band: band),
                    environment: model.matrix.environments[col],
                    entryName: row.name,
                    identifier: "envcell-\(index)-\(col)",
                    revealedText: revealedText(row: index, col: col),
                    isStaged: model.isStaged(row: index, col: col),
                    canEdit: model.canEdit,
                    onPress: { model.beginReveal(row: index, col: col) },
                    onRelease: { model.endReveal() },
                    onCopy: { model.copyValue(row: index, col: col) },
                    onEdit: { model.beginEdit(row: index, col: col) },
                    onRemove: { model.stageRemoval(row: index, col: col) }
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
        @unknown default: "Unknown"
        }
    }
}
