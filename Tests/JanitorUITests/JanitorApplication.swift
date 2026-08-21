//  JanitorApplication.swift
//  Launching the app for a UI test, and finding things in it.
//
//  These tests drive the running app through the accessibility tree, which is the same
//  thing VoiceOver reads. Elements are found by identifier — `envcell-3-1`, `entryhdr`,
//  `pinned-database.*` — and every identifier is structural. It says where an element is
//  or which cluster it labels, never what a cell holds.
//
//  The app runs on `StubCore`, so every launch renders the same seeded Applications with
//  no network and no credential. The Values in it are fabricated.

import XCTest

@MainActor
enum JanitorApplication {
    /// The seeded Application the tests read: nine Entries across prod and staging, in
    /// three prefix clusters.
    static let seededEntries = 9
    static let seededEnvironments = 2

    /// Poll until a condition holds.
    ///
    /// XCUITest reads a snapshot of the accessibility tree, and a snapshot taken the
    /// instant after an event can be a frame behind what the app has already drawn.
    @discardableResult
    static func wait(upTo timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }

    /// Launch at a named window size and wait for the matrix.
    ///
    /// The size is the point. Which layout the matrix uses depends on how much room it
    /// has, so a test that asserts one has to name a width. `JANITOR_WINDOW_SIZE` is a
    /// debug-only hook in the app for exactly this.
    static func launch(width: Int, height: Int = 800) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JANITOR_WINDOW_SIZE"] = "\(width)x\(height)"
        // Otherwise a restored window frame from an earlier run overrides the size the
        // test asked for.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(
            app.element(for: "envhead-0").waitForExistence(timeout: 30),
            "the matrix did not render within 30 seconds"
        )
        return app
    }
}

extension XCUIApplication {
    /// One element by identifier, whatever type it is.
    func element(for identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }

    /// Every element whose identifier starts with `prefix`, in tree order.
    func elements(startingWith prefix: String) -> [XCUIElement] {
        let query = descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        return query.allElementsBoundByIndex
    }

    /// The identifiers of every element that starts with `prefix`.
    func identifiers(startingWith prefix: String) -> [String] {
        elements(startingWith: prefix).map(\.identifier)
    }

    /// The horizontally scrolling region that holds the comparison columns, found by the
    /// left edge it shares with the first cell in it.
    func comparisonRegion() -> XCUIElement {
        let firstCell = element(for: "envcell-0-0").frame
        let region = scrollViews.allElementsBoundByIndex.first {
            abs($0.frame.minX - firstCell.minX) < 1
        }
        return region ?? scrollViews.firstMatch
    }

    /// The vertically scrolling body, found by the left edge it shares with the frozen
    /// column.
    func bodyRegion() -> XCUIElement {
        let frozen = element(for: "state-cell-0").frame
        let region = scrollViews.allElementsBoundByIndex.first {
            $0.frame.minX < frozen.minX && $0.frame.maxX > frozen.maxX
        }
        return region ?? scrollViews.firstMatch
    }
}
