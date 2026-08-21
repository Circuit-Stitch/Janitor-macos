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

    /// The canned Config, seeded once and then mutated the way the real one is. The
    /// Manage and Settings windows write through the seam, so it has to be a value that
    /// changes rather than a constant.
    private var config = StubConfig.seed

    /// The walk in flight, if any. One at a time, like the real orchestrator.
    private var walk: Walk?

    /// The worker's read-write lock. It lives here, not in the view, because refusing a
    /// write is the worker's job.
    private var readWrite = false

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
            guard let app = lock.withLock({ config.applications[safe: index] }) else { return }
            emit(.appLoading)
            after(0.5) { [self] in
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
            lock.withLock { readWrite = on }
            emit(.readWriteModeChanged(on))

        case .beginDiscovery(let method, let environment, let region):
            let name = environment.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            lock.withLock {
                walk = Walk(method: method, environment: name, region: region, chosen: [])
            }
            if method == .ssmDotenv {
                // The advisory a real SSM read surfaces when the org archives every
                // session. It is masked operator guidance, never a Value.
                emit(.warning("session logging is on for this org — this read is archived to S3"))
            }
            after(0.3) { [self] in step() }

        case .advanceDiscovery(let choice):
            lock.withLock { walk?.chosen.append("choice-\(choice)") }
            after(0.3) { [self] in step() }

        case .provideInput(let text):
            lock.withLock { walk?.chosen.append(text) }
            after(0.3) { [self] in step() }

        case .applyEdits(let environment, let edits):
            // The lock is the worker's, not the view's. Refuse before pretending to
            // reach AWS, which is the whole point of holding it here.
            guard lock.withLock({ readWrite }) else {
                emit(.writeRefused(environment: environment))
                return
            }
            after(0.4) { [self] in
                // One canned conflict, so the non-stomping path is reachable from the
                // UI: editing an Entry whose name starts with `LEGACY_` never commits.
                if edits.contains(where: { $0.key.hasPrefix("LEGACY_") }) {
                    emit(.writeConflict(environment: environment))
                } else {
                    emit(.writeApplied(environment: environment))
                }
            }

        case .shutdown:
            continuation.finish()
        }
    }

    /// Advance the scripted walk one step. The real orchestrator collapses a
    /// single-choice step and stops at the first question; this one always asks, so
    /// every wizard state is reachable from a running app.
    private func step() {
        let walk = lock.withLock { self.walk }
        guard let walk else { return }

        switch (walk.method, walk.chosen.count) {
        case (_, 0):
            emit(.discoveryChoice(
                what: .accounts, labels: Self.accounts, defaultIndex: 0
            ))
        case (_, 1):
            emit(.discoveryChoice(
                what: .roles, labels: Self.roles, defaultIndex: 0
            ))
        case (.secretsManager, 2):
            emit(.discoveryChoice(
                what: .secrets, labels: Self.secrets, defaultIndex: nil
            ))
        case (.ssmDotenv, 2):
            emit(.discoveryChoice(
                what: .instances, labels: Self.instances, defaultIndex: 0
            ))
        case (.ssmDotenv, 3):
            emit(.discoveryInput(
                what: .filePath,
                prompt: "Path to the .env file on the instance:",
                defaultText: "/opt/app/.env"
            ))
        default:
            finish(walk)
        }
    }

    /// End the walk with the Mapping it assembled. Where it lands is the shell's
    /// decision, so this only hands it over.
    private func finish(_ walk: Walk) {
        lock.withLock { self.walk = nil }
        emit(.envDiscovered(mapping: Mapping(
            environment: walk.environment,
            accountId: "1234567890" + String(format: "%02d", walk.chosen.count),
            region: walk.region,
            secretId: walk.method == .secretsManager
                ? "arn:aws:secretsmanager:\(walk.region):123456789012:secret:\(walk.environment)/app"
                : "i-0abc1234def567890:" + (walk.chosen.last ?? "/opt/app/.env"),
            permissionSet: "ReadOnly",
            method: walk.method
        )))
    }

    private func emit(_ event: JanitorEvent) {
        continuation.yield(event)
    }

    private func after(_ seconds: Double, _ body: @escaping @Sendable () -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: body)
    }

    /// The fabricated plaintext behind one cell, or nil when the cell is absent.
    private func value(row: Int, col: Int) -> String? {
        let app = lock.withLock { loadedIndex.flatMap { config.applications[safe: $0] } }
        guard let app else { return nil }
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

    // MARK: Config

    // The real core reads and writes a TOML file here. The stub keeps the same shape in
    // memory, including the two refusals that are core rules rather than view rules: a
    // blank name and a duplicate Environment.

    func applications() -> [(name: String, environmentCount: Int)] {
        lock.withLock { config.applications.map { ($0.name, $0.environments.count) } }
    }

    func environments(of application: Int) -> [Mapping] {
        lock.withLock { config.applications[safe: application]?.environments ?? [] }
    }

    @discardableResult
    func addApplication(name: String) -> Int? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return lock.withLock {
            config.applications.append(StubApp(name: name, view: MatrixView()))
            return config.applications.count - 1
        }
    }

    func removeApplication(_ index: Int) {
        lock.withLock {
            guard config.applications.indices.contains(index) else { return }
            config.applications.remove(at: index)
        }
    }

    @discardableResult
    func renameApplication(_ index: Int, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        return lock.withLock {
            guard config.applications.indices.contains(index) else { return false }
            config.applications[index].name = name
            return true
        }
    }

    @discardableResult
    func addEnvironment(application: Int, mapping: Mapping) -> Bool {
        lock.withLock {
            guard config.applications.indices.contains(application) else { return false }
            guard !config.applications[application].environments
                .contains(where: { $0.environment == mapping.environment })
            else { return false }
            config.applications[application].environments.append(mapping)
            config.applications[application].view.environments.append(mapping.environment)
            return true
        }
    }

    func removeEnvironment(application: Int, index: Int) {
        lock.withLock {
            guard config.applications.indices.contains(application) else { return }
            guard config.applications[application].environments.indices.contains(index) else {
                return
            }
            config.applications[application].environments.remove(at: index)
            if config.applications[application].view.environments.indices.contains(index) {
                config.applications[application].view.environments.remove(at: index)
            }
        }
    }

    func regionChoices() -> [String] {
        let config = lock.withLock { self.config }
        var choices = Self.knownRegions
        func offer(_ region: String) {
            guard !region.isEmpty, !choices.contains(region) else { return }
            choices.append(region)
        }
        offer(config.ssoRegion)
        for app in config.applications {
            for mapping in app.environments { offer(mapping.region) }
        }
        return choices
    }

    func browseRegion() -> String {
        lock.withLock {
            config.secretRegion.isEmpty ? config.ssoRegion : config.secretRegion
        }
    }

    func setBrowseRegion(_ region: String) {
        lock.withLock { config.secretRegion = region }
    }

    func identityCenter() -> (startURL: String, region: String) {
        lock.withLock { (config.ssoStartURL, config.ssoRegion) }
    }

    func setIdentityCenter(startURL: String, region: String) {
        lock.withLock {
            config.ssoStartURL = startURL.trimmingCharacters(in: .whitespaces)
            config.ssoRegion = region.trimmingCharacters(in: .whitespaces)
        }
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

    func choicePrompt(_ what: What) -> String {
        switch what {
        case .accounts: "Choose an account:"
        case .roles: "Choose a role:"
        case .secrets: "Choose a secret:"
        case .instances: "Choose an instance:"
        // A path is asked for as free text, so this titles no picker. It is here to keep
        // the mapping total.
        case .filePath: "Choose a path:"
        }
    }

    func methodLabel(_ method: SecretMethod) -> String {
        switch method {
        case .secretsManager: "SM"
        case .ssmDotenv: "SSM"
        }
    }

    func methodName(_ method: SecretMethod) -> String {
        switch method {
        case .secretsManager: "Secrets Manager"
        case .ssmDotenv: "Remote .env over SSM"
        }
    }

    func summarizeEdits(_ edits: [EnvEdit]) -> [String] {
        edits.map { edit in
            switch edit {
            case .set(let key, let value): "\(key) → \(value.count) bytes"
            case .remove(let key): "\(key) → removed"
            }
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

// MARK: - The in-flight walk

extension StubCore {
    /// One guided walk. `chosen` accumulates the answers, and its length is what the
    /// script reads to decide the next question — the same shape the real orchestrator
    /// uses, minus the AWS calls between steps.
    struct Walk {
        var method: SecretMethod
        var environment: String
        var region: String
        var chosen: [String]
    }
}

// MARK: - Canned data

extension StubCore {
    struct StubApp {
        var name: String
        var environments: [Mapping] = []
        var view: MatrixView
        var failure: Failure?
    }

    /// The canned Config. It starts as the Applications the offline mock Provider seeds
    /// and is then edited through the seam, the way the real one is.
    struct StubConfig {
        var ssoStartURL: String
        var ssoRegion: String
        /// The browse region. Empty means "use the Identity Center region", which is
        /// what lets a single-region org never pick one.
        var secretRegion: String
        var applications: [StubApp]

        static let seed = StubConfig(
            ssoStartURL: "https://example.awsapps.com/start",
            ssoRegion: "us-east-1",
            secretRegion: "",
            applications: [
                StubApp(
                    name: "Payments API",
                    environments: mappings("payments", ["prod", "staging"], "us-east-1"),
                    view: paymentsView
                ),
                StubApp(
                    name: "Auth Service",
                    environments: mappings("auth", ["prod", "staging", "dev"], "us-west-2"),
                    view: fabricatedView(
                        service: "auth", environments: ["prod", "staging", "dev"]
                    )
                ),
                StubApp(
                    name: "Billing Worker",
                    environments: mappings("billing", ["prod", "staging"], "eu-west-1"),
                    view: fabricatedView(
                        service: "billing", environments: ["prod", "staging"]
                    )
                ),
                StubApp(
                    name: "Notifications",
                    environments: mappings("notify", ["prod", "staging", "dev"], "us-east-1"),
                    view: MatrixView(environments: ["prod", "staging", "dev"]),
                    failure: Failure(
                        environment: "dev",
                        detail: "the role is not assigned to this account"
                    )
                ),
            ]
        )
    }

    /// One Mapping per Environment, all in one region and all Secrets Manager. Enough
    /// for the Manage window to have rows to show.
    static func mappings(_ service: String, _ environments: [String], _ region: String)
        -> [Mapping]
    {
        environments.map { environment in
            Mapping(
                environment: environment,
                accountId: "123456789012",
                region: region,
                secretId: "arn:aws:secretsmanager:\(region):123456789012:secret:\(environment)/\(service)",
                permissionSet: "ReadOnly",
                method: .secretsManager
            )
        }
    }

    /// The regions the picker offers before any of the operator's own are unioned in.
    static let knownRegions = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2", "ca-central-1",
        "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-north-1",
        "eu-south-1", "ap-south-1", "ap-northeast-1", "ap-northeast-2",
        "ap-northeast-3", "ap-southeast-1", "ap-southeast-2", "sa-east-1",
    ]

    /// The presenter lines a walk offers at each list step. Account and role lines look
    /// the way the real ones do; none of them is a Value.
    static let accounts = [
        "Platform Production (123456789012)",
        "Platform Staging (210987654321)",
        "Sandbox (555555555555)",
    ]
    static let roles = ["ReadOnlySecrets", "SecretsAdmin"]
    static let secrets = ["prod/payments-api", "prod/payments-api-legacy"]
    static let instances = ["i-0abc1234def567890 — api-1", "i-0fed4321cba098765 — api-2"]

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

// MARK: - Bounds

extension Array {
    /// The element at `index`, or nil when it is out of range. Manage windows and
    /// pending loads both outlive the Application they name, so several reads here have
    /// to tolerate an index that no longer exists.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
