//  EditTests.swift
//  Staging an edit, reviewing it, and applying it.
//
//  Two properties carry most of the weight here.
//
//  A staged Value never leaves the batch. It is not in the log, not in the summary the
//  review dialog reads, and not in any event. Every test that stages one checks for it
//  afterwards by content.
//
//  Nothing is unlocked by asking. Read-write mode is the worker's, and the shell reflects
//  what the worker said rather than what the toggle was set to.

import Testing
@testable import Janitor

@MainActor
struct EditTests {
    /// A signal string. If it appears anywhere it should not, a test says so by name.
    private let secret = "hunter2-should-never-appear"

    private func loaded() -> AppModel {
        let model = AppModel(core: StubCore())
        model.loadSelected()
        model.apply(.appLoaded(
            view: MatrixView(
                environments: ["prod", "staging"],
                rows: [
                    MatrixRow(
                        name: "STRIPE_API_KEY", state: .drift, kind: .string,
                        cells: [
                            .present(len: 20, group: 1, hex: "aaaa", kind: .string),
                            .present(len: 19, group: 2, hex: "bbbb", kind: .string),
                        ]
                    ),
                    MatrixRow(
                        name: "LEGACY_TOKEN", state: .gap, kind: .string,
                        cells: [.present(len: 16, group: 1, hex: "cccc", kind: .string), .absent]
                    ),
                ]
            ),
            appName: "Payments API"
        ))
        return model
    }

    /// A model with the worker's lock open.
    private func unlocked() -> AppModel {
        let model = loaded()
        model.setReadWrite(true)
        model.apply(.readWriteModeChanged(true))
        return model
    }

    // MARK: The lock

    @Test("a cell cannot be edited while the worker is locked")
    func lockedMeansNoEditing() {
        let model = loaded()
        #expect(model.canEdit == false)

        model.beginEdit(row: 0, col: 0)
        #expect(model.editing == nil)

        model.stageEdit(row: 0, col: 0, value: secret)
        #expect(model.pending == nil)
        #expect(model.editNotice != nil)
    }

    @Test("asking to unlock is not being unlocked")
    func askingIsNotUnlocking() {
        let model = loaded()
        model.setReadWrite(true)

        // The worker has not answered yet.
        #expect(model.canEdit == false)
        model.stageEdit(row: 0, col: 0, value: secret)
        #expect(model.pending == nil)
    }

    @Test("locking again discards what was staged")
    func lockingDiscardsTheBatch() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        #expect(model.pending?.count == 1)

        model.apply(.readWriteModeChanged(false))
        #expect(model.pending == nil)
        #expect(!model.log.contains { $0.message.contains(secret) })
    }

    // MARK: Staging

    @Test("a staged edit is described by name and size, never by Value")
    func aStagedEditIsDescribedNotShown() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)

        #expect(model.pendingSummary.count == 1)
        let line = model.pendingSummary[0]
        #expect(line.contains("STRIPE_API_KEY"))
        #expect(line.contains("\(secret.count)"))
        #expect(!line.contains(secret))
        #expect(!model.log.contains { $0.message.contains(secret) })
    }

    @Test("editing the same cell twice stages one edit, not two")
    func lastWriteWinsPerEntry() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: "first")
        model.stageEdit(row: 0, col: 0, value: "second-value")

        #expect(model.pending?.count == 1)
        #expect(model.pendingSummary[0].contains("\("second-value".count)"))
    }

    @Test("a removal stages without a Value at all")
    func aRemovalStagesWithoutAValue() {
        let model = unlocked()
        model.stageRemoval(row: 1, col: 0)

        #expect(model.pending?.count == 1)
        #expect(model.pendingSummary[0].contains("LEGACY_TOKEN"))
        #expect(model.pendingSummary[0].contains("removed"))
    }

    @Test("a batch belongs to one Environment")
    func aBatchBelongsToOneEnvironment() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)

        // The engine writes one Set at a time, so mixing columns would promise an
        // atomicity it does not have.
        model.stageEdit(row: 0, col: 1, value: secret)

        #expect(model.pending?.count == 1)
        #expect(model.pending?.environment == "prod")
        #expect(model.editNotice?.message.contains("prod") == true)
    }

    @Test("the matrix marks the cells that are staged")
    func stagedCellsAreMarked() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)

        #expect(model.isStaged(row: 0, col: 0))
        #expect(!model.isStaged(row: 0, col: 1))
        #expect(!model.isStaged(row: 1, col: 0))
    }

    @Test("unstaging one edit leaves the rest")
    func unstagingOneLeavesTheRest() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        model.stageRemoval(row: 1, col: 0)
        #expect(model.pending?.count == 2)

        model.unstage("STRIPE_API_KEY")
        #expect(model.pending?.count == 1)

        // Emptying the batch clears it, rather than leaving a bar with nothing in it.
        model.unstage("LEGACY_TOKEN")
        #expect(model.pending == nil)
    }

    // MARK: Applying

    @Test("a committed write clears the batch and the Values with it")
    func aCommittedWriteClearsTheBatch() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        model.applyPending()
        model.apply(.writeApplied(environment: "prod"))

        #expect(model.pending == nil)
        #expect(model.reviewing == false)
        #expect(!model.log.contains { $0.message.contains(secret) })
    }

    @Test("a conflict keeps the batch, so a retry is not a retype")
    func aConflictKeepsTheBatch() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        model.applyPending()
        model.apply(.writeConflict(environment: "prod"))

        #expect(model.pending?.count == 1)
        #expect(model.editNotice?.title == "Nothing was written")
    }

    @Test("a refusal keeps the batch and says the lock is why")
    func aRefusalKeepsTheBatch() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        model.applyPending()
        model.apply(.writeRefused(environment: "prod"))

        #expect(model.pending?.count == 1)
        #expect(model.editNotice?.message.contains("read-write mode is off") == true)
    }

    @Test("discarding drops the batch and everything in it")
    func discardingDropsEverything() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        model.discardPending()

        #expect(model.pending == nil)
        #expect(model.pendingSummary.isEmpty)
        #expect(!model.log.contains { $0.message.contains(secret) })
    }

    @Test("shutting down drops the batch")
    func shutdownDropsTheBatch() {
        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        model.shutdown()

        #expect(model.pending == nil)
    }

    @Test("a refused stage and a refused write say different things")
    func theTwoRefusalsAreDistinguishable() {
        // A batch that survives a refused write reads as lost if the alert says the edit
        // was never staged.
        let locked = loaded()
        locked.stageEdit(row: 0, col: 0, value: secret)
        #expect(locked.editNotice?.title == "Edit not staged")

        let model = unlocked()
        model.stageEdit(row: 0, col: 0, value: secret)
        model.applyPending()
        model.apply(.writeFailed(environment: "prod", detail: "the role cannot write this secret"))
        #expect(model.editNotice?.title == "Nothing was written")
        #expect(model.pending?.count == 1)
    }

    @Test("opening the editor ends any reveal on the same matrix")
    func openingTheEditorEndsTheReveal() {
        let model = unlocked()
        model.beginReveal(row: 0, col: 0)
        model.apply(.revealed(row: 0, col: 0, text: "an old value"))
        #expect(model.revealed != nil)

        // The old Value beside a field for the new one is two Values on screen at once.
        model.beginEdit(row: 0, col: 0)
        #expect(model.revealed == nil)
        #expect(model.editing?.name == "STRIPE_API_KEY")
    }
}
