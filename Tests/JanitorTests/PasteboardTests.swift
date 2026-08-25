//  PasteboardTests.swift
//  What a copied Value carries, and when Janitor takes it back.
//
//  The markers are the whole defense against a clipboard manager recording a Value, so
//  they are asserted rather than assumed. Two of the three are community conventions and
//  one is undocumented, which means nothing outside this file tells us they landed.
//
//  Every test runs against a private pasteboard. The suite never touches the system one,
//  so it cannot wipe whatever the operator had copied before running it.

import AppKit
import Testing
@testable import Janitor

@MainActor
struct PasteboardTests {
    /// Point `Pasteboard` at a board of this test's own, then hand it back.
    private func onScratchBoard(_ name: String, _ body: (NSPasteboard) -> Void) {
        let board = NSPasteboard(name: NSPasteboard.Name("com.circuitstitch.apps.janitor.tests.\(name)"))
        Pasteboard.board = board
        defer {
            board.releaseGlobally()
            Pasteboard.board = .general
        }
        body(board)
    }

    @Test func aConcealedCopyCarriesTheValue() {
        onScratchBoard("value") { board in
            Pasteboard.copyConcealed("s3cret")
            #expect(board.string(forType: .string) == "s3cret")
        }
    }

    @Test func aConcealedCopyCarriesEveryMarker() {
        onScratchBoard("markers") { board in
            Pasteboard.copyConcealed("s3cret")
            let types = board.types ?? []
            for marker in Pasteboard.concealedMarkers {
                #expect(types.contains(marker), "missing \(marker.rawValue)")
            }
        }
    }

    @Test func aPlainCopyCarriesNoMarker() {
        onScratchBoard("plain") { board in
            Pasteboard.copyPlain("STRIPE_API_KEY")
            let types = board.types ?? []
            #expect(types.contains(.string))
            for marker in Pasteboard.concealedMarkers {
                #expect(!types.contains(marker), "unexpected \(marker.rawValue)")
            }
        }
    }

    @Test func clearingTakesBackAValueJanitorStillOwns() {
        onScratchBoard("clear-owned") { board in
            Pasteboard.copyConcealed("s3cret")
            Pasteboard.clearIfOwned()
            #expect(board.string(forType: .string) == nil)
        }
    }

    @Test func clearingLeavesSomethingCopiedSinceAlone() {
        onScratchBoard("clear-foreign") { board in
            Pasteboard.copyConcealed("s3cret")
            // Stand in for the operator copying something else while the timer runs.
            board.clearContents()
            board.setString("a grocery list", forType: .string)

            Pasteboard.clearIfOwned()
            #expect(board.string(forType: .string) == "a grocery list")
        }
    }

    @Test func clearingLeavesACopiedNameAlone() {
        onScratchBoard("clear-name") { board in
            Pasteboard.copyPlain("STRIPE_API_KEY")
            Pasteboard.clearIfOwned()
            #expect(board.string(forType: .string) == "STRIPE_API_KEY")
        }
    }

    @Test func aSecondCopyIsTheOneThatGetsCleared() {
        onScratchBoard("clear-latest") { board in
            Pasteboard.copyConcealed("first")
            Pasteboard.copyConcealed("second")
            Pasteboard.clearIfOwned()
            #expect(board.string(forType: .string) == nil)
        }
    }
}
