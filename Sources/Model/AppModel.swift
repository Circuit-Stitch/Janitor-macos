//  AppModel.swift
//  The shell's whole mutable state, and the one place events turn into it.
//
//  Everything here is rendering state. No auth, no AWS call, no comparison, no write
//  logic. `apply` is a reducer: an event goes in and the properties the views read come
//  out. Two guards in it are load-bearing and are described where they are applied.

import Foundation
import Observation

/// The single revealed cell. One optional, not a set, so "exactly one cell un-masks" is
/// a property of the type rather than a rule someone has to keep.
struct RevealedCell: Sendable, Hashable {
    var row: Int
    var col: Int
    var text: String
}

/// One line of the Diagnostic Log.
struct LogLine: Sendable, Hashable, Identifiable {
    enum Level: String, Sendable { case info = "INFO", warn = "WARN", error = "ERROR" }
    var id = UUID()
    var at = Date()
    var level: Level
    var message: String
}

@Observable
@MainActor
final class AppModel {
    /// How long a reveal survives without a release. Plaintext should not outlive the
    /// operator's attention, and a press that never lands its release — a drag off the
    /// window, a system alert stealing the mouse — otherwise leaves it on screen.
    static let revealTimeout: Duration = .seconds(10)

    /// How long a copied Value stays on the pasteboard before it is cleared.
    static let pasteboardTimeout: Duration = .seconds(45)

    private let core: JanitorCore

    // MARK: Rendered state

    private(set) var apps: [SidebarApp] = []
    private(set) var selected = 0
    private(set) var status: LoadStatus = .idle
    private(set) var matrix: MatrixView = .empty
    /// The rendered row list, recomputed by the core whenever the matrix or the grouping
    /// switch changes.
    private(set) var items: [MatrixItem] = []
    private(set) var banner: String?
    private(set) var revealed: RevealedCell?
    private(set) var readWrite = false
    private(set) var identity: String?
    private(set) var loadedAt: Date?
    private(set) var log: [LogLine] = []

    var grouped = true {
        didSet { rebuildItems() }
    }
    var logVisible = false

    // MARK: Guards

    /// The cell whose press is still held. A reveal that arrives when this is nil, or
    /// names a different cell, is dropped: the operator already let go, and painting it
    /// would flash a secret on screen after the gesture ended.
    private var pendingReveal: (row: Int, col: Int)?

    /// The Application a load was started for. An `appLoaded` for anything else is
    /// dropped: the operator switched Applications while it was in flight, and applying
    /// it would paint one Application's matrix under another one's name.
    private var loadingApp: String?

    private var revealTimer: Task<Void, Never>?
    private var pasteboardTimer: Task<Void, Never>?

    init(core: JanitorCore) {
        self.core = core
        rebuildSidebar()
        Task { [weak self] in
            for await event in core.events {
                self?.apply(event)
            }
        }
    }

    // MARK: Intents

    func signIn() {
        core.send(.signIn)
    }

    func select(_ index: Int) {
        guard index != selected, index >= 0, index < apps.count else { return }
        selected = index
        endReveal()
        rebuildSidebar()
        loadSelected()
    }

    func loadSelected() {
        guard selected < apps.count else { return }
        banner = nil
        loadingApp = apps[selected].name
        core.send(.loadApp(index: selected))
    }

    /// Begin a momentary reveal of one cell. The plaintext arrives as an event.
    func beginReveal(row: Int, col: Int) {
        pendingReveal = (row, col)
        core.send(.reveal(row: row, col: col))
        revealTimer?.cancel()
        revealTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.revealTimeout)
            guard !Task.isCancelled else { return }
            self?.endReveal()
        }
    }

    /// End the reveal. Called on release, on the window losing focus, and on timeout.
    func endReveal() {
        revealTimer?.cancel()
        revealTimer = nil
        pendingReveal = nil
        if revealed != nil {
            revealed = nil
            core.send(.endReveal)
        }
    }

    /// Copy an Entry name. A name is metadata, so it goes on the pasteboard plainly.
    func copyName(_ name: String) {
        Pasteboard.copyPlain(name)
        note(.info, "\(name) name copied to clipboard")
    }

    /// Copy a cell's Value. The plaintext arrives as an event and goes straight to the
    /// pasteboard; it is never held in view state and never logged.
    func copyValue(row: Int, col: Int) {
        core.send(.copyValue(row: row, col: col))
    }

    /// Flip the read-write lock. The worker is the authority: it decides, and
    /// `readWriteModeChanged` is what moves this state.
    func setReadWrite(_ on: Bool) {
        core.send(.setReadWrite(on))
    }

    func shutdown() {
        endReveal()
        Pasteboard.clearIfOwned()
        core.send(.shutdown)
    }

    // MARK: Reducer

    func apply(_ event: JanitorEvent) {
        switch event {
        case .signInStarted:
            status = .signingIn
            note(.info, "signing in")

        case .signedIn(let identity):
            self.identity = identity
            note(.info, "signed in as \(identity)")
            loadSelected()

        case .signInFailed(let reason):
            status = .failed
            banner = reason
            note(.error, "sign-in failed: \(reason)")

        case .appLoading:
            status = .loading

        case .appLoaded(let view, let appName):
            // The stale-load guard.
            guard appName == loadingApp else { return }
            loadingApp = nil
            status = .loaded
            matrix = view
            banner = nil
            loadedAt = Date()
            rebuildItems()
            rebuildSidebar()
            note(.info, "\(appName) loaded — \(view.rows.count) entries across \(view.environments.count) environments")

        case .appFailed(let failures):
            loadingApp = nil
            status = .failed
            matrix = .empty
            items = []
            banner = core.errorBanner(failures)
            rebuildSidebar()
            for failure in failures {
                note(.error, "\(failure.environment): \(failure.detail)")
            }

        case .revealed(let row, let col, let text):
            // The release-race guard.
            guard let pending = pendingReveal, pending.row == row, pending.col == col else {
                return
            }
            revealed = RevealedCell(row: row, col: col, text: text)

        case .revealUnavailable:
            pendingReveal = nil
            revealed = nil

        case .copyValue(let row, let col, let text):
            Pasteboard.copyConcealed(text)
            armPasteboardClear()
            note(.info, "\(label(row: row, col: col)) copied to clipboard")

        case .copyUnavailable:
            note(.warn, "nothing to copy — the entry is absent here")

        case .warning(let text):
            note(.warn, text)

        case .readWriteModeChanged(let on):
            readWrite = on
            note(.warn, on ? "read-write mode unlocked" : "read-only mode")
        }
    }

    // MARK: Pure rules, forwarded to the core

    // The shell renders these; it does not decide them. Each one is a tested Rust
    // function reached through the seam.

    func displayNameParts(groupLabel: String?, name: String) -> NameParts {
        core.displayNameParts(groupLabel: groupLabel, name: name)
    }

    func badgeLabel(kind: LeafKind?) -> String {
        core.badgeLabel(kind: kind)
    }

    func stateGlyph(_ state: EntryState) -> String {
        core.stateGlyph(state)
    }

    /// Which main pane to show.
    var pane: MainPane {
        core.mainPane(status: status, hasApplications: !apps.isEmpty)
    }

    func paneTitle(_ pane: MainPane) -> String {
        core.paneTitle(pane)
    }

    /// On an error pane this carries the scrubbed reason the core produced.
    func paneBody(_ pane: MainPane) -> String {
        core.paneBody(pane, statusMessage: banner)
    }

    // MARK: Derived state

    private func rebuildItems() {
        items = core.matrixItems(names: matrix.rows.map(\.name), grouped: grouped)
    }

    private func rebuildSidebar() {
        apps = core.applications().enumerated().map { index, app in
            SidebarApp(
                id: index,
                name: app.name,
                subtitle: "\(app.environmentCount) envs",
                drift: core.driftBadge(
                    isSelected: index == selected, status: status, view: matrix
                )
            )
        }
    }

    /// `NAME[env]` — the non-secret name of a cell, for the log.
    private func label(row: Int, col: Int) -> String {
        guard row < matrix.rows.count, col < matrix.environments.count else { return "entry" }
        return "\(matrix.rows[row].name)[\(matrix.environments[col])]"
    }

    private func armPasteboardClear() {
        pasteboardTimer?.cancel()
        pasteboardTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.pasteboardTimeout)
            guard !Task.isCancelled else { return }
            Pasteboard.clearIfOwned()
            self?.note(.info, "clipboard cleared")
        }
    }

    /// Append to the Diagnostic Log. Never called with a Value.
    private func note(_ level: LogLine.Level, _ message: String) {
        log.append(LogLine(level: level, message: message))
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
    }
}
