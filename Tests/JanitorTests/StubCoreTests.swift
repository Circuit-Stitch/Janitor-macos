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
