//  MatrixUITests.swift
//  What the matrix actually renders, asserted against the running app.
//
//  These are the Slint shell's view tests, brought over. Both shells claim the same
//  things about the matrix: the comparison columns stretch to fill and then hold a floor,
//  each Environment name sits over its own column, the state glyph and the Entry name
//  never scroll away, a cluster header pins while its rows are on screen, and no cell
//  shows a Value unless it is held.
//
//  `MatrixLayoutTests` proves the arithmetic behind those rules. These prove the views
//  are wired to it. A rule can be right and unused, and that is the failure this file
//  exists to catch.

import XCTest

@MainActor
final class MatrixUITests: XCTestCase {
    // MARK: What a cell shows

    func testEveryCellIsMaskedOrAbsent() {
        // The whole matrix, read the way VoiceOver reads it. A masked cell describes its
        // shape — byte count and equality group — and an absent one says so. Nothing
        // else is allowed to be on screen.
        let app = JanitorApplication.launch(width: 1400)
        let cells = app.elements(startingWith: "envcell-")
        XCTAssertEqual(
            cells.count,
            JanitorApplication.seededEntries * JanitorApplication.seededEnvironments
        )

        for cell in cells {
            let label = cell.label
            let masked = label.contains(": masked, ") && label.contains(" bytes, group ")
            let absent = label.hasSuffix(": absent")
            XCTAssertTrue(masked || absent, "a cell reads \"\(label)\", which is neither masked nor absent")
        }
    }

    func testARevealEndsWhenThePressDoes() {
        // Press and hold reveals one cell; letting go hides it at once. The showing half
        // is a model test — XCUITest cannot look at the screen in the middle of its own
        // press — so what is checked here is that letting go ends it.
        //
        // It did not, once. A `DragGesture` whose press never moves does not deliver its
        // end event on macOS, so a released Value stayed on screen until the ten-second
        // timeout took it down.
        let app = JanitorApplication.launch(width: 1400)
        let endReveal = app.menuBars.menuItems["End Reveal"]
        XCTAssertFalse(endReveal.isEnabled, "nothing is revealed before the press")

        let cell = app.element(for: "envcell-0-0")
        let masked = cell.label
        cell.press(forDuration: 1.0)

        XCTAssertFalse(endReveal.isEnabled, "the reveal must end when the press does")
        XCTAssertEqual(app.element(for: "envcell-0-0").label, masked, "the cell is masked again")
    }

    // MARK: The comparison columns

    func testColumnsStretchToFillAWideWindow() {
        // Two Environments in a wide window: they divide the whole region rather than
        // sitting at their floor with a gutter to the right of them.
        let app = JanitorApplication.launch(width: 1400)
        let region = app.comparisonRegion().frame
        let first = app.element(for: "envcell-0-0").frame
        let last = app.element(for: "envcell-0-1").frame

        XCTAssertGreaterThan(first.width, 250, "the columns did not stretch past their floor")
        XCTAssertEqual(first.minX, region.minX, accuracy: 1)
        XCTAssertEqual(last.maxX, region.maxX, accuracy: 2, "a gutter is left at the right")
    }

    func testColumnsHoldTheirFloorAndOverflowInANarrowWindow() {
        // The same two Environments with less room than two floors. They stop shrinking
        // and the region scrolls instead, because a column narrower than the masked cell
        // in it shows nothing worth reading.
        let app = JanitorApplication.launch(width: 900)
        let region = app.comparisonRegion().frame
        let first = app.element(for: "envcell-0-0").frame
        let last = app.element(for: "envcell-0-1").frame

        XCTAssertEqual(first.width, 200, accuracy: 1, "the column did not hold its floor")
        XCTAssertLessThan(region.width, 400, "this window is not narrow enough to test the floor")
        XCTAssertGreaterThan(last.maxX, region.maxX + 1, "the columns must overflow and scroll")
    }

    func testEachEnvironmentNameSitsOverItsOwnColumn() {
        for width in [1400, 1100, 900] {
            let app = JanitorApplication.launch(width: width)
            let insets = (0..<JanitorApplication.seededEnvironments).map { column in
                app.element(for: "envhead-\(column)").frame.minX
                    - app.element(for: "envcell-0-\(column)").frame.minX
            }

            // One inset for every column means one origin and one step in both bands. A
            // header that drifted would show up as a different inset on a later column.
            for (column, inset) in insets.enumerated() {
                XCTAssertEqual(
                    inset, insets[0], accuracy: 1,
                    "at \(width)pt the name over column \(column) is off its own column"
                )
                XCTAssertGreaterThanOrEqual(inset, 0)
            }
            app.terminate()
        }
    }

    // MARK: The frozen pair

    func testTheStateColumnIsFrozenLeftOfTheEntryColumn() {
        let app = JanitorApplication.launch(width: 1400)
        let state = app.element(for: "state-cell-0").frame
        let entry = app.element(for: "entry-cell-0").frame
        let firstValue = app.element(for: "envcell-0-0").frame

        XCTAssertLessThan(state.minX, entry.minX, "STATE must sit left of ENTRY")
        XCTAssertLessThan(entry.minX, firstValue.minX, "ENTRY must sit left of the columns")

        // The header band and the body start the frozen pair at the same place, so the
        // ENTRY heading is directly above the Entry names.
        XCTAssertEqual(app.element(for: "entryhdr").frame.minX, entry.minX, accuracy: 1)
    }

    func testTheStateWordIsCarriedOnlyByTheStateColumn() {
        // The row draws a glyph, not a word, and the glyph is the row's only state
        // carrier. VoiceOver still gets the word, because a glyph alone reads as nothing.
        let app = JanitorApplication.launch(width: 1400)
        XCTAssertEqual(app.element(for: "state-cell-0").label, "Aligned")
        XCTAssertEqual(app.element(for: "state-cell-1").label, "Drift")
        XCTAssertEqual(app.element(for: "state-cell-2").label, "Gap")

        for row in 0..<JanitorApplication.seededEntries {
            let name = app.element(for: "entry-cell-\(row)").label
            for word in ["Aligned", "Drift", "Gap"] {
                XCTAssertFalse(name.contains(word), "the Entry cell repeats the state word")
            }
        }
    }

    func testEveryRowIsOneLine() {
        // One line per Entry. A second line for the state word cost a third of the rows
        // on screen and the word is in the STATE column now.
        let app = JanitorApplication.launch(width: 1400)
        for row in 0..<JanitorApplication.seededEntries {
            XCTAssertEqual(
                app.element(for: "envcell-\(row)-0").frame.height, 30, accuracy: 1,
                "row \(row) is not a single line"
            )
        }
    }

    func testAGroupedRowKeepsItsWholeNameForVoiceOver() {
        // Grouping strips the prefix the cluster header already shows, so the row draws
        // less than the Entry is called. The whole name stays in the accessibility label,
        // and on hover.
        let app = JanitorApplication.launch(width: 1400)
        XCTAssertTrue(app.element(for: "cluster-GITHUB_APP_*").exists)
        XCTAssertEqual(app.element(for: "entry-cell-1").label, "GITHUB_APP_PRIVATE_KEY")
    }

    func testClickingAnEntryNameDoesNotCopyIt() {
        // Copying is a menu action, not something a stray click does. The log is what
        // says whether anything was copied, and it stays quiet.
        let app = JanitorApplication.launch(width: 1400)
        app.element(for: "entry-cell-1").click()

        app.element(for: "log-toggle").click()
        XCTAssertTrue(app.element(for: "diagnostic-log").waitForExistence(timeout: 5))
        let lines = app.elements(startingWith: "log-line-").map { $0.value as? String ?? "" }
        XCTAssertFalse(
            lines.contains { $0.contains("copied to clipboard") },
            "a click on an Entry name must not copy it: \(lines)"
        )
    }

    // MARK: The ENTRY column drag

    func testDraggingTheEntryColumnWidensItAndReflowsTheColumns() {
        let app = JanitorApplication.launch(width: 1400)
        let frozenOrigin = app.element(for: "entry-cell-0").frame.minX
        let handleBefore = app.element(for: "entry-resize-handle").frame.minX
        let columnBefore = app.element(for: "envcell-0-0").frame.width

        XCTAssertTrue(
            drag(app, by: 150) {
                app.element(for: "entry-resize-handle").frame.minX > handleBefore + 20
            },
            "dragging right must widen the ENTRY column"
        )
        XCTAssertLessThan(
            app.element(for: "envcell-0-0").frame.width, columnBefore - 20,
            "a wider ENTRY column leaves less for the comparison columns"
        )
        // The frozen pair still starts where it started. The matrix must not slide out
        // from under its own header.
        XCTAssertEqual(app.element(for: "entry-cell-0").frame.minX, frozenOrigin, accuracy: 1)
        XCTAssertEqual(app.element(for: "entryhdr").frame.minX, frozenOrigin, accuracy: 1)
    }

    func testTheEntryColumnStopsAtItsFloor() {
        let app = JanitorApplication.launch(width: 1400)
        let entryLeft = app.element(for: "entry-cell-0").frame.minX - 8

        // The handle sits on the column's right edge, so where the handle ends up is the
        // column's width. Dragged far past the floor, it stops at the floor.
        func width() -> CGFloat {
            app.element(for: "entry-resize-handle").frame.midX - entryLeft
        }
        XCTAssertTrue(
            drag(app, by: -600) { abs(width() - 200) <= 2 },
            "the ENTRY column stopped at \(width()) points, not at its 200 point floor"
        )
    }

    func testAResizeSurvivesAReload() {
        // The width is persisted when the drag ends, and the table reads it back when it
        // is built. A refresh tears the table down and builds it again, so it is the
        // cheapest way to see whether the width was stored at all.
        let app = JanitorApplication.launch(width: 1400)
        let before = app.element(for: "entry-resize-handle").frame.minX
        XCTAssertTrue(drag(app, by: 150) {
            app.element(for: "entry-resize-handle").frame.minX > before + 20
        })
        let widened = app.element(for: "entry-resize-handle").frame.minX

        app.buttons["Refresh"].click()
        XCTAssertTrue(app.element(for: "envhead-0").waitForExistence(timeout: 10))

        XCTAssertEqual(
            app.element(for: "entry-resize-handle").frame.minX, widened, accuracy: 1,
            "the ENTRY column went back to its default, so the resize was never stored"
        )
    }

    /// Drag the ENTRY column's handle until `settled` holds. Returns whether it ever did.
    ///
    /// A synthesized drag does not always deliver the whole distance it was given, and a
    /// short one is the test environment rather than the app — a real pointer moving
    /// across the screen at the same moment is enough to eat some of it. What the app
    /// owes is where the column ends up, so the drag repeats until it gets there.
    private func drag(_ app: XCUIApplication, by dx: CGFloat, until settled: () -> Bool)
        -> Bool
    {
        for _ in 1...6 {
            let handle = app.element(for: "entry-resize-handle")
            let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
            if JanitorApplication.wait(upTo: 0.5, until: settled) { return true }
        }
        return false
    }

    // MARK: The pinned cluster header

    func testAClusterHeaderPinsWhileItsRowsAreOnScreen() {
        // The log panel is opened to make the body shorter than its rows, which is what
        // gives the test something to scroll.
        let app = JanitorApplication.launch(width: 1000, height: 520)
        app.element(for: "log-toggle").click()
        XCTAssertTrue(app.element(for: "diagnostic-log").waitForExistence(timeout: 5))

        XCTAssertEqual(app.identifiers(startingWith: "pinned-"), [],
                       "nothing pins while every cluster's own header is on screen")

        // Any scroll at all takes the first cluster's header off the top, so the
        // question is only whether the body moved. A synthesized wheel event is
        // sometimes dropped on the way in, and a dropped one is not a failure to pin.
        let body = app.bodyRegion()
        let top = app.element(for: "entry-cell-0").frame.minY
        XCTAssertTrue(
            scroll(body, app, by: 30) { app.element(for: "entry-cell-0").frame.minY < top - 5 },
            "the body never scrolled, so there was nothing to pin over"
        )
        XCTAssertTrue(
            JanitorApplication.wait {
                app.identifiers(startingWith: "pinned-") == ["pinned-GITHUB_APP_*"]
            },
            "the first cluster must pin once its own header has scrolled past: "
                + "\(app.identifiers(startingWith: "pinned-"))"
        )

        XCTAssertTrue(
            scroll(body, app, by: -60) { app.element(for: "entry-cell-0").frame.minY >= top - 1 },
            "the body never scrolled back"
        )
        XCTAssertTrue(
            JanitorApplication.wait { app.identifiers(startingWith: "pinned-").isEmpty },
            "back at the top, the cluster's own header is on screen and nothing pins"
        )
    }

    /// Wheel-scroll `region` until `settled` holds, hovering a row first so the pointer
    /// is over the thing being scrolled. Returns whether it ever settled.
    private func scroll(
        _ region: XCUIElement,
        _ app: XCUIApplication,
        by delta: CGFloat,
        until settled: () -> Bool
    ) -> Bool {
        for _ in 1...8 {
            app.element(for: "entry-cell-3").hover()
            region.scroll(byDeltaX: 0, deltaY: delta)
            if JanitorApplication.wait(upTo: 0.5, until: settled) { return true }
        }
        return false
    }
}
