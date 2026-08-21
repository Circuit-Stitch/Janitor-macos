//  SettingsView.swift
//  Global Settings, in the place macOS puts them.
//
//  In the Slint shell this was a dimmed backdrop and a centered card drawn inside the
//  main window. On macOS it is a `Settings` scene, so it gets the Settings menu item,
//  the ⌘, shortcut, and the window behavior every other Mac app has.
//
//  Two of these controls are worth reading twice.
//
//  The browse region is the same value the Manage window shows beside the field that
//  adds an Environment. Not a copy: both are bound to one property on the model, so
//  there is no state to keep in step.
//
//  Read-write mode is the deliberate unlock. The toggle asks; the worker decides. What
//  is drawn here is the worker's answer, which is why flipping it and seeing nothing
//  change would be correct behavior rather than a bug.

import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            Tab("Identity Center", systemImage: "person.badge.key") {
                identityCenter
            }
            Tab("Discovery", systemImage: "binoculars") {
                discovery
            }
            Tab("Access", systemImage: "lock") {
                access
            }
        }
        .frame(width: 520, height: 300)
    }

    // MARK: Identity Center

    private var identityCenter: some View {
        Form {
            Section {
                TextField("Start URL", text: $model.ssoStartURL)
                TextField("Region", text: $model.ssoRegion)
            } header: {
                Text("Where Janitor signs in")
            } footer: {
                Text("Saved to disk. Janitor stores no token and no credential — it signs in through the browser each launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Save") { model.saveIdentityCenter() }
                    .disabled(model.ssoStartURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Discovery

    private var discovery: some View {
        Form {
            Section {
                LabeledContent("Browse region") {
                    RegionPicker(model: model)
                        .frame(width: 180)
                }
            } header: {
                Text("Where the next walk looks")
            } footer: {
                Text("The same picker sits beside Add Environment in the Manage window. Changing either changes both, and it applies to the next walk with no save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Access

    private var access: some View {
        Form {
            Section {
                Toggle("Read-write mode", isOn: Binding(
                    get: { model.readWrite },
                    set: { model.setReadWrite($0) }
                ))
            } header: {
                Text("Mutation")
            } footer: {
                Text("Off is read-only, and off is where every launch starts. On lets Janitor write edits, always through the engine that changes the Entries you edited and leaves the rest of the Set alone. The lock is held by the worker, not by this switch: it refuses a write without making a call.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
