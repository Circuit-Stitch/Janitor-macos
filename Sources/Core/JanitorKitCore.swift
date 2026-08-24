//  JanitorKitCore.swift
//  JanitorCore over the real Rust core.
//
//  It owns two things from JanitorKit and adds nothing of its own:
//
//  * A `Worker`, which is the same worker thread the Slint shell drives in Rust.
//    Commands go in and events come out. The worker holds the Provider, the secrets, and
//    the read-write lock; none of that is here.
//  * A `ConfigStore`, which is the core's one copy of Config. Every Config call comes
//    from CoreDefaults, so this file does not implement one.
//
//  THE SINK IS NOT ON THE MAIN THREAD
//
//  The worker calls `onEvent` from its own thread. Nothing here touches view state: the
//  events go into an `AsyncStream` and the model — which is `@MainActor` — is what picks
//  them up. That hop is the whole reason the stream exists.

import Foundation
import JanitorKit

final class JanitorKitCore: JanitorCore, ConfigBacked, @unchecked Sendable {
    let events: AsyncStream<JanitorEvent>
    let store: ConfigStore

    /// Where a Config write's failure goes. The composition root points this at the
    /// Diagnostic Log, so a failed save is visible rather than silent.
    var onConfigError: (@Sendable (String) -> Void)?

    private let worker: Worker

    /// Build the core over a Provider and a Config store.
    ///
    /// `kind` is `.aws` for the real thing and `.mock` for the offline matrix. Nothing
    /// touches AWS until a `signIn` or a `loadApp`, so constructing this opens no
    /// browser and makes no call.
    init(kind: ProviderKind, store: ConfigStore) {
        self.store = store

        var send: (@Sendable (JanitorEvent) -> Void)!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            send = { continuation.yield($0) }
        }
        self.worker = Worker.start(kind: kind, config: store.snapshot(), sink: Sink(send: send))
    }

    /// The core the app runs on. `JANITOR_MOCK=1` swaps the Provider for the offline one
    /// and holds Config in memory, so a demo run makes no AWS call and cannot edit a real
    /// operator's Applications.
    static func launch() -> JanitorKitCore {
        if ProcessInfo.processInfo.environment["JANITOR_MOCK"] == "1" {
            return JanitorKitCore(kind: .mock, store: ConfigStore.inMemory(config: .mock))
        }
        do {
            return JanitorKitCore(kind: .aws, store: try ConfigStore.load())
        } catch {
            // An unreadable config is not a reason to refuse to start. The shell comes up
            // on an empty one and the Settings window is how it gets filled in. The store
            // is in-memory, so a launch that could not read the file cannot overwrite it
            // either.
            let core = JanitorKitCore(kind: .aws, store: ConfigStore.inMemory(config: .empty))
            let reason = error.localizedDescription
            DispatchQueue.main.async { [weak core] in
                core?.onConfigError?("config could not be read — \(reason)")
            }
            return core
        }
    }

    func send(_ command: JanitorCommand) {
        worker.send(command: command)
    }

    /// The worker's event sink. It forwards and does nothing else, because it runs on
    /// the worker's thread.
    ///
    /// A class, because the Rust side holds it as a reference across the boundary and
    /// `EventSink` is class-bound for that reason.
    private final class Sink: EventSink, @unchecked Sendable {
        private let send: @Sendable (JanitorEvent) -> Void
        init(send: @escaping @Sendable (JanitorEvent) -> Void) { self.send = send }
        func onEvent(event: JanitorEvent) throws { send(event) }
    }
}

extension Config {
    /// Nothing configured, for a launch that could not read a config file.
    static let empty = Config(
        ssoStartUrl: "", ssoRegion: "", secretRegion: "", browserCommand: nil,
        lastPick: nil, entryColumnWidth: nil, applications: []
    )

    /// The Applications the offline run compares. The mock Provider invents the Secret
    /// Sets behind them; these are the locations alone, and they never reach disk.
    static let mock = Config(
        ssoStartUrl: "https://example.awsapps.com/start",
        ssoRegion: "us-east-1",
        secretRegion: "",
        browserCommand: nil,
        lastPick: nil,
        entryColumnWidth: nil,
        applications: [
            Application(name: "Payments API", environments: mockMappings(
                "payments", ["prod", "staging"], "us-east-1")),
            Application(name: "Auth Service", environments: mockMappings(
                "auth", ["prod", "staging", "dev"], "us-west-2")),
            Application(name: "Billing Worker", environments: mockMappings(
                "billing", ["prod", "staging"], "eu-west-1")),
        ]
    )
}

/// One Mapping per Environment, all in one region and all Secrets Manager.
private func mockMappings(
    _ service: String, _ environments: [String], _ region: String
) -> [Mapping] {
    environments.map { environment in
        Mapping(
            environment: environment,
            accountId: "123456789012",
            region: region,
            secretId:
                "arn:aws:secretsmanager:\(region):123456789012:secret:\(environment)/\(service)",
            permissionSet: "ReadOnly",
            method: .secretsManager
        )
    }
}
