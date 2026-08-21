//  Protocol.swift
//  The command and event vocabulary the shell speaks to the Rust core.
//
//  These types mirror `janitor_core`'s worker protocol one for one. Commands go in,
//  events come out, and nothing else crosses. When JanitorKit lands, UniFFI generates
//  the same shapes and this file is deleted — the views and the model above it keep
//  compiling because they were written against these names.
//
//  It mirrors 10 of the worker's 12 commands and 21 of its 23 events. The two missing
//  pairs drive the Windows MSIX updater. A Mac App Store build is updated by the App
//  Store, so naming them here would be vocabulary the shell can never speak.
//
//  Field names follow what UniFFI generates from the Rust, not Swift's own
//  conventions — `accountId`, not `accountID`. This file exists to be deleted, and
//  matching the generated spelling is what makes deleting it mechanical.
//
//  One name deliberately does not match. Rust calls it `Method`, and so will the
//  generated Swift, but a type named `Method` shadows the Objective-C runtime's `Method`
//  for this whole module. It compiles, and then tooling resolves the wrong one in any
//  file that does not see ours. It is `SecretMethod` here, and one typealias reconciles
//  the two when JanitorKit lands.
//
//  Nothing here carries a secret Value except `revealed`, `copyValue`, and an
//  `EnvEdit.set`. Those three are the plaintext crossings.

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

// MARK: - Configuration

/// Which backend holds one Environment's Set. The operator picks it before a walk
/// starts, so the walk runs that method's steps, and it tags the Environment
/// afterwards.
///
/// Named `Method` in the Rust. See the note at the top of this file for why it is not
/// named that here.
enum SecretMethod: Sendable, Hashable, CaseIterable, Identifiable {
    /// AWS Secrets Manager.
    case secretsManager
    /// A remote `.env` on an SSM-managed instance, read over Session Manager.
    case ssmDotenv

    var id: Self { self }
}

/// Where one Environment's Set lives. An account, a region, a Set id, a role, and the
/// method that reaches it. Locations only — this is what Config persists, and it never
/// holds a Value.
struct Mapping: Sendable, Hashable, Identifiable {
    var environment: String
    var accountId: String
    var region: String
    var secretId: String
    var permissionSet: String
    var method: SecretMethod

    /// Environment names are unique within an Application — adding a duplicate is
    /// refused rather than applied — so the name identifies the row.
    var id: String { environment }
}

// MARK: - Discovery

/// What a guided walk is asking for. It titles the picker. The shell reads no further
/// meaning into it.
enum What: Sendable, Hashable {
    case accounts
    case roles
    case secrets
    case instances
    case filePath
}

// MARK: - Writes

/// One surgical edit to one Environment's Set, keyed by a literal Entry name.
///
/// A `set` carries a plaintext Value. It exists for as long as it takes to reach the
/// core, which holds it in a zeroizing buffer. It is never logged, never rendered, and
/// never put in view state.
enum EnvEdit: Sendable {
    /// Give `key` this Value, replacing what is there or adding the Entry if it is
    /// missing.
    case set(key: String, value: String)
    /// Remove `key` from the Set.
    case remove(key: String)

    /// The Entry name this edit touches. A name is metadata, so it is safe to show and
    /// to log.
    var key: String {
        switch self {
        case .set(let key, _): key
        case .remove(let key): key
        }
    }
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

    /// Start a guided walk that fills in one new Environment. The operator supplies the
    /// name, the method, and the region to browse; the account, the role, and the Set
    /// are discovered. The walk answers with `discoveryChoice` or `discoveryInput` until
    /// it reaches `envDiscovered`.
    case beginDiscovery(method: SecretMethod, environment: String, region: String)
    /// The operator picked row `choice` of the pending list, and the walk resumes.
    case advanceDiscovery(choice: Int)
    /// The operator answered a free-text step, such as a path on a remote host. The text
    /// is a location, never a Value.
    case provideInput(String)

    /// Apply edits to one Environment's Set through the non-stomping write engine. The
    /// worker refuses it while locked, and refuses it before making any AWS call.
    case applyEdits(environment: String, edits: [EnvEdit])

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

    // MARK: Discovery

    /// A walk finished and produced a Mapping. Where it lands is the shell's to decide,
    /// and the shell's answer is always the Application the Manage window was opened
    /// for. The Mapping is locations only.
    case envDiscovered(mapping: Mapping)
    /// The walk needs a pick. `labels` are presenter lines — an account, a role, a Set
    /// name — and `defaultIndex` is the remembered pick to preselect.
    case discoveryChoice(what: What, labels: [String], defaultIndex: Int?)
    /// The walk needs typed text. `defaultText` is a remembered answer to prefill.
    /// Both are locations, never Values.
    case discoveryInput(what: What, prompt: String, defaultText: String?)
    /// The walk could not finish. Pre-masked reason.
    case discoveryFailed(String)
    /// The SSO token is dead and could not be refreshed. This is not a walk failure:
    /// the shell routes back to sign-in rather than offering a retry in the wizard.
    case discoveryReauthRequired

    // MARK: Write outcomes

    /// The compare-and-swap matched and the replace landed. `environment` names the
    /// column. The edits themselves never appear in an event.
    case writeApplied(environment: String)
    /// The Set changed underneath the write and the bounded retries ran out. Nothing
    /// was overwritten. The operator re-reads and tries again.
    case writeConflict(environment: String)
    /// The write failed. `detail` is masked.
    case writeFailed(environment: String, detail: String)
    /// The worker refused a write because it is locked, without making an AWS call.
    /// The shell gates the affordance too, so this is the backstop made visible.
    case writeRefused(environment: String)
}
