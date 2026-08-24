//  JanitorKitCoreTests.swift
//  The real core, driven end to end.
//
//  Every other test in this bundle drives StubCore, which scripts events. This one drives
//  the Rust worker inside JanitorKit: a command crosses the FFI, the worker runs the mock
//  Provider, the comparison engine builds the matrix, and the events come back over the
//  sink. If the xcframework and the shell disagree about a shape, this is where it shows.
//
//  The Provider is the offline one and the store is in memory, so nothing here signs in,
//  reaches AWS, or writes a config file.

import Foundation
import JanitorKit
import Testing

@testable import Janitor

struct JanitorKitCoreTests {
    private func core() -> JanitorKitCore {
        JanitorKitCore(kind: .mock, store: ConfigStore.inMemory(config: .mock))
    }

    /// Collect events until `isDone` accepts one, or give up. The worker answers on its
    /// own thread, so a test that waited on a fixed sleep would be flaky in one direction
    /// and slow in the other.
    private func drain(
        _ core: JanitorKitCore,
        until isDone: @escaping @Sendable (JanitorEvent) -> Bool
    ) async throws -> [JanitorEvent] {
        try await withThrowingTaskGroup(of: [JanitorEvent].self) { group in
            group.addTask {
                var seen: [JanitorEvent] = []
                for await event in core.events {
                    seen.append(event)
                    if isDone(event) { return seen }
                }
                return seen
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw CoreTimeout()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private struct CoreTimeout: Error {}

    @Test("the real worker builds a masked matrix from the mock Provider")
    func theWorkerBuildsAMatrix() async throws {
        let core = core()
        let application = core.applications()[0]

        core.send(.signIn)
        core.send(.loadApp(application))
        let events = try await drain(core) { if case .appLoaded = $0 { true } else { false } }
        core.send(.shutdown)

        guard case .appLoaded(let view, _, let name)? = events.last else {
            Issue.record("the worker never loaded an Application: \(events)")
            return
        }
        #expect(name == application.name)
        #expect(view.environments == application.environments.map(\.environment))
        #expect(!view.rows.isEmpty)

        // Masked, and structurally unable to be otherwise: a present cell carries a byte
        // length and an equality group, and no Value crosses until a reveal asks for one.
        for row in view.rows {
            #expect(row.cells.count == view.environments.count)
            for cell in row.cells where !isAbsent(cell) {
                guard case .present(let len, _, let hex, _) = cell else { continue }
                #expect(len > 0)
                #expect(hex.count == 4)
            }
        }
    }

    @Test("a reveal returns one cell's plaintext and nothing else")
    func aRevealReturnsOneValue() async throws {
        let core = core()
        let application = core.applications()[0]

        core.send(.loadApp(application))
        let loaded = try await drain(core) { if case .appLoaded = $0 { true } else { false } }
        guard case .appLoaded(let view, _, _)? = loaded.last else {
            Issue.record("the worker never loaded an Application")
            return
        }
        guard let (row, col) = firstPresent(view) else {
            Issue.record("the mock matrix has no present cell to reveal")
            return
        }

        core.send(.reveal(row: Usize(row), col: Usize(col), key: view.rows[row].key))
        let revealed = try await drain(core) {
            if case .revealed = $0 { true } else if case .revealUnavailable = $0 { true }
            else { false }
        }
        core.send(.shutdown)

        guard case .revealed(let gotRow, let gotCol, let text)? = revealed.last else {
            Issue.record("the reveal did not come back: \(revealed)")
            return
        }
        #expect(Int(gotRow) == row)
        #expect(Int(gotCol) == col)
        #expect(!text.isEmpty)

        // The un-mask-exactly-one rule is Rust's, and this is the shell asking it.
        #expect(isRevealed(revealedRow: Int32(row), revealedCol: Int32(col),
                           row: Int32(row), col: Int32(col)))
        #expect(!isRevealed(revealedRow: Int32(row), revealedCol: Int32(col),
                            row: Int32(row), col: Int32(col) + 1))
    }

    @Test("the worker refuses a write while it is locked, and says so")
    func aLockedWorkerRefusesAWrite() async throws {
        let core = core()
        let mapping = core.applications()[0].environments[0]

        // Read-write mode starts off every launch and is never persisted, so no setup is
        // needed to be locked.
        core.send(.applyEdits(mapping: mapping, edits: [.set(key: "A", value: "1")]))
        let events = try await drain(core) {
            if case .writeRefused = $0 { true } else { false }
        }
        core.send(.shutdown)

        guard case .writeRefused(let environment)? = events.last else {
            Issue.record("a locked worker did not refuse the write: \(events)")
            return
        }
        #expect(environment == mapping.environment)
    }

    private func isAbsent(_ cell: MatrixCell) -> Bool {
        if case .absent = cell { return true }
        return false
    }

    private func firstPresent(_ view: MatrixView) -> (row: Int, col: Int)? {
        for (r, row) in view.rows.enumerated() {
            for (c, cell) in row.cells.enumerated() where !isAbsent(cell) {
                return (r, c)
            }
        }
        return nil
    }
}
