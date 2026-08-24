//  SidebarView.swift
//  The Applications list, and where Applications are added, removed, and managed.
//
//  The drift badge shows on one row only: the selected, loaded one. The count comes
//  from the matrix that is loaded, and that matrix describes the selected Application
//  and nothing else. Putting a count on the other rows would mean fetching every
//  Application's secrets on launch.
//
//  Opening Manage from a row binds the window to that row's Application. That is the one
//  moment the selection decides the binding. Afterwards the window keeps it, and
//  clicking a different row here does not move it.

import JanitorKit
import SwiftUI

struct SidebarView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @State private var addingApplication = false
    @State private var draftName = ""

    var body: some View {
        List(selection: selection) {
            Section("Applications") {
                ForEach(model.apps) { app in
                    row(app)
                        .tag(app.id)
                        .contextMenu {
                            Button("Manage…") { manage(app.id) }
                            Divider()
                            Button("Remove", role: .destructive) {
                                model.removeApplication(at: app.id)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { addBar }
        .alert("New Application", isPresented: $addingApplication) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) { draftName = "" }
            Button("Add") {
                model.addApplication(named: draftName)
                draftName = ""
                openWindow(id: ManageView.windowID)
            }
        } message: {
            Text("It starts with no Environments. Add them in the Manage window, where Janitor discovers each one.")
        }
    }

    private var addBar: some View {
        HStack(spacing: 2) {
            Button {
                addingApplication = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Add an Application")

            Button {
                manage(model.selected)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Manage the selected Application")
            .disabled(model.apps.isEmpty)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func manage(_ index: Int) {
        model.openManage(index)
        openWindow(id: ManageView.windowID)
    }

    private var selection: Binding<Int?> {
        Binding(
            get: { model.selected },
            set: { if let index = $0 { model.select(index) } }
        )
    }

    private func row(_ app: SidebarRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                Text(app.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !app.drift.isEmpty {
                Text(app.drift)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.drift.opacity(0.2), in: .capsule)
                    .foregroundStyle(Theme.drift)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
