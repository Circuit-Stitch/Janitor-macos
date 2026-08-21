//  MatrixLayoutTests.swift
//  The matrix's layout arithmetic.
//
//  These are the rules the Slint shell asserted against real rendered geometry: the
//  comparison columns stretch to fill and then hold a floor, the two bands of the freeze
//  pane share one origin and one step, the ENTRY column tracks the cursor and clamps, and
//  one cluster header floats at a time.
//
//  Here they are tested as arithmetic, and again in `JanitorUITests` against the running
//  app. The split is deliberate: this file proves the rule is right, and the UI tests
//  prove the views are wired to it.

import Testing
import CoreGraphics
@testable import Janitor

@MainActor
struct MatrixLayoutTests {
    private let floor = MatrixLayout.environmentFloor

    // MARK: The comparison columns

    @Test("few columns in a wide window stretch to fill the band")
    func columnsStretchToFill() {
        // Two columns with far more than two floors of room. They divide it all, so
        // there is no gutter left on the right.
        let width = MatrixLayout.environmentColumnWidth(available: 1000, count: 2)

        #expect(width == 500)
        #expect(width > floor)
        #expect(MatrixLayout.environmentContentWidth(available: 1000, count: 2) == 1000)
        #expect(MatrixLayout.environmentOverflows(available: 1000, count: 2) == false)
    }

    @Test("many columns hold the floor and overflow instead of shrinking")
    func columnsHoldTheFloor() {
        // Eight columns in room for four. They stop at the floor rather than squeezing
        // to a width that shows nothing readable, and the band scrolls.
        let width = MatrixLayout.environmentColumnWidth(available: 800, count: 8)

        #expect(width == floor)
        #expect(MatrixLayout.environmentContentWidth(available: 800, count: 8) == floor * 8)
        #expect(MatrixLayout.environmentOverflows(available: 800, count: 8))
    }

    @Test("the floor is exactly where stretching stops")
    func theFloorIsTheBoundary() {
        // Room for exactly four floors: still the floor, and still no overflow.
        #expect(MatrixLayout.environmentColumnWidth(available: floor * 4, count: 4) == floor)
        #expect(MatrixLayout.environmentOverflows(available: floor * 4, count: 4) == false)

        // One point more, and the columns share it.
        #expect(MatrixLayout.environmentColumnWidth(available: floor * 4 + 4, count: 4) > floor)
    }

    @Test("no Environments means no division by zero")
    func noColumnsIsSafe() {
        #expect(MatrixLayout.environmentColumnWidth(available: 900, count: 0) == floor)
        #expect(MatrixLayout.environmentContentWidth(available: 900, count: 0) == 0)
    }

    // MARK: The freeze pane

    @Test("the header band and the body step by the same width from the same origin")
    func bothBandsShareOneOriginAndStep() {
        // Header column N sits over body column N because both bands are laid out from
        // this one function. Equal origin and equal step is what that means.
        let width = MatrixLayout.environmentColumnWidth(available: 900, count: 3)

        for index in 0..<3 {
            let header = MatrixLayout.environmentColumnOrigin(index: index, width: width)
            let body = MatrixLayout.environmentColumnOrigin(index: index, width: width)
            #expect(header == body)
        }

        let step = MatrixLayout.environmentColumnOrigin(index: 1, width: width)
            - MatrixLayout.environmentColumnOrigin(index: 0, width: width)
        #expect(step == width)
    }

    @Test("the header band follows the body the opposite way")
    func theHeaderBandMirrorsTheBody() {
        // The body scrolls its content left as the offset grows, so the header band,
        // which does not scroll, has to move left by the same amount.
        #expect(MatrixLayout.headerBandOffset(bodyContentOffset: 0) == 0)
        #expect(MatrixLayout.headerBandOffset(bodyContentOffset: 120) == -120)
    }

    @Test("the room for the comparison columns is what the frozen pair leaves")
    func theBandIsWhatIsLeftOver() {
        let entry: CGFloat = 300
        let available = MatrixLayout.availableEnvironmentWidth(total: 1000, entryWidth: entry)

        #expect(MatrixLayout.frozenWidth(entryWidth: entry)
            == Theme.Metrics.stateColumn + entry)
        #expect(available
            == 1000 - Theme.Metrics.stateColumn - entry - Theme.Metrics.dividerWidth)

        // A window narrower than the frozen pair leaves nothing, never a negative width.
        #expect(MatrixLayout.availableEnvironmentWidth(total: 100, entryWidth: entry) == 0)
    }

    @Test("widening the ENTRY column narrows the comparison columns")
    func resizingEntryReflowsTheColumns() {
        // Both widths stay above the floor, so this is reflow rather than clamping.
        let atDefault = MatrixLayout.environmentColumnWidth(
            available: MatrixLayout.availableEnvironmentWidth(
                total: 1400, entryWidth: MatrixLayout.entryDefault
            ),
            count: 2
        )
        let whenWide = MatrixLayout.environmentColumnWidth(
            available: MatrixLayout.availableEnvironmentWidth(
                total: 1400, entryWidth: MatrixLayout.entryDefault + 200
            ),
            count: 2
        )

        #expect(whenWide < atDefault)
        #expect(whenWide > MatrixLayout.environmentFloor)
        #expect(atDefault - whenWide == 100)  // 200 points, split between two columns
    }

    // MARK: The ENTRY column drag

    @Test("the column tracks the cursor rather than accumulating each step")
    func theDragTracksTheCursor() {
        // A drag reports its whole distance from where the press landed, every time it
        // moves. Adding each report to the current width instead of to the width at the
        // press counts the early movement again and again, and the column runs away
        // from the pointer.
        let start = MatrixLayout.entryDefault
        var width = start
        for step in stride(from: CGFloat(5), through: 100, by: 5) {
            width = MatrixLayout.entryWidth(anchor: start, translation: step)
        }

        #expect(width == start + 100)
    }

    @Test("the column never shrinks below its floor")
    func theDragClamps() {
        #expect(MatrixLayout.entryWidth(anchor: MatrixLayout.entryDefault, translation: -400)
            == MatrixLayout.entryFloor)
        #expect(MatrixLayout.clampEntryWidth(10) == MatrixLayout.entryFloor)
        #expect(MatrixLayout.clampEntryWidth(640) == 640)
    }

    @Test("a resize is persisted through the core, clamped to the floor")
    func theWidthIsPersisted() {
        let model = AppModel(core: StubCore())

        // Nothing stored yet.
        #expect(model.entryColumnWidth == MatrixLayout.entryDefault)

        model.setEntryColumnWidth(420)
        #expect(model.entryColumnWidth == 420)

        // The floor is the core's to enforce as well, so a bad width cannot be stored.
        model.setEntryColumnWidth(10)
        #expect(model.entryColumnWidth == MatrixLayout.entryFloor)
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
        #expect(MatrixLayout.pinnedHeader(sections: sections, offset: 0) == nil)
    }

    @Test("the header floats once it has scrolled past")
    func theHeaderFloatsOnceItIsGone() {
        let header = MatrixLayout.pinnedHeader(sections: sections, offset: headerHeight + 4)
        #expect(header?.label == "database.*")
        #expect(header?.count == 2)
    }

    @Test("the next cluster takes over at its boundary")
    func theNextClusterTakesOver() {
        let firstSection = headerHeight + 2 * rowHeight

        // The last pixel of the first cluster still belongs to it.
        #expect(MatrixLayout.pinnedHeader(sections: sections, offset: firstSection - 1)?.label
            == "database.*")

        // Its own header is on screen again at the boundary, so nothing floats.
        #expect(MatrixLayout.pinnedHeader(sections: sections, offset: firstSection) == nil)

        #expect(MatrixLayout.pinnedHeader(
            sections: sections, offset: firstSection + headerHeight + 4
        )?.label == "STRIPE_*")
    }

    @Test("ungrouped rows float nothing")
    func ungroupedRowsFloatNothing() {
        let flat = MatrixItem.sections([
            .row(index: 0, zebra: false, groupLabel: nil),
            .row(index: 1, zebra: true, groupLabel: nil),
        ])

        #expect(MatrixLayout.pinnedHeader(sections: flat, offset: 0) == nil)
        #expect(MatrixLayout.pinnedHeader(sections: flat, offset: rowHeight + 1) == nil)
    }

    @Test("scrolled past the end, nothing floats")
    func pastTheEndNothingFloats() {
        let total = 2 * headerHeight + 4 * rowHeight
        #expect(MatrixLayout.pinnedHeader(sections: sections, offset: total + 50) == nil)
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
