//  JanitorApp.swift
//  The composition root.
//
//  It builds one core, wraps it in one model, and hands that model to the windows. The
//  choice of core is the only decision made here, and today there is one to choose
//  from.
//
//  Three scenes. The matrix is the main window. Manage is a second window rather than a
//  sheet, because it stays bound to one Application while the operator keeps working in
//  the first. Settings is a `Settings` scene, so it lands where every Mac app puts it.

import SwiftUI

@main
struct JanitorApp: App {
    @State private var model = AppModel(core: StubCore())

    var body: some Scene {
        Window("Janitor", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 480)
                .task { model.signIn() }
        }
        .defaultSize(width: 1100, height: 700)
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
