//  Protocol.swift
//  The command and event vocabulary the shell speaks to the Rust core.
//
//  These types mirror `janitor_core`'s worker protocol one for one. Commands go in,
//  events come out, and nothing else crosses. When JanitorKit lands, UniFFI generates
//  the same shapes and this file is deleted — the views and the model above it keep
//  compiling because they were written against these names.
//
//  This slice drives the masked matrix, so it mirrors the 7 commands and 12 events the
//  matrix needs. The Discovery, write, and update halves of the protocol arrive with
//  the rest of the surface.
//
//  Nothing here carries a secret Value except `revealed` and `copyValue`, which carry
//  the one plaintext crossing.

import Foundation

// MARK: - Masked matrix

/// How an Entry compares across every Environment. The engine computes this across all
/// columns at once, so it never depends on column order.
enum EntryState: Sendable, Hashable {
    /// Present everywhere with identical Values.
    case aligned
    /// Present everywhere, Values differ.
    case drift
    /// Present in some Environments, missing in others.
    case gap
}

/// The JSON leaf type behind an Entry, used for the type badge. A Binary Set has none.
enum LeafKind: Sendable, Hashable {
    case string, number, bool, null, json
}

/// One masked cell. `present` carries byte length, the row-local equality group, and a
/// cosmetic tag — never a Value.
enum MatrixCell: Sendable, Hashable {
    /// Two cells in a row with the same `group` hold the same Value. `hex` is a
    /// four-character display flavor derived from the Entry name and the group, so
    /// equal cells look equal at a glance. The equality mechanism is `group`.
    case present(len: Int, group: UInt32, hex: String, kind: LeafKind?)
    /// Missing in this Environment.
    case absent
}

/// One projected row of the matrix.
struct MatrixRow: Sendable, Hashable {
    /// The Entry name, or `(whole set)` for a Set that is not JSON.
    var name: String
    var state: EntryState
    /// The row's representative leaf type for the badge.
    var kind: LeafKind?
    /// One cell per Environment, in `MatrixView.environments` order.
    var cells: [MatrixCell]
}

/// The masked matrix. It holds no Values, so the view may keep it as long as it likes.
struct MatrixView: Sendable, Hashable {
    var environments: [String] = []
    var rows: [MatrixRow] = []

    static let empty = MatrixView()
}

// MARK: - Rendered row list

/// One line of the rendered table: a prefix-cluster header, or a data row pointing back
/// at its index in `MatrixView.rows`.
///
/// The clustering that produces this list is a tested Rust seam. The shell asks for the
/// list and renders it; it never computes the clusters itself.
enum MatrixItem: Sendable, Hashable {
    /// A cluster header, such as `database.*`, and how many rows it covers.
    case header(label: String, count: Int)
    /// A data row. `index` addresses `MatrixView.rows` and is the reveal coordinate
    /// space. `zebra` is the shaded stripe, which restarts under each header. When the
    /// row sits under a header, `groupLabel` names it so the renderer can drop the
    /// prefix the header already shows.
    case row(index: Int, zebra: Bool, groupLabel: String?)
}

/// An Entry name split for the two-tone render: a muted prefix up to and including the
/// last separator, and the bold final segment.
struct NameParts: Sendable, Hashable {
    var prefix: String
    var leaf: String
}

/// What the main pane shows.
enum MainPane: Sendable, Hashable {
    /// Not signed in.
    case signIn
    /// Browser sign-in in flight.
    case signing
    /// Fetching the selected Application's secrets.
    case loading
    /// Signed in with no Applications configured. Points at the sidebar rather than
    /// showing an empty matrix.
    case emptyApps
    /// The matrix.
    case matrix
    /// A load failed.
    case error
}

// MARK: - Failures

/// One Environment's failure. `detail` is scrubbed before it gets here, so it never
/// carries a Value, a Credential, or SDK text.
struct Failure: Sendable, Hashable {
    var environment: String
    var detail: String
}

// MARK: - Commands

/// Shell to core. Every command returns immediately; the answer arrives as an event.
enum JanitorCommand: Sendable {
    /// Begin browser sign-in. Lazy — nothing touches AWS until this or `loadApp`.
    case signIn
    /// Load one Application by its index in the sidebar.
    case loadApp(index: Int)
    /// Fetch the plaintext of one cell for a momentary reveal.
    case reveal(row: Int, col: Int)
    /// The press was released. The core forgets the pending reveal.
    case endReveal
    /// Fetch the plaintext of one cell for the pasteboard.
    case copyValue(row: Int, col: Int)
    /// Flip the worker's read-write lock. The worker is the authority, not the UI: it
    /// refuses a write while locked without making any AWS call. Off every launch, and
    /// never persisted.
    case setReadWrite(Bool)
    /// Tear the worker down.
    case shutdown
}

// MARK: - Events

/// Core to shell.
enum JanitorEvent: Sendable {
    case signInStarted
    case signedIn(identity: String)
    /// Pre-masked reason. Never SDK text.
    case signInFailed(String)

    case appLoading
    /// A load succeeded. `appName` is carried so a load that finished after the user
    /// switched Applications can be dropped rather than painted over the new one.
    case appLoaded(view: MatrixView, appName: String)
    /// The load failed. A single failing Environment fails the whole Application, so
    /// the matrix is never partial.
    case appFailed(failures: [Failure])

    /// The one plaintext crossing, together with `copyValue`. `text` is a copy taken
    /// out of the zeroizing Value on the Rust side. Swift is never handed a pointer
    /// into that buffer.
    case revealed(row: Int, col: Int, text: String)
    /// The cell holds nothing revealable — absent here, or a Binary Set.
    case revealUnavailable

    /// A Value fetched for the pasteboard. The log records the Entry name, never this.
    case copyValue(row: Int, col: Int, text: String)
    case copyUnavailable

    /// A masked operator advisory about an unavoidable side effect of a read, such as
    /// org-wide SSM session logging archiving the file to S3.
    case warning(String)

    /// The worker's lock changed. This acknowledges a `setReadWrite`, so the chrome
    /// reflects the real state rather than what the UI asked for.
    case readWriteModeChanged(Bool)
}
