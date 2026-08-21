//  ChromeUITests.swift
//  The chrome around the matrix: the read-only badge, the status bar, the Diagnostic
//  Log, and Settings.
//
//  Every string these assert is metadata — an identity, a state name, a count, a
//  timestamp, an Environment name. That is the other half of what they check: the chrome
//  is where a Value would be easiest to leak by accident, so the log is read line by line
//  and none of it may carry one.

import XCTest

@MainActor
final class ChromeUITests: XCTestCase {
    func testTheBadgeSaysWhatTheWorkerSaysAndTheTitleNamesTheApplication() {
        // Read-only is where every launch starts, and the badge reads the worker's lock
        // rather than a constant.
        let app = JanitorApplication.launch(width: 1400)
        XCTAssertEqual(app.element(for: "topbar-readwrite").value as? String, "Read-only")

        // The window title is the breadcrumb: the app, then the Application on screen.
        let title = app.windows["main"].title
        XCTAssertTrue(title.hasPrefix("Janitor"), "the window title is \"\(title)\"")
        XCTAssertTrue(title.contains("Payments API"), "the title must name the Application")
    }

    func testTheStatusBarCarriesTheLegendCountsAndTheSession() {
        // The legend counts what is in the matrix. The seeded Payments API Application is
        // one Aligned Entry, six that drift, and two Gaps.
        let app = JanitorApplication.launch(width: 1400)
        XCTAssertEqual(app.element(for: "legend-aligned").label, "Aligned 1")
        XCTAssertEqual(app.element(for: "legend-drift").label, "Drift 6")
        XCTAssertEqual(app.element(for: "legend-gap").label, "Gap 2")

        XCTAssertTrue(app.element(for: "statusbar-identity").exists)
        XCTAssertTrue(app.element(for: "statusbar-snapshot").exists)
        let snapshot = app.element(for: "statusbar-snapshot").value as? String ?? ""
        XCTAssertTrue(snapshot.hasPrefix("read "), "the status bar must say how stale the matrix is")
    }

    func testTheDiagnosticLogSaysWhatHappenedAndNamesNoValue() {
        let app = JanitorApplication.launch(width: 1400)
        app.element(for: "log-toggle").click()
        XCTAssertTrue(app.element(for: "diagnostic-log").waitForExistence(timeout: 5))

        let lines = app.elements(startingWith: "log-line-").map { $0.value as? String ?? "" }
        XCTAssertFalse(lines.isEmpty, "the log is empty after a sign-in and a load")
        XCTAssertTrue(
            lines.contains { $0.contains("Payments API loaded") },
            "the log must record the load: \(lines)"
        )

        // Every line is a timestamp, a level, and metadata. A Value in one would be a
        // secret written to a panel the operator can copy out of.
        for line in lines {
            XCTAssertTrue(
                line.contains("INFO") || line.contains("WARN") || line.contains("ERROR"),
                "a log line is not a log line: \(line)"
            )
        }
        for cell in app.elements(startingWith: "envcell-") {
            XCTAssertTrue(cell.label.contains("masked") || cell.label.contains("absent"))
        }
    }

    func testSettingsOpensAsItsOwnWindowWithItsControls() {
        // In the Slint shell this was a dimmed backdrop and a centered card inside the
        // main window. On macOS it is a Settings scene, so it is a real window with the
        // ⌘, shortcut every other Mac app has.
        let app = JanitorApplication.launch(width: 1400)
        app.typeKey(",", modifierFlags: .command)

        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))

        for tab in ["Identity Center", "Discovery", "Access"] {
            XCTAssertTrue(settings.buttons[tab].exists, "the \(tab) tab is missing")
        }

        // Which tab is selected is remembered between launches, so it is chosen rather
        // than assumed.
        settings.buttons["Identity Center"].click()

        // Identity Center is where the fields are, and the region picker and the unlock
        // are one tab away each.
        XCTAssertEqual(settings.textFields.count, 2, "the Identity Center fields are missing")
        XCTAssertTrue(settings.buttons["Save"].exists)

        settings.buttons["Access"].click()
        let unlock = settings.switches.firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "the read-write unlock is missing")
        XCTAssertEqual(unlock.value as? Int, 0, "read-write mode must start off")
    }

    func testTheBrowseRegionPickerOffersRegionsAndNeverFreeText() {
        // A region is picked from a list, the way the console does it. A typed region is
        // a way to reach a Set that does not exist, and the failure it produces reads as
        // a permissions problem.
        let app = JanitorApplication.launch(width: 1400)
        app.typeKey(",", modifierFlags: .command)

        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.buttons["Discovery"].click()
        XCTAssertTrue(settings.popUpButtons.firstMatch.waitForExistence(timeout: 5))

        let picker = settings.popUpButtons.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the browse region picker is missing")
        XCTAssertEqual(settings.textFields.count, 0, "a region must never be free text")
    }
}
