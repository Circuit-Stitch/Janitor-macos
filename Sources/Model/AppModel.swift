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

/// What the Discovery wizard is asking. The wizard has three question states and they
/// are mutually exclusive, so they are cases of one property rather than three
/// properties that have to be kept from overlapping.
enum DiscoveryState: Sendable, Hashable {
    /// No walk. The wizard is not shown.
    case idle
    /// A walk is between steps.
    case working(String)
    /// The walk needs a pick. `defaultIndex` is the remembered one.
    case choice(prompt: String, labels: [String], defaultIndex: Int?)
    /// The walk needs typed text, prefilled with `text`. A location, never a Value.
    case input(prompt: String, text: String)
    /// The walk ended without a Mapping. Dismissible, so the operator can adjust and
    /// try again.
    case terminal(String)
}

/// One open Manage window, and the Application it is bound to.
///
/// The binding is the point. `application` is fixed when the window opens and nothing
/// about the sidebar changes it. A discovered Environment lands on this index, so it
/// cannot arrive in whichever Application happens to be selected when the walk
/// finishes.
struct ManageSession: Sendable, Hashable {
    /// The bound Application, by sidebar index.
    var application: Int
    /// Its name at the time of the last refresh, for the window title.
    var name: String
    var environments: [Mapping]
    var discovery: DiscoveryState = .idle
    /// A masked advisory the walk surfaced, such as a read being archived by org-wide
    /// session logging. It rides alongside the question rather than replacing it.
    var advisory: String?
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

    // MARK: Manage and Settings

    /// The open Manage window, or nil when none is open.
    private(set) var manage: ManageSession?

    /// The region the next Discovery walk browses. One value, shown in Settings and
    /// again beside the add-Environment field, so the two pickers cannot disagree:
    /// they are the same property.
    private(set) var browseRegion = ""
    private(set) var regionChoices: [String] = []

    /// The Identity Center fields, as edited. They are a draft until saved, so a
    /// half-typed URL is never what the next sign-in uses.
    var ssoStartURL = ""
    var ssoRegion = ""

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
        rebuildConfig()
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

    /// Select an Application in the sidebar.
    ///
    /// This deliberately leaves `manage` alone. An open Manage window stays bound to the
    /// Application it was opened for, so a walk that finishes after the operator has
    /// moved on still lands where they started it.
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

    // MARK: Applications

    /// Add an Application and select it. It has no Environments yet, which is what the
    /// Manage window is for.
    func addApplication(named name: String) {
        guard let index = core.addApplication(name: name) else { return }
        rebuildSidebar()
        note(.info, "added application \(apps[index].name)")
        select(index)
        openManage(index)
    }

    /// Remove an Application, and close the Manage window if it was the one bound.
    func removeApplication(at index: Int) {
        guard index < apps.count else { return }
        let name = apps[index].name
        core.removeApplication(index)
        if manage?.application == index { manage = nil }
        rebuildSidebar()
        rebuildConfig()
        note(.info, "removed application \(name)")
        if selected >= apps.count { selected = max(0, apps.count - 1) }
        matrix = .empty
        items = []
        loadSelected()
    }

    // MARK: The Manage window

    /// Open the Manage window on one Application, or rebind an open one to it.
    ///
    /// Rebinding on an explicit open is not the same as retargeting on a selection
    /// change. This is the operator asking for this Application; a sidebar click is not.
    func openManage(_ index: Int) {
        guard index >= 0, index < apps.count else { return }
        manage = ManageSession(
            application: index,
            name: apps[index].name,
            environments: core.environments(of: index)
        )
    }

    func closeManage() {
        manage = nil
    }

    /// Rename the bound Application. A blank name is refused by the core, so the window
    /// keeps the name it had.
    func renameManagedApplication(to name: String) {
        guard var session = manage else { return }
        guard core.renameApplication(session.application, to: name) else { return }
        session.name = core.applications()[safe: session.application]?.name ?? session.name
        manage = session
        rebuildSidebar()
        note(.info, "renamed application to \(session.name)")
    }

    /// Remove one Environment from the bound Application. This drops a compare column
    /// and touches no Secret Set.
    func removeManagedEnvironment(at index: Int) {
        guard var session = manage else { return }
        let name = session.environments[safe: index]?.environment ?? ""
        core.removeEnvironment(application: session.application, index: index)
        session.environments = core.environments(of: session.application)
        manage = session
        rebuildSidebar()
        note(.info, "removed environment \(name) from \(session.name)")
        if session.application == selected { loadSelected() }
    }

    // MARK: Discovery

    /// Start a guided walk for a new Environment on the bound Application.
    func beginDiscovery(environment: String, method: SecretMethod) {
        let name = environment.trimmingCharacters(in: .whitespaces)
        guard var session = manage, !name.isEmpty else { return }
        session.discovery = .working("Discovering…")
        session.advisory = nil
        manage = session
        core.send(.beginDiscovery(method: method, environment: name, region: browseRegion))
    }

    /// Send the operator's pick back into the walk.
    func advanceDiscovery(choice: Int) {
        guard var session = manage else { return }
        session.discovery = .working("Discovering…")
        manage = session
        core.send(.advanceDiscovery(choice: choice))
    }

    /// Send the operator's typed answer back into the walk. It is a location, so it is
    /// safe to log — but there is nothing worth logging in it, so it is not.
    func provideInput(_ text: String) {
        guard var session = manage else { return }
        session.discovery = .working("Discovering…")
        manage = session
        core.send(.provideInput(text))
    }

    /// Dismiss a finished walk's message so the operator can adjust and retry.
    func dismissDiscovery() {
        guard var session = manage else { return }
        session.discovery = .idle
        session.advisory = nil
        manage = session
    }

    // MARK: Settings

    /// Persist the browse region. Both pickers read this back, because both are bound to
    /// the same property.
    func setBrowseRegion(_ region: String) {
        guard region != browseRegion else { return }
        core.setBrowseRegion(region)
        rebuildConfig()
        note(.info, "discovery browses \(browseRegion)")
    }

    /// Save the Identity Center fields. It takes effect on the next sign-in.
    func saveIdentityCenter() {
        core.setIdentityCenter(startURL: ssoStartURL, region: ssoRegion)
        rebuildConfig()
        note(.info, "identity center saved — sign in again to use it")
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
            // An advisory raised during a walk belongs in the wizard too, beside the
            // question rather than instead of it. With no wizard open the log is the
            // whole of it.
            if var session = manage, session.discovery != .idle {
                session.advisory = text
                manage = session
            }

        case .readWriteModeChanged(let on):
            readWrite = on
            note(.warn, on ? "read-write mode unlocked" : "read-only mode")

        // MARK: Discovery

        case .envDiscovered(let mapping):
            // The binding rule. The Mapping lands on the Application the window was
            // opened for. `selected` is not consulted, so a walk that finishes after the
            // operator moved on still lands where they started it.
            guard var session = manage else { return }
            guard core.addEnvironment(application: session.application, mapping: mapping) else {
                session.discovery = .terminal(
                    "\(mapping.environment) already exists in \(session.name)."
                )
                manage = session
                return
            }
            session.environments = core.environments(of: session.application)
            session.discovery = .idle
            session.advisory = nil
            manage = session
            rebuildSidebar()
            rebuildConfig()
            note(.info, "added \(mapping.environment) to \(session.name)")
            if session.application == selected { loadSelected() }

        case .discoveryChoice(let what, let labels, let defaultIndex):
            guard var session = manage else { return }
            session.discovery = .choice(
                prompt: core.choicePrompt(what), labels: labels, defaultIndex: defaultIndex
            )
            manage = session

        case .discoveryInput(_, let prompt, let defaultText):
            guard var session = manage else { return }
            session.discovery = .input(prompt: prompt, text: defaultText ?? "")
            manage = session

        case .discoveryFailed(let reason):
            note(.error, "discovery failed: \(reason)")
            guard var session = manage else { return }
            session.discovery = .terminal("Could not add: \(reason)")
            manage = session

        case .discoveryReauthRequired:
            // Not a walk failure. The session is gone, so the whole window goes back to
            // sign-in rather than offering a retry inside the wizard.
            status = .failed
            banner = "Session expired — sign in again."
            note(.error, "session expired during discovery")
            if var session = manage {
                session.discovery = .terminal("Session expired — sign in again.")
                manage = session
            }

        // MARK: Write outcomes

        case .writeApplied(let environment):
            note(.info, "\(environment): edits applied")
            // Re-read, so the matrix shows what is now there rather than what was.
            loadSelected()

        case .writeConflict(let environment):
            note(.warn, "\(environment): the set changed under the write — nothing was overwritten")

        case .writeFailed(let environment, let detail):
            note(.error, "\(environment): write failed — \(detail)")

        case .writeRefused(let environment):
            note(.warn, "\(environment): write refused — read-write mode is off")
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

    /// The short method tag on an Environment row.
    func methodLabel(_ method: SecretMethod) -> String {
        core.methodLabel(method)
    }

    /// The full method name, for the picker that chooses one before a walk.
    func methodName(_ method: SecretMethod) -> String {
        core.methodName(method)
    }

    /// A pending edit, described by Entry name and Value length.
    func summarizeEdits(_ edits: [EnvEdit]) -> [String] {
        core.summarizeEdits(edits)
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

    /// Re-read the parts of Config the windows show. Config is the core's, so this is a
    /// read rather than a cache: the model holds the last answer, never its own copy.
    private func rebuildConfig() {
        regionChoices = core.regionChoices()
        browseRegion = core.browseRegion()
        let identity = core.identityCenter()
        ssoStartURL = identity.startURL
        ssoRegion = identity.region
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
