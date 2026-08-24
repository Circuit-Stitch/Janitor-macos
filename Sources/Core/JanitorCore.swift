//  JanitorCore.swift
//  The single seam between the SwiftUI shell and the Rust core.
//
//  The shell holds no auth, no AWS calls, no comparison, and no write logic. It renders
//  what the core sends and sends back what the operator did. Everything below this
//  protocol is Rust; everything above it is view code.
//
//  Three halves:
//
//  1. `send` plus `events` — the asynchronous command and event loop. A command returns
//     immediately and its answer arrives on the stream.
//  2. Config. It holds locations and view preferences, never a Value, and the core owns
//     it. The Manage and Settings windows read and write it through these calls rather
//     than keeping a copy, so there is one answer to what is configured and the shell is
//     never the place a Mapping is assembled.
//  3. The pure functions — synchronous rules already tested in Rust. Prefix clustering,
//     the name split, the type badge, the state glyph, the sidebar rows, and the pane
//     copy. The shell calls them. Reimplementing any of them in Swift would move a
//     tested rule into an untested layer.
//
//  Two implementations. `JanitorKitCore` drives the real worker over UniFFI and is what
//  the app runs. `StubCore` serves canned data and is what the tests drive, so a test
//  needs no AWS and no config file.
//
//  Indexes are `Int` here. Rust counts with `usize` and UniFFI crosses that as `UInt64`;
//  converting at this line is what keeps the conversion out of the views.

import Foundation
import JanitorKit

/// One sidebar row: an Application, its `N envs` subtitle, and the drift badge the core
/// decided. The index is the shell's, because SwiftUI selects on it.
struct SidebarRow: Sendable, Hashable, Identifiable {
    var id: Int
    var name: String
    var subtitle: String
    /// `N drift`, or empty when suppressed.
    var drift: String
}

protocol JanitorCore: AnyObject, Sendable {
    /// Events from the worker, in order. Consumed once, by the model.
    var events: AsyncStream<JanitorEvent> { get }

    /// Send a command. Returns immediately.
    func send(_ command: JanitorCommand)

    // MARK: Config

    // Every call here is synchronous: it reads or writes a file the core already has
    // open, and it makes no network call. A write that the core refuses — a blank name,
    // a duplicate Environment — changes nothing and says so.

    /// The Applications configured on disk, in sidebar order.
    func applications() -> [Application]

    /// One Application's Environments, in column order. Empty for an index that is out
    /// of range, so a Manage window bound to an Application that was removed elsewhere
    /// renders empty rather than trapping.
    func environments(of application: Int) -> [Mapping]

    /// Add an Application with no Environments and return its index. A blank name is
    /// refused and returns nil.
    @discardableResult
    func addApplication(name: String) -> Int?

    /// Remove an Application and everything mapped under it.
    func removeApplication(_ index: Int)

    /// Rename an Application. A blank name is refused, so a stray Return cannot erase
    /// one. Returns whether the name changed.
    @discardableResult
    func renameApplication(_ index: Int, to name: String) -> Bool

    /// Append a discovered Environment to one Application. An Environment name already
    /// present is refused rather than overwritten — overwriting one would silently
    /// retarget a compare column at a different Secret Set. Returns whether it landed.
    @discardableResult
    func addEnvironment(application: Int, mapping: Mapping) -> Bool

    /// Remove one Environment from one Application. This drops a compare column; it
    /// touches no Secret Set.
    func removeEnvironment(application: Int, index: Int)

    /// Fold roles a load recovered back into Config. Only the permission set moves, and
    /// only on the Environment the recovery was computed for. Returns how many changed.
    @discardableResult
    func applyCorrectedRoles(application: Int, corrected: [Mapping]) -> Int

    /// The account, role, and Secret last picked in a guided walk, offered as the
    /// default in the next one. Nil until the first successful pick.
    func lastPick() -> Mapping?

    /// The regions the browse picker offers: the known commercial regions, plus every
    /// region this operator already refers to, so their own region is always present.
    func regionChoices() -> [String]

    /// The region the next Discovery walk browses. One sticky value, shown in two
    /// places.
    func browseRegion() -> String
    func setBrowseRegion(_ region: String)

    /// The Identity Center start URL and the region that hosts it.
    func identityCenter() -> IdentityCenter
    func setIdentityCenter(startURL: String, region: String)

    /// The persisted width of the matrix's ENTRY column, in points.
    ///
    /// The caller supplies the floor and the fallback, so Config knows nothing about
    /// view sizes. It enforces one rule: a stored width is never returned below the
    /// floor, so a hand-edited config cannot render a column too narrow to read.
    func entryColumnWidth(minimum: Double, fallback: Double) -> Double

    /// Persist a resized ENTRY column, clamped to the floor the caller names.
    func setEntryColumnWidth(_ points: Double, minimum: Double)

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

    /// The sidebar rows. The drift badge shows only on the selected, loaded row: the
    /// count comes from the loaded matrix, which describes that Application alone.
    /// Showing a count on the others would mean fetching every Application's secrets.
    func sidebarRows(selected: Int, status: LoadStatus, view: MatrixView) -> [SidebarRow]

    /// The error banner: one `environment: detail` clause per failed Environment.
    func errorBanner(_ error: AppError) -> String

    /// Which main pane to show, and what it says.
    func mainPane(status: LoadStatus) -> MainPane
    func paneTitle(_ pane: MainPane) -> String
    func paneBody(_ pane: MainPane, statusMessage: String?) -> String

    /// The question above a Discovery picker, for what the walk is asking.
    func choicePrompt(_ what: What) -> String

    /// The Methods a picker offers, in order.
    func methodChoices() -> [SecretMethod]

    /// The short method tag on an Environment row.
    func methodLabel(_ method: SecretMethod) -> String

    /// The full method name, for the picker that chooses one before a walk.
    func methodName(_ method: SecretMethod) -> String

    /// Pending edits described by Entry name and Value length. The length is what makes
    /// a confirm dialog reviewable without putting the new Value on screen.
    func summarizeEdits(_ edits: [EnvEdit]) -> [EditSummary]
}
