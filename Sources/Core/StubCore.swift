//  StubCore.swift
//  A stand-in for the Rust core, so the views can be built and tested before the
//  xcframework exists.
//
//  It serves the same canned Applications the offline mock Provider serves, and it
//  answers the pure rules the same way the Rust seams do. It makes no network call and
//  holds no real secret material — the Values below are fabricated.
//
//  This file is temporary. `JanitorKitCore` replaces it once the xcframework is
//  published, and what survives is this file as a test fixture. The rule copies here
//  are the reason it is temporary: prefix clustering, the name split, and the drift
//  badge are tested in Rust, and having a second copy of them is exactly what the shell
//  must not ship.

import Foundation

/// Canned data plus local copies of the pure rules. Not the shipping implementation.
final class StubCore: JanitorCore, @unchecked Sendable {
    let events: AsyncStream<JanitorEvent>
    private let continuation: AsyncStream<JanitorEvent>.Continuation

    private let lock = NSLock()
    private var loadedIndex: Int?

    init() {
        var captured: AsyncStream<JanitorEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
    }

    // MARK: Commands

    func send(_ command: JanitorCommand) {
        switch command {
        case .signIn:
            emit(.signInStarted)
            after(0.4) { [self] in
                emit(.signedIn(identity: "mock@example.com / ReadOnly"))
            }

        case .loadApp(let index):
            guard index >= 0, index < Self.applications.count else { return }
            emit(.appLoading)
            after(0.5) { [self] in
                let app = Self.applications[index]
                lock.withLock { loadedIndex = index }
                if let failure = app.failure {
                    emit(.appFailed(failures: [failure]))
                } else {
                    emit(.appLoaded(view: app.view, appName: app.name))
                }
            }

        case .reveal(let row, let col):
            after(0.05) { [self] in
                if let text = value(row: row, col: col) {
                    emit(.revealed(row: row, col: col, text: text))
                } else {
                    emit(.revealUnavailable)
                }
            }

        case .endReveal:
            break

        case .copyValue(let row, let col):
            after(0.05) { [self] in
                if let text = value(row: row, col: col) {
                    emit(.copyValue(row: row, col: col, text: text))
                } else {
                    emit(.copyUnavailable)
                }
            }

        case .setReadWrite(let on):
            emit(.readWriteModeChanged(on))

        case .shutdown:
            continuation.finish()
        }
    }

    func applications() -> [(name: String, environmentCount: Int)] {
        Self.applications.map { ($0.name, $0.view.environments.count) }
    }

    private func emit(_ event: JanitorEvent) {
        continuation.yield(event)
    }

    private func after(_ seconds: Double, _ body: @escaping @Sendable () -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: body)
    }

    /// The fabricated plaintext behind one cell, or nil when the cell is absent.
    private func value(row: Int, col: Int) -> String? {
        let index = lock.withLock { loadedIndex }
        guard let index, index < Self.applications.count else { return nil }
        let app = Self.applications[index]
        guard row < app.view.rows.count, col < app.view.environments.count else { return nil }
        guard case .present(let len, let group, _, _) = app.view.rows[row].cells[col] else {
            return nil
        }
        return Self.fabricate(
            name: app.view.rows[row].name,
            environment: app.view.environments[col],
            group: group,
            len: len
        )
    }

    // MARK: Pure rules

    func matrixItems(names: [String], grouped: Bool) -> [MatrixItem] {
        guard grouped else {
            return names.indices.map { .row(index: $0, zebra: $0 % 2 == 1, groupLabel: nil) }
        }
        var items: [MatrixItem] = []
        var stripe = 0
        for cluster in Self.clusters(names) {
            if let label = cluster.label {
                items.append(.header(label: label, count: cluster.members.count))
                stripe = 0
            }
            for index in cluster.members {
                items.append(.row(index: index, zebra: stripe % 2 == 1, groupLabel: cluster.label))
                stripe += 1
            }
        }
        return items
    }

    func displayNameParts(groupLabel: String?, name: String) -> NameParts {
        var relative = name
        if let groupLabel, groupLabel.hasSuffix("*") {
            let prefix = String(groupLabel.dropLast())
            if name.hasPrefix(prefix) { relative = String(name.dropFirst(prefix.count)) }
        }
        if relative.isEmpty { relative = name }
        guard let cut = relative.lastIndex(where: { $0 == "." || $0 == "_" }) else {
            return NameParts(prefix: "", leaf: relative)
        }
        let after = relative.index(after: cut)
        return NameParts(
            prefix: String(relative[relative.startIndex...cut]),
            leaf: String(relative[after...])
        )
    }

    func badgeLabel(kind: LeafKind?) -> String {
        switch kind {
        case .string: "STRING"
        case .number: "NUMBER"
        case .bool: "BOOL"
        case .null: "NULL"
        case .json: "JSON"
        case nil: ""
        }
    }

    func stateGlyph(_ state: EntryState) -> String {
        switch state {
        case .aligned: "="
        case .drift: "≠"
        case .gap: "∅"
        }
    }

    func driftBadge(isSelected: Bool, status: LoadStatus, view: MatrixView) -> String {
        guard isSelected, status == .loaded else { return "" }
        let n = view.rows.filter { $0.state == .drift }.count
        return n > 0 ? "\(n) drift" : ""
    }

    func errorBanner(_ failures: [Failure]) -> String {
        failures.map { "\($0.environment): \($0.detail)" }.joined(separator: "; ")
    }

    func mainPane(status: LoadStatus, hasApplications: Bool) -> MainPane {
        switch status {
        case .loaded: hasApplications ? .matrix : .emptyApps
        case .signingIn: .signing
        case .loading: .loading
        case .failed: .error
        case .idle: .signIn
        }
    }

    func paneTitle(_ pane: MainPane) -> String {
        switch pane {
        case .matrix: "Drift matrix"
        case .emptyApps: "No Applications"
        case .loading: "Loading…"
        case .signing: "Signing in…"
        case .signIn, .error: "Not signed in"
        }
    }

    func paneBody(_ pane: MainPane, statusMessage: String?) -> String {
        switch pane {
        case .signIn:
            "Sign in to Identity Center in your browser to read a Secret Set."
        case .signing:
            "Finish signing in the browser window that opened."
        case .loading:
            "Reading each Environment's Secret Set."
        case .error:
            statusMessage ?? "The load failed. Sign in again and retry."
        case .matrix, .emptyApps:
            ""
        }
    }
}

// MARK: - Prefix clustering

extension StubCore {
    struct Cluster {
        var label: String?
        var members: [Int]
    }

    /// Group names that share their first segment. A group of two or more gets a header
    /// labeled with the longest prefix common to its members, cut at the last separator
    /// and followed by `*`. A name that shares its first segment with nothing else is
    /// returned alone and renders flat.
    static func clusters(_ names: [String]) -> [Cluster] {
        var keys: [String] = []
        var groups: [[Int]] = []
        for (i, name) in names.enumerated() {
            let key = firstSegment(name)
            if let g = keys.firstIndex(of: key) {
                groups[g].append(i)
            } else {
                keys.append(key)
                groups.append([i])
            }
        }
        return groups.map { members in
            guard members.count >= 2 else { return Cluster(label: nil, members: members) }
            return Cluster(label: groupLabel(members.map { names[$0] }), members: members)
        }
    }

    static func firstSegment(_ name: String) -> String {
        guard let i = name.firstIndex(where: { $0 == "." || $0 == "_" }) else { return name }
        return String(name[name.startIndex..<i])
    }

    static func groupLabel(_ members: [String]) -> String {
        let lcp = longestCommonPrefix(members)
        guard let cut = lcp.lastIndex(where: { $0 == "." || $0 == "_" }) else { return lcp + "*" }
        return String(lcp[lcp.startIndex...cut]) + "*"
    }

    static func longestCommonPrefix(_ members: [String]) -> String {
        guard var prefix = members.first else { return "" }
        for member in members.dropFirst() {
            var end = prefix.startIndex
            var a = prefix.startIndex
            var b = member.startIndex
            while a < prefix.endIndex, b < member.endIndex, prefix[a] == member[b] {
                a = prefix.index(after: a)
                b = member.index(after: b)
                end = a
            }
            prefix = String(prefix[prefix.startIndex..<end])
        }
        return prefix
    }
}

// MARK: - Canned data

extension StubCore {
    struct StubApp {
        var name: String
        var view: MatrixView
        var failure: Failure?
    }

    /// The same Applications the offline mock Provider seeds.
    static let applications: [StubApp] = [
        StubApp(name: "Payments API", view: paymentsView),
        StubApp(name: "Auth Service", view: fabricatedView(
            service: "auth", environments: ["prod", "staging", "dev"]
        )),
        StubApp(name: "Billing Worker", view: fabricatedView(
            service: "billing", environments: ["prod", "staging"]
        )),
        StubApp(
            name: "Notifications",
            view: MatrixView(environments: ["prod", "staging", "dev"]),
            failure: Failure(
                environment: "dev",
                detail: "the role is not assigned to this account"
            )
        ),
    ]

    /// The hand-seeded Payments API matrix. `GITHUB_APP_ID` is identical everywhere,
    /// `database.replica.url` and `GITHUB_APP_WEBHOOK_SECRET` exist only in prod, and
    /// the rest differ.
    static let paymentsView = MatrixView(
        environments: ["prod", "staging"],
        rows: [
            row("GITHUB_APP_ID", .string, [cell(6, 1), cell(6, 1)]),
            row("GITHUB_APP_PRIVATE_KEY", .string, [cell(69, 1), cell(72, 2)]),
            row("GITHUB_APP_WEBHOOK_SECRET", .string, [cell(18, 1), nil]),
            row("STRIPE_API_KEY", .string, [cell(20, 1), cell(19, 2)]),
            row("STRIPE_WEBHOOK_SECRET", .string, [cell(22, 1), cell(24, 2)]),
            row("database.pool.max", .number, [cell(3, 1), cell(2, 2)]),
            row("database.primary.password", .string, [cell(14, 1), cell(13, 2)]),
            row("database.primary.url", .string, [cell(45, 1), cell(48, 2)]),
            row("database.replica.url", .string, [cell(49, 1), nil]),
        ]
    )

    /// The deterministic fallback the mock fabricates for an unseeded Set: one Aligned
    /// row, two Drift rows, and a prod-only Gap row.
    static func fabricatedView(service: String, environments: [String]) -> MatrixView {
        let n = environments.count
        return MatrixView(
            environments: environments,
            rows: [
                row("API_KEY", .string, (0..<n).map { cell(16, UInt32($0 + 1)) }),
                row("DATABASE_URL", .string, (0..<n).map { cell(30 + $0, UInt32($0 + 1)) }),
                row("LEGACY_TOKEN", .string, [cell(16, 1)] + Array(repeating: nil, count: n - 1)),
                row("SERVICE_NAME", .string, Array(repeating: cell(service.count, 1), count: n)),
            ]
        )
    }

    /// Build a row and derive its state from its cells, the way the engine does: any
    /// absent cell is a Gap, more than one equality group is Drift, everything else is
    /// Aligned.
    static func row(_ name: String, _ kind: LeafKind, _ cells: [(len: Int, group: UInt32)?])
        -> MatrixRow
    {
        let state: EntryState =
            cells.contains(where: { $0 == nil })
            ? .gap
            : (Set(cells.compactMap { $0?.group }).count > 1 ? .drift : .aligned)
        return MatrixRow(
            name: name,
            state: state,
            kind: kind,
            cells: cells.map {
                guard let c = $0 else { return .absent }
                return .present(len: c.len, group: c.group, hex: hexTag(name, c.group), kind: kind)
            }
        )
    }

    static func cell(_ len: Int, _ group: UInt32) -> (len: Int, group: UInt32) { (len, group) }

    /// The same cosmetic four-character tag the engine derives from the Entry name and
    /// the equality group. Never derived from a Value.
    static func hexTag(_ name: String, _ group: UInt32) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in Array(name.utf8) + [UInt8(ascii: ":")] + withUnsafeBytes(
            of: group.littleEndian, Array.init
        ) {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(format: "%04x", h & 0xffff)
    }

    /// Fabricated plaintext for a reveal. Deterministic, so the same cell always shows
    /// the same text, and obviously fake.
    static func fabricate(name: String, environment: String, group: UInt32, len: Int) -> String {
        let seed = hexTag("\(name)@\(environment)", group)
        let body = String(repeating: seed, count: max(1, len / seed.count + 1))
        return String(body.prefix(max(1, len)))
    }
}
