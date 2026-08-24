//  StubCore.swift
//  A scripted core, for the tests.
//
//  It answers commands with canned events on a timer, so the model and the views can be
//  driven without AWS, without a browser, and without a config file. The Values it
//  reveals are fabricated and obviously fake.
//
//  It is not a second implementation of anything. Config goes through an in-memory
//  `ConfigStore`, so every Config rule it enforces is the Rust one and nothing here can
//  write to disk. Every pure rule comes from CoreDefaults. What is left is the script:
//  which events a command produces, and in what order.
//
//  The shipping app runs on `JanitorKitCore`. This exists so a test can assert what the
//  shell does with an event, which needs the event to arrive on demand.

import Foundation
import JanitorKit

/// Canned events over a real Config store. Not the shipping implementation.
final class StubCore: JanitorCore, ConfigBacked, @unchecked Sendable {
    let events: AsyncStream<JanitorEvent>
    let store: ConfigStore
    var onConfigError: (@Sendable (String) -> Void)?

    private let continuation: AsyncStream<JanitorEvent>.Continuation

    private let lock = NSLock()
    private var loadedName: String?

    /// The walk in flight, if any. One at a time, like the real orchestrator.
    private var walk: Walk?

    /// The worker's read-write lock. It lives here, not in the view, because refusing a
    /// write is the worker's job.
    private var readWrite = false

    init() {
        var captured: AsyncStream<JanitorEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
        store = ConfigStore.inMemory(config: .stub)
    }

    // MARK: Commands

    func send(_ command: JanitorCommand) {
        switch command {
        case .signIn:
            emit(.signInStarted)
            after(0.4) { [self] in emit(.signedIn) }

        case .loadApp(let application):
            emit(.appLoading)
            after(0.5) { [self] in
                lock.withLock { loadedName = application.name }
                if let failure = Self.failures[application.name] {
                    emit(.appFailed(AppError(failures: [failure])))
                } else {
                    emit(.appLoaded(
                        view: Self.view(for: application),
                        corrected: [],
                        appName: application.name
                    ))
                }
            }

        case .reveal(let row, let col, _):
            after(0.05) { [self] in
                if let text = value(row: Int(row), col: Int(col)) {
                    emit(.revealed(row: row, col: col, text: text))
                } else {
                    emit(.revealUnavailable)
                }
            }

        case .copyValue(let row, let col, _):
            after(0.05) { [self] in
                if let text = value(row: Int(row), col: Int(col)) {
                    emit(.copyValue(row: row, col: col, text: text))
                } else {
                    emit(.copyUnavailable)
                }
            }

        case .setReadWrite(let on):
            lock.withLock { readWrite = on }
            emit(.readWriteModeChanged(on))

        case .beginDiscovery(let method, let environment, let region, _):
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

        case .applyEdits(let mapping, let edits):
            // The lock is the worker's, not the view's. Refuse before pretending to
            // reach AWS, which is the whole point of holding it here.
            guard lock.withLock({ readWrite }) else {
                emit(.writeRefused(environment: mapping.environment))
                return
            }
            after(0.4) { [self] in
                // One canned conflict, so the non-stomping path is reachable from the
                // UI: editing an Entry whose name starts with `LEGACY_` never commits.
                if edits.contains(where: { $0.key.hasPrefix("LEGACY_") }) {
                    emit(.writeConflict(environment: mapping.environment))
                } else {
                    emit(.writeApplied(environment: mapping.environment))
                }
            }

        case .shutdown:
            continuation.finish()

        // The script covers the ten commands the protocol has. One a newer JanitorKit
        // adds is ignored rather than answered wrongly.
        @unknown default:
            break
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
                what: .accounts, labels: Self.accounts, default: 0
            ))
        case (_, 1):
            emit(.discoveryChoice(
                what: .roles, labels: Self.roles, default: 0
            ))
        case (.secretsManager, 2):
            emit(.discoveryChoice(
                what: .secrets, labels: Self.secrets, default: nil
            ))
        case (.ssmDotenv, 2):
            emit(.discoveryChoice(
                what: .instances, labels: Self.instances, default: 0
            ))
        case (.ssmDotenv, 3):
            emit(.discoveryInput(
                what: .filePath,
                prompt: "Path to the .env file on the instance:",
                default: "/opt/app/.env"
            ))
        default:
            finish(walk)
        }
    }

    /// End the walk with the Mapping it assembled. Where it lands is the shell's
    /// decision, so this only hands it over.
    private func finish(_ walk: Walk) {
        lock.withLock { self.walk = nil }
        emit(.envDiscovered(Mapping(
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
        guard let name = lock.withLock({ loadedName }) else { return nil }
        guard let application = store.applications().first(where: { $0.name == name })
        else { return nil }
        let view = Self.view(for: application)
        guard row < view.rows.count, col < view.environments.count else { return nil }
        guard case .present(let len, let group, _, _) = view.rows[row].cells[col] else {
            return nil
        }
        return Self.fabricate(
            name: view.rows[row].name,
            environment: view.environments[col],
            group: group,
            len: Int(len)
        )
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

extension Config {
    /// The Config the fixture starts on. It is edited through the store the way the real
    /// one is, and the store is in-memory, so none of this reaches disk.
    static let stub = Config(
        ssoStartUrl: "https://example.awsapps.com/start",
        ssoRegion: "us-east-1",
        // Empty means "use the Identity Center region", which is what lets a
        // single-region org never pick one.
        secretRegion: "",
        browserCommand: nil,
        lastPick: nil,
        entryColumnWidth: nil,
        applications: [
            Application(name: "Payments API",
                        environments: StubCore.mappings("payments", ["prod", "staging"], "us-east-1")),
            Application(name: "Auth Service",
                        environments: StubCore.mappings("auth", ["prod", "staging", "dev"], "us-west-2")),
            Application(name: "Billing Worker",
                        environments: StubCore.mappings("billing", ["prod", "staging"], "eu-west-1")),
            Application(name: "Notifications",
                        environments: StubCore.mappings("notify", ["prod", "staging", "dev"], "us-east-1")),
        ]
    )
}

extension StubCore {
    /// The Applications that fail to load, by name. Notifications is the one, so the
    /// error pane and the banner are reachable from a running app.
    static let failures: [String: Failure] = [
        "Notifications": Failure(
            environment: "dev",
            reason: .accessDenied,
            detail: "the role is not assigned to this account"
        )
    ]

    /// The masked matrix one Application loads as. Payments API is hand-seeded so the
    /// three states and the prefix clusters are all present; everything else is
    /// fabricated from its Environments.
    static func view(for application: Application) -> MatrixView {
        let environments = application.environments.map(\.environment)
        if application.name == "Payments API" { return paymentsView }
        return fabricatedView(service: application.name, environments: environments)
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

    /// The deterministic fallback for an unseeded Set: one Aligned row, two Drift rows,
    /// and a prod-only Gap row.
    static func fabricatedView(service: String, environments: [String]) -> MatrixView {
        let n = environments.count
        guard n > 0 else { return MatrixView(environments: [], rows: []) }
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
            key: .entry(name),
            name: name,
            state: state,
            kind: kind,
            cells: cells.map {
                guard let c = $0 else { return .absent }
                return .present(
                    len: Usize(c.len), group: c.group, hex: hexTag(name, c.group), kind: kind
                )
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
