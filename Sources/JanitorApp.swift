//  JanitorApp.swift
//  The composition root.
//
//  It builds one core, wraps it in one model, and hands that model to the window. The
//  choice of core is the only decision made here, and today there is one to choose
//  from.

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
