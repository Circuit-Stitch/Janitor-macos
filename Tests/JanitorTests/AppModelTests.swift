//  AppModelTests.swift
//  The reducer's rules, driven the way the core drives it.
//
//  Every test feeds events into `apply` and asserts what the views would render. None of
//  them reaches into a view. That is deliberate: the command and event protocol is the
//  seam, and a test written against it survives a view rewrite.
//
//  Nearly all of Janitor's logic is tested in Rust. What is left for these tests is what
//  the shell genuinely owns — the two race guards and the reveal lifetime.

import JanitorKit
import Testing
import Foundation
@testable import Janitor

@MainActor
struct AppModelTests {
    private func model() -> AppModel {
        AppModel(core: StubCore())
    }

    private func view(_ appName: String) -> MatrixView {
        MatrixView(
            environments: ["prod", "staging"],
            rows: [
                MatrixRow(
                    key: .entry("A"),
                    name: "A", state: .drift, kind: .string,
                    cells: [
                        .present(len: 3, group: 1, hex: "aaaa", kind: .string),
                        .present(len: 4, group: 2, hex: "bbbb", kind: .string),
                    ]
                ),
                MatrixRow(
                    key: .entry("B"),
                    name: "B", state: .drift, kind: .string,
                    cells: [
                        .present(len: 5, group: 1, hex: "cccc", kind: .string),
                        .present(len: 6, group: 2, hex: "dddd", kind: .string),
                    ]
                ),
            ]
        )
    }

    /// A model with a matrix on screen. A reveal is addressed by the row's key, which
    /// comes from the loaded matrix, so a reveal before a load asks for nothing.
    private func loaded() -> AppModel {
        let model = model()
        model.loadSelected()
        model.apply(.appLoaded(
            view: view("Payments API"), corrected: [], appName: "Payments API"
        ))
        return model
    }

    // MARK: The stale-load guard

    @Test("a load for the Application that was asked for is applied")
    func loadForTheSelectedApplicationLands() {
        let model = model()
        model.loadSelected()
        model.apply(.appLoaded(view: view("Payments API"), corrected: [], appName: "Payments API"))

        #expect(model.status == .loaded)
        #expect(model.matrix.rows.count == 2)
    }

    @Test("a load that names a different Application is dropped")
    func loadForAnotherApplicationIsDropped() {
        let model = model()
        model.loadSelected()

        // The operator switched while this one was in flight. Applying it would paint
        // one Application's matrix under another one's name.
        model.apply(.appLoaded(view: view("Auth Service"), corrected: [], appName: "Auth Service"))

        #expect(model.matrix.rows.isEmpty)
        #expect(model.status != .loaded)
    }

    // MARK: The release-race guard

    @Test("a revealed Value for the held cell is shown")
    func revealForTheHeldCellIsShown() {
        let model = loaded()
        model.beginReveal(row: 0, col: 1)
        model.apply(.revealed(row: 0, col: 1, text: "hunter2"))

        #expect(model.revealed?.text == "hunter2")
        #expect(model.revealed?.row == 0)
        #expect(model.revealed?.col == 1)
    }

    @Test("a revealed Value arriving after the release is dropped")
    func revealAfterReleaseIsDropped() {
        let model = loaded()
        model.beginReveal(row: 0, col: 1)
        model.endReveal()

        // The operator already let go. Painting this would flash a secret on screen
        // after the gesture ended.
        model.apply(.revealed(row: 0, col: 1, text: "hunter2"))

        #expect(model.revealed == nil)
    }

    @Test("a revealed Value for a cell that is not the held one is dropped")
    func revealForAnotherCellIsDropped() {
        let model = loaded()
        model.beginReveal(row: 0, col: 1)
        model.apply(.revealed(row: 3, col: 0, text: "hunter2"))

        #expect(model.revealed == nil)
    }

    @Test("beginning a second reveal replaces the first")
    func onlyOneCellIsEverRevealed() {
        let model = loaded()
        model.beginReveal(row: 0, col: 0)
        model.apply(.revealed(row: 0, col: 0, text: "first"))
        model.beginReveal(row: 1, col: 1)
        model.apply(.revealed(row: 1, col: 1, text: "second"))

        #expect(model.revealed?.text == "second")
        #expect(model.revealed?.row == 1)
    }

    @Test("an unavailable reveal clears the pending state")
    func revealUnavailableClears() {
        let model = model()
        model.beginReveal(row: 0, col: 1)
        model.apply(.revealUnavailable)

        #expect(model.revealed == nil)

        // The press is forgotten, so a late Value for it is dropped too.
        model.apply(.revealed(row: 0, col: 1, text: "hunter2"))
        #expect(model.revealed == nil)
    }

    // MARK: Failures

    @Test("a failed load shows the banner and clears the matrix")
    func failedLoadShowsTheBanner() {
        let model = model()
        model.loadSelected()
        model.apply(.appLoaded(view: view("Payments API"), corrected: [], appName: "Payments API"))
        model.loadSelected()
        model.apply(.appFailed(AppError(failures: [
            Failure(environment: "prod", reason: .notFound, detail: "secret not found"),
            Failure(environment: "dev", reason: .accessDenied, detail: "the role is not assigned"),
        ])))

        #expect(model.status == .failed)
        #expect(model.matrix.rows.isEmpty)
        #expect(model.banner == "prod: secret not found; dev: the role is not assigned")
    }

    // MARK: The read-write lock

    @Test("read-write mode starts off and follows the worker")
    func readWriteFollowsTheWorker() {
        let model = model()
        #expect(model.readWrite == false)

        // Asking is not the same as being unlocked. The worker decides, and the
        // acknowledgement is what moves the state.
        model.setReadWrite(true)
        #expect(model.readWrite == false)

        model.apply(.readWriteModeChanged(true))
        #expect(model.readWrite == true)
    }

    // MARK: The Diagnostic Log

    @Test("a copied Value is logged by name, never by content")
    func copyLogsTheNameNotTheValue() {
        let model = model()
        model.loadSelected()
        model.apply(.appLoaded(view: view("Payments API"), corrected: [], appName: "Payments API"))
        model.apply(.copyValue(row: 0, col: 1, text: "hunter2"))

        let lines = model.log.map(\.message)
        #expect(lines.contains { $0.contains("A[staging]") })
        #expect(!lines.contains { $0.contains("hunter2") })
    }

    @Test("no log line ever carries a revealed Value")
    func theLogNeverCarriesAValue() {
        let model = model()
        model.loadSelected()
        model.apply(.appLoaded(view: view("Payments API"), corrected: [], appName: "Payments API"))
        model.beginReveal(row: 0, col: 0)
        model.apply(.revealed(row: 0, col: 0, text: "hunter2"))
        model.apply(.warning("session logging archives this read to S3"))

        #expect(!model.log.contains { $0.message.contains("hunter2") })
    }
}
