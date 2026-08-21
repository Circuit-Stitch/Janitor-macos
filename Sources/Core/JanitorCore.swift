//  JanitorCore.swift
//  The single seam between the SwiftUI shell and the Rust core.
//
//  The shell holds no auth, no AWS calls, no comparison, and no write logic. It renders
//  what the core sends and sends back what the operator did. Everything below this
//  protocol is Rust; everything above it is view code.
//
//  Two halves:
//
//  1. `send` plus `events` — the asynchronous command and event loop. A command returns
//     immediately and its answer arrives on the stream.
//  2. The pure functions — synchronous rules that are already tested in Rust. Prefix
//     clustering, the name split, the type badge, the state glyph, the drift badge, and
//     the error banner. The shell calls them. Reimplementing any of them in Swift would
//     move a tested rule into an untested layer.
//
//  There is one implementation today: `StubCore`, which serves canned data so the views
//  can be built and tested before the xcframework exists. `JanitorKitCore` joins it and
//  `StubCore` becomes a test fixture.

import Foundation

/// The load state of the selected Application.
enum LoadStatus: Sendable, Hashable {
    case idle
    case signingIn
    case loading
    case loaded
    case failed
}

/// One sidebar row.
struct SidebarApp: Sendable, Hashable, Identifiable {
    var id: Int
    var name: String
    /// `N envs`.
    var subtitle: String
    /// `N drift`, or empty when suppressed.
    var drift: String
}

protocol JanitorCore: AnyObject, Sendable {
    /// Events from the worker, in order. Consumed once, by the model.
    var events: AsyncStream<JanitorEvent> { get }

    /// Send a command. Returns immediately.
    func send(_ command: JanitorCommand)

    /// The Applications configured on disk, in sidebar order. Config holds locations
    /// only — never a Value.
    func applications() -> [(name: String, environmentCount: Int)]

    // MARK: Pure rules, decided in Rust

    /// Assemble the rendered row list. When `grouped`, Entry names that share a prefix
    /// collapse under a cluster header.
    func matrixItems(names: [String], grouped: Bool) -> [MatrixItem]

    /// Split an Entry name into the muted prefix and the bold leaf, first dropping the
    /// cluster prefix that its header already shows.
    func displayNameParts(groupLabel: String?, name: String) -> NameParts

    /// The type-badge text for a leaf kind. Empty for a Binary row, which has none.
    func badgeLabel(kind: LeafKind?) -> String

    /// The frozen STATE column glyph.
    func stateGlyph(_ state: EntryState) -> String

    /// The sidebar drift badge. It shows only on the selected, loaded row: the count
    /// comes from the loaded matrix, which describes that Application alone. Showing a
    /// count on the others would mean fetching every Application's secrets.
    func driftBadge(isSelected: Bool, status: LoadStatus, view: MatrixView) -> String

    /// The error banner: one `environment: detail` clause per failed Environment.
    func errorBanner(_ failures: [Failure]) -> String

    /// Which main pane to show, and what it says.
    func mainPane(status: LoadStatus, hasApplications: Bool) -> MainPane
    func paneTitle(_ pane: MainPane) -> String
    func paneBody(_ pane: MainPane, statusMessage: String?) -> String
}
