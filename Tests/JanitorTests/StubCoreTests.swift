//  StubCoreTests.swift
//  Pins the stub to the behavior the Rust seams have.
//
//  These tests exist because the stub carries copies of rules that are tested in Rust.
//  They are the thing that catches the copies drifting before JanitorKit replaces them.
//  When it does, these tests point at the real implementation and keep their assertions.

import Testing
@testable import Janitor

struct StubCoreTests {
    private let core = StubCore()

    // MARK: Prefix clustering

    @Test("names sharing a first segment collapse under one header")
    func namesShareAHeader() {
        let items = core.matrixItems(
            names: ["database.primary.url", "database.primary.password"],
            grouped: true
        )

        #expect(items.count == 3)
        guard case .header(let label, let count) = items[0] else {
            Issue.record("expected a header first")
            return
        }
        #expect(label == "database.primary.*")
        #expect(count == 2)
    }

    @Test("a name with no sibling renders flat")
    func loneNamesRenderFlat() {
        let items = core.matrixItems(names: ["STRIPE_KEY", "LOG_LEVEL"], grouped: true)

        #expect(items.count == 2)
        #expect(items.allSatisfy { if case .row = $0 { true } else { false } })
    }

    @Test("the header label is the longest common prefix, cut at a separator")
    func headerLabelIsTheCommonPrefix() {
        let items = core.matrixItems(
            names: ["GITHUB_APP_ID", "GITHUB_APP_KEY", "GITHUB_APP_SECRET"],
            grouped: true
        )

        guard case .header(let label, _) = items[0] else {
            Issue.record("expected a header first")
            return
        }
        #expect(label == "GITHUB_APP_*")
    }

    @Test("ungrouped is one flat list with one continuous stripe")
    func ungroupedIsFlat() {
        let items = core.matrixItems(names: ["a", "b", "c"], grouped: false)

        #expect(items == [
            .row(index: 0, zebra: false, groupLabel: nil),
            .row(index: 1, zebra: true, groupLabel: nil),
            .row(index: 2, zebra: false, groupLabel: nil),
        ])
    }

    @Test("the zebra stripe restarts under each header")
    func stripeRestartsUnderAHeader() {
        let items = core.matrixItems(
            names: ["a.one", "a.two", "b.one", "b.two"],
            grouped: true
        )

        let stripes = items.compactMap { item -> Bool? in
            if case .row(_, let zebra, _) = item { return zebra }
            return nil
        }
        #expect(stripes == [false, true, false, true])
    }

    // MARK: The name split

    @Test("a grouped row drops the prefix its header already shows")
    func groupedRowDropsTheHeaderPrefix() {
        let parts = core.displayNameParts(
            groupLabel: "database.*", name: "database.primary.url"
        )

        #expect(parts.prefix == "primary.")
        #expect(parts.leaf == "url")
    }

    @Test("an ungrouped row keeps its whole name")
    func ungroupedRowKeepsItsName() {
        let parts = core.displayNameParts(groupLabel: nil, name: "database.primary.url")

        #expect(parts.prefix == "database.primary.")
        #expect(parts.leaf == "url")
    }

    @Test("a name with no separator is all leaf")
    func separatorlessNameIsAllLeaf() {
        let parts = core.displayNameParts(groupLabel: nil, name: "SENTRY")

        #expect(parts.prefix == "")
        #expect(parts.leaf == "SENTRY")
    }

    @Test("a row equal to its whole cluster prefix falls back to its full name")
    func rowEqualToItsPrefixKeepsItsName() {
        // Stripping would leave the ENTRY column blank, which reads as a bug.
        let parts = core.displayNameParts(groupLabel: "database*", name: "database")

        #expect(parts.leaf == "database")
    }

    // MARK: Glyphs and badges

    @Test("each state has its own glyph")
    func stateGlyphs() {
        #expect(core.stateGlyph(.aligned) == "=")
        #expect(core.stateGlyph(.drift) == "≠")
        #expect(core.stateGlyph(.gap) == "∅")
    }

    @Test("a Binary row has no type badge")
    func binaryRowHasNoBadge() {
        #expect(core.badgeLabel(kind: nil) == "")
        #expect(core.badgeLabel(kind: .string) == "STRING")
        #expect(core.badgeLabel(kind: .number) == "NUMBER")
    }

    // MARK: The drift badge

    @Test("the drift badge shows only on the selected, loaded row")
    func driftBadgeIsSuppressedElsewhere() {
        let view = StubCore.paymentsView

        #expect(core.driftBadge(isSelected: true, status: .loaded, view: view) != "")
        #expect(core.driftBadge(isSelected: false, status: .loaded, view: view) == "")
        #expect(core.driftBadge(isSelected: true, status: .loading, view: view) == "")
    }

    @Test("no drift means no badge")
    func noDriftNoBadge() {
        let aligned = MatrixView(
            environments: ["prod", "staging"],
            rows: [StubCore.row("A", .string, [StubCore.cell(3, 1), StubCore.cell(3, 1)])]
        )

        #expect(core.driftBadge(isSelected: true, status: .loaded, view: aligned) == "")
    }

    // MARK: Canned data

    @Test("the seeded Payments matrix carries all three states")
    func paymentsMatrixCoversEveryState() {
        let states = Set(StubCore.paymentsView.rows.map(\.state))

        #expect(states == [.aligned, .drift, .gap])
    }

    @Test("aligned cells share an equality tag and drifting ones do not")
    func equalityTagsMatchTheState() {
        let rows = StubCore.paymentsView.rows

        let aligned = rows.first { $0.state == .aligned }!
        #expect(Set(aligned.cells.compactMap(tag)).count == 1)

        let drift = rows.first { $0.state == .drift }!
        #expect(Set(drift.cells.compactMap(tag)).count > 1)
    }

    private func tag(_ cell: MatrixCell) -> String? {
        if case .present(_, _, let hex, _) = cell { return hex }
        return nil
    }
}

// MARK: - The pinned cluster header

/// The header that floats over the table is chosen by arithmetic on the section heights,
/// so the part that could be wrong is testable without a view.
@MainActor
struct PinnedHeaderTests {
    /// Two clusters of two rows each, in the order the table lays them out.
    private let sections = MatrixItem.sections([
        .header(label: "database.*", count: 2),
        .row(index: 0, zebra: false, groupLabel: "database.*"),
        .row(index: 1, zebra: true, groupLabel: "database.*"),
        .header(label: "STRIPE_*", count: 2),
        .row(index: 2, zebra: false, groupLabel: "STRIPE_*"),
        .row(index: 3, zebra: true, groupLabel: "STRIPE_*"),
    ])

    private let headerHeight = Theme.Metrics.headerHeight
    private let rowHeight = Theme.Metrics.rowHeight

    @Test("nothing floats while the section's own header is on screen")
    func nothingFloatsAtTheTop() {
        #expect(MatrixTable.pinnedHeader(sections: sections, offset: 0) == nil)
    }

    @Test("the header floats once it has scrolled past")
    func theHeaderFloatsOnceItIsGone() {
        let header = MatrixTable.pinnedHeader(sections: sections, offset: headerHeight + 4)
        #expect(header?.label == "database.*")
        #expect(header?.count == 2)
    }

    @Test("the next cluster takes over at its boundary")
    func theNextClusterTakesOver() {
        let firstSection = headerHeight + 2 * rowHeight

        // The last pixel of the first cluster still belongs to it.
        #expect(MatrixTable.pinnedHeader(sections: sections, offset: firstSection - 1)?.label
            == "database.*")

        // Its own header is on screen again at the boundary, so nothing floats.
        #expect(MatrixTable.pinnedHeader(sections: sections, offset: firstSection) == nil)

        #expect(MatrixTable.pinnedHeader(
            sections: sections, offset: firstSection + headerHeight + 4
        )?.label == "STRIPE_*")
    }

    @Test("ungrouped rows float nothing")
    func ungroupedRowsFloatNothing() {
        let flat = MatrixItem.sections([
            .row(index: 0, zebra: false, groupLabel: nil),
            .row(index: 1, zebra: true, groupLabel: nil),
        ])

        #expect(MatrixTable.pinnedHeader(sections: flat, offset: 0) == nil)
        #expect(MatrixTable.pinnedHeader(sections: flat, offset: rowHeight + 1) == nil)
    }

    @Test("scrolled past the end, nothing floats")
    func pastTheEndNothingFloats() {
        let total = 2 * headerHeight + 4 * rowHeight
        #expect(MatrixTable.pinnedHeader(sections: sections, offset: total + 50) == nil)
    }

    @Test("a section nests its rows under its header")
    func sectionsNestTheirRows() {
        #expect(sections.count == 2)
        #expect(sections[0].header?.label == "database.*")
        #expect(sections[0].rows.map(\.index) == [0, 1])
        #expect(sections[1].rows.map(\.index) == [2, 3])
    }

    @Test("rows before any header become a leading section with none")
    func leadingRowsGetASectionWithNoHeader() {
        let mixed = MatrixItem.sections([
            .row(index: 0, zebra: false, groupLabel: nil),
            .header(label: "database.*", count: 1),
            .row(index: 1, zebra: false, groupLabel: "database.*"),
        ])

        #expect(mixed.count == 2)
        #expect(mixed[0].header == nil)
        #expect(mixed[0].rows.map(\.index) == [0])
        #expect(mixed[1].header?.label == "database.*")
    }
}
