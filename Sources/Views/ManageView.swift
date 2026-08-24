//  ManageView.swift
//  Everything about one Application: its name, its Environments, and the guided walk
//  that adds another one.
//
//  It is a real window rather than a sheet or an inspector, and that is the whole reason
//  the binding holds. A sheet would block the matrix the operator is comparing against.
//  An inspector belongs to the main window and would follow the sidebar, which is
//  exactly the retargeting that must not happen: a walk started for staging must not
//  deposit its Environment in whichever Application was clicked while it ran.
//
//  The wizard below has three states and they are one property, so two of them can never
//  be on screen at once. An advisory is separate, because it describes the walk rather
//  than asking anything, and it belongs beside the question.

import JanitorKit
import SwiftUI

struct ManageView: View {
    /// The scene id. Opening the window and declaring it both name it, so they name one
    /// constant.
    static let windowID = "manage"

    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftName = ""
    @State private var newEnvironment = ""
    @State private var method: SecretMethod = .secretsManager

    var body: some View {
        Group {
            if let session = model.manage {
                content(session)
                    .navigationTitle("Manage · \(session.name)")
            } else {
                ContentUnavailableView(
                    "No Application",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Choose an Application in the sidebar and open Manage again.")
                )
                .navigationTitle("Manage")
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .onDisappear { model.closeManage() }
    }

    private func content(_ session: ManageSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            name(session)
            Divider()
            environments(session)
            Divider()
            addEnvironment
            wizard(session)
            Spacer(minLength: 0)
        }
        .padding(18)
        // The field seeds from the bound Application and re-seeds when the binding
        // changes, so it always shows the saved name rather than a stale draft.
        .onAppear { draftName = session.name }
        .onChange(of: session.name) { _, name in draftName = name }
        .onChange(of: session.application) { _, _ in
            newEnvironment = ""
            method = .secretsManager
        }
    }

    // MARK: Name

    private func name(_ session: ManageSession) -> some View {
        HStack(spacing: 8) {
            Text("Name")
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField("Application name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.renameManagedApplication(to: draftName) }
            Button("Rename") { model.renameManagedApplication(to: draftName) }
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty
                    || draftName == session.name)
        }
    }

    // MARK: Environments

    private func environments(_ session: ManageSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENVIRONMENTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if session.environments.isEmpty {
                Text("No Environments yet. Add one below and Janitor discovers the rest.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(session.environments.enumerated()), id: \.element.id) { index, env in
                    environmentRow(env, at: index)
                }
            }
        }
    }

    private func environmentRow(_ env: Mapping, at index: Int) -> some View {
        HStack(spacing: 10) {
            Text(env.environment)
                .fontWeight(.medium)
                .frame(width: 84, alignment: .leading)
            Text(model.methodLabel(env.method))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(nsColor: .quaternaryLabelColor), in: .rect(cornerRadius: 3))
                .frame(width: 44, alignment: .leading)
            Text(env.accountId)
                .font(Theme.monoSmall)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(env.region)
                .font(Theme.monoSmall)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(env.secretId)
                .font(Theme.monoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Remove") { model.removeManagedEnvironment(at: index) }
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Add

    private var addEnvironment: some View {
        HStack(spacing: 8) {
            TextField("environment name (e.g. prod)", text: $newEnvironment)
                .textFieldStyle(.roundedBorder)
                .onSubmit(startWalk)

            Picker("Method", selection: $method) {
                ForEach(model.methodChoices()) { method in
                    Text(model.methodName(method)).tag(method)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            // The same sticky value the Settings picker writes. It is here as well as
            // there because the region the next walk browses is worth seeing at the
            // moment of the add, and flipping it between adds is how one Application
            // ends up spanning regions.
            RegionPicker(model: model)
                .frame(width: 150)

            Button("Add Environment", action: startWalk)
                .disabled(newEnvironment.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func startWalk() {
        model.beginDiscovery(environment: newEnvironment, method: method)
        newEnvironment = ""
    }

    // MARK: The wizard

    @ViewBuilder
    private func wizard(_ session: ManageSession) -> some View {
        if session.discovery != .idle || session.advisory != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let advisory = session.advisory {
                    Label(advisory, systemImage: "exclamationmark.bubble")
                        .font(.callout)
                        .foregroundStyle(Theme.drift)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switch session.discovery {
                case .idle:
                    EmptyView()

                case .working(let text):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(text).foregroundStyle(.secondary)
                    }

                case .choice(let prompt, let labels, let defaultIndex):
                    ChoiceList(
                        prompt: prompt,
                        labels: labels,
                        defaultIndex: defaultIndex,
                        pick: { model.advanceDiscovery(choice: $0) }
                    )

                case .input(let prompt, let text):
                    InputStep(prompt: prompt, text: text) { model.provideInput($0) }

                case .terminal(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.gap)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Back") { model.dismissDiscovery() }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .underPageBackgroundColor), in: .rect(cornerRadius: 6))
        }
    }
}

/// The pick step. One button per presenter line, with the remembered pick marked.
private struct ChoiceList: View {
    let prompt: String
    let labels: [String]
    let defaultIndex: Int?
    let pick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt).font(.callout.weight(.medium))
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button {
                    pick(index)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: index == defaultIndex
                            ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(index == defaultIndex ? Color.accentColor : .secondary)
                        Text(label)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 4))
            }
        }
    }
}

/// The free-text step. The typed answer is a location, such as a path on a host, and it
/// is the one place in the wizard the operator types rather than picks.
private struct InputStep: View {
    let prompt: String
    let text: String
    let submit: (String) -> Void

    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt).font(.callout.weight(.medium))
            HStack(spacing: 8) {
                TextField("", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit(typed) }
                Button("Continue") { submit(typed) }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        // Seeded from the remembered answer, and re-seeded if the walk asks again.
        .onAppear { typed = text }
        .onChange(of: text) { _, text in typed = text }
    }
}

/// The browse-region picker. A list of known regions and the operator's own, never a
/// text field: a typo in a region name fails a walk with an error that reads like a
/// permissions problem.
struct RegionPicker: View {
    let model: AppModel

    var body: some View {
        Picker("Browse region", selection: Binding(
            get: { model.browseRegion },
            set: { model.setBrowseRegion($0) }
        )) {
            ForEach(model.regionChoices, id: \.self) { region in
                Text(region).tag(region)
            }
        }
        .labelsHidden()
    }
}
