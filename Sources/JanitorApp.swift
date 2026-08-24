//  JanitorApp.swift
//  The composition root.
//
//  It builds one core, wraps it in one model, and hands that model to the windows. The
//  choice of core is the only decision made here: the real one, driving the Rust worker
//  over JanitorKit. `JANITOR_MOCK=1` swaps the Provider behind it for the offline one
//  and stops Config being written, which is what the UI tests run against.
//
//  Three scenes. The matrix is the main window. Manage is a second window rather than a
//  sheet, because it stays bound to one Application while the operator keeps working in
//  the first. Settings is a `Settings` scene, so it lands where every Mac app puts it.

import JanitorKit
import SwiftUI

@main
struct JanitorApp: App {
    @State private var model = JanitorApp.build()

    /// Build the core and the model over it, and route a failed Config write into the
    /// Diagnostic Log rather than letting it disappear.
    @MainActor
    private static func build() -> AppModel {
        let core = JanitorKitCore.launch()
        let model = AppModel(core: core)
        core.onConfigError = { reason in
            Task { @MainActor in model.report(reason) }
        }
        return model
    }

    var body: some Scene {
        Window("Janitor", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 480)
                .frame(width: Self.fixedSize?.width, height: Self.fixedSize?.height)
                .task { model.signIn() }
        }
        .defaultSize(width: 1100, height: 700)
        // With a size named by the environment the window is pinned to it. Without one
        // this is `.automatic`, which is the ordinary resizable window. Pinning only the
        // content would leave the window at whatever size it was restored to, with the
        // matrix floating in the middle of it.
        .windowResizability(Self.fixedSize == nil ? .automatic : .contentSize)
        .commands { commands }

        // One Manage window, not a group. The model holds one binding, so a second
        // window would be a second claim on it.
        Window("Manage", id: ManageView.windowID) {
            ManageView(model: model)
        }
        .defaultSize(width: 720, height: 520)

        Settings {
            SettingsView(model: model)
        }
    }

    /// A window size named by the environment, as `WIDTHxHEIGHT`.
    ///
    /// The layout is what the UI tests assert, and the layout depends on how much room
    /// the window has, so a test has to be able to name a width. Debug builds only: the
    /// shipping app sizes its window the way every other Mac app does.
    private static var fixedSize: CGSize? {
        #if DEBUG
            guard let raw = ProcessInfo.processInfo.environment["JANITOR_WINDOW_SIZE"] else {
                return nil
            }
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return CGSize(width: parts[0], height: parts[1])
        #else
            nil
        #endif
    }

    @CommandsBuilder
    private var commands: some Commands {
        // The New Item group is where a document-based app puts New and Open. Janitor
        // opens no documents, so it is replaced rather than left showing menu items
        // that do nothing.
        CommandGroup(replacing: .newItem) {
            Button("Refresh") { model.loadSelected() }
                .keyboardShortcut("r")
                .disabled(model.status == .loading || model.status == .signingIn)
            Divider()
            Button("Sign In") { model.signIn() }
                .disabled(model.status == .signingIn)
        }

        CommandMenu("View") {
            Toggle("Group by Prefix", isOn: Binding(
                get: { model.grouped },
                set: { model.grouped = $0 }
            ))
            .keyboardShortcut("g")
            Divider()
            Toggle("Diagnostic Log", isOn: Binding(
                get: { model.logVisible },
                set: { model.logVisible = $0 }
            ))
            .keyboardShortcut("l")
        }

        CommandGroup(after: .newItem) {
            ManageMenuItem(model: model)
        }

        CommandMenu("Secrets") {
            // The deliberate unlock. Janitor ships read-only, the worker enforces it,
            // and this is the one control that asks the worker to change its mind.
            Toggle("Read-Write Mode", isOn: Binding(
                get: { model.readWrite },
                set: { model.setReadWrite($0) }
            ))
            Divider()
            Button("End Reveal") { model.endReveal() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(model.revealed == nil)
            Button("Clear Clipboard") { Pasteboard.clearIfOwned() }
        }
    }
}

/// The Manage menu item. It opens the window on the selected Application, which is the
/// only place the selection decides the binding — from then on the window keeps it.
private struct ManageMenuItem: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Manage Application…") {
            model.openManage(model.selected)
            openWindow(id: ManageView.windowID)
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(model.apps.isEmpty)
    }
}
