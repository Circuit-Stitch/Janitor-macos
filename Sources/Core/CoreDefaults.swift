//  CoreDefaults.swift
//  Where JanitorCore reaches JanitorKit, for every implementation at once.
//
//  Two kinds of call live here, and neither one decides anything.
//
//  The pure rules are free functions in the kit. They need no worker, no Config, and no
//  state, so they are default implementations on the protocol itself and nothing can
//  override them by accident.
//
//  The Config calls need a `ConfigStore`, which is the core's one copy of Config. Any
//  implementation that has one gets all of them, so the shipping core and the test
//  fixture read and write Config through exactly the same rules — the blank-name
//  refusal, the duplicate-Environment refusal, the column-width floor. The fixture holds
//  an in-memory store, so a test run cannot reach a real operator's config file.
//
//  This file is the reason there is one answer to every rule. Before it, the test
//  fixture carried its own copy of prefix clustering, the name split, the drift badge,
//  and the pane copy, and a copy is what drifts.

import Foundation
import JanitorKit

/// A core that reaches Config through a store.
protocol ConfigBacked: AnyObject {
    /// The one copy of Config. Reads answer from it; writes run Rust's rule and then
    /// persist, unless the store is the in-memory one.
    var store: ConfigStore { get }

    /// Where a failed Config write is reported. A write that did not happen is answered
    /// as "it did not happen"; this is how the reason reaches the Diagnostic Log.
    var onConfigError: (@Sendable (String) -> Void)? { get }
}

// MARK: - The pure rules

extension JanitorCore {
    func matrixItems(names: [String], grouped: Bool) -> [MatrixItem] {
        JanitorKit.matrixItems(names: names, grouped: grouped)
    }

    func displayNameParts(groupLabel: String?, name: String) -> NameParts {
        JanitorKit.displayNameParts(groupLabel: groupLabel, name: name)
    }

    func badgeLabel(kind: LeafKind?) -> String {
        JanitorKit.badgeLabel(kind: kind)
    }

    func stateGlyph(_ state: EntryState) -> String {
        JanitorKit.stateGlyph(state: state)
    }

    func errorBanner(_ error: AppError) -> String {
        JanitorKit.errorBanner(error: error)
    }

    func paneTitle(_ pane: MainPane) -> String {
        JanitorKit.paneTitle(pane: pane)
    }

    func paneBody(_ pane: MainPane, statusMessage: String?) -> String {
        JanitorKit.paneBody(pane: pane, statusMessage: statusMessage)
    }

    func choicePrompt(_ what: What) -> String {
        JanitorKit.choicePrompt(what: what)
    }

    func methodChoices() -> [SecretMethod] {
        JanitorKit.methodChoices()
    }

    func methodLabel(_ method: SecretMethod) -> String {
        JanitorKit.methodLabel(method: method)
    }

    func methodName(_ method: SecretMethod) -> String {
        JanitorKit.methodName(method: method)
    }

    func summarizeEdits(_ edits: [EnvEdit]) -> [EditSummary] {
        JanitorKit.summarizeEdits(edits: edits)
    }
}

// MARK: - Config

extension JanitorCore where Self: ConfigBacked {
    func applications() -> [Application] { store.applications() }

    func environments(of application: Int) -> [Mapping] {
        store.environments(application: Usize(application))
    }

    func addApplication(name: String) -> Int? {
        guarded { try store.addApplication(name: name).map(Int.init) } ?? nil
    }

    func removeApplication(_ index: Int) {
        guarded { try store.removeApplication(index: Usize(index)) }
    }

    func renameApplication(_ index: Int, to name: String) -> Bool {
        guarded { try store.renameApplication(index: Usize(index), name: name) } ?? false
    }

    func addEnvironment(application: Int, mapping: Mapping) -> Bool {
        guarded {
            try store.addEnvironment(application: Usize(application), mapping: mapping)
        } ?? false
    }

    func removeEnvironment(application: Int, index: Int) {
        guarded {
            try store.removeEnvironment(application: Usize(application), index: Usize(index))
        }
    }

    func applyCorrectedRoles(application: Int, corrected: [Mapping]) -> Int {
        guarded {
            Int(try store.applyCorrectedRoles(
                application: Usize(application), corrected: corrected
            ))
        } ?? 0
    }

    func lastPick() -> Mapping? { store.snapshot().lastPick }

    func regionChoices() -> [String] { store.regionChoices() }

    func browseRegion() -> String { store.browseRegion() }

    func setBrowseRegion(_ region: String) {
        guarded { try store.setBrowseRegion(region: region) }
    }

    func identityCenter() -> IdentityCenter { store.identityCenter() }

    func setIdentityCenter(startURL: String, region: String) {
        guarded {
            try store.setIdentityCenter(
                startUrl: startURL.trimmingCharacters(in: .whitespaces),
                region: region.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    func entryColumnWidth(minimum: Double, fallback: Double) -> Double {
        store.entryColumnWidth(minimum: minimum, fallback: fallback)
    }

    func setEntryColumnWidth(_ points: Double, minimum: Double) {
        guarded { try store.setEntryColumnWidth(points: points, minimum: minimum) }
    }

    func sidebarRows(selected: Int, status: LoadStatus, view: MatrixView) -> [SidebarRow] {
        store.sidebarApps(selected: Usize(selected), view: view, status: status)
            .enumerated()
            .map {
                SidebarRow(
                    id: $0.offset,
                    name: $0.element.name,
                    subtitle: $0.element.subtitle,
                    drift: $0.element.drift
                )
            }
    }

    func mainPane(status: LoadStatus) -> MainPane {
        store.mainPane(status: status)
    }

    /// Run a Config write, reporting a failure rather than throwing it at a view.
    private func guarded<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            onConfigError?("config could not be saved — \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func guarded(_ body: () throws -> Void) -> Void? {
        guarded { () throws -> Bool in try body(); return true }.map { _ in () }
    }
}
