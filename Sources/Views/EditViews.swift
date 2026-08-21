//  EditViews.swift
//  Typing a new Value, and reviewing a batch before it is written.
//
//  Two rules shape all of this.
//
//  A staged Value is never drawn again. The editor is the only place it appears, and the
//  field is cleared the moment the sheet closes. Everywhere after that — the pending bar,
//  the review dialog, the Diagnostic Log — describes an edit as an Entry name and a byte
//  count. That description comes from the core, so the shell is not the thing deciding
//  what is safe to show.
//
//  Nothing is written until the operator reads the batch and presses Apply. A cell edit
//  stages; it does not send. What is sent goes through the engine that rewrites the
//  Entries in the batch and leaves the rest of the Set exactly as it found it.

import SwiftUI

/// The editor for one cell's Value.
struct EditValueSheet: View {
    let target: EditTarget
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var value = ""
    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("New Value")
                    .font(.headline)
                Text("\(target.name) in \(target.environment)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Concealed by default, because an editor left open is a Value on screen for
            // as long as the operator is away from the desk. The reveal is deliberate and
            // only lasts while the sheet does.
            HStack(spacing: 6) {
                Group {
                    if visible {
                        TextField("", text: $value)
                    } else {
                        SecureField("", text: $value)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono)

                Button {
                    visible.toggle()
                } label: {
                    Image(systemName: visible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(visible ? "Conceal" : "Show what you typed")
            }

            Text("\(value.utf8.count) bytes. Nothing is written until you review and apply the batch.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Stage Edit") {
                    model.stageEdit(row: target.row, col: target.col, value: value)
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(value.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    /// Clear the field before the sheet goes. What was typed does not outlive it.
    private func close() {
        value = ""
        model.editing = nil
        dismiss()
    }
}

/// The bar above the matrix while edits are staged. It is the way into the review, and
/// the reason a staged batch cannot be forgotten about.
struct PendingEditsBar: View {
    @Bindable var model: AppModel

    var body: some View {
        if let pending = model.pending {
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                Text("^[\(pending.count) edit](inflect: true) staged for \(pending.environment)")
                    .fontWeight(.medium)
                Spacer(minLength: 0)
                Button("Discard") { model.discardPending() }
                Button("Review and Apply…") { model.reviewing = true }
                    .buttonStyle(.borderedProminent)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.drift.opacity(0.14))
            .accessibilityElement(children: .combine)
        }
    }
}

/// The last look before anything is written: every edit in the batch, by Entry name and
/// size, and which Environment they land in.
struct ReviewEditsSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply to \(model.pending?.environment ?? "")")
                    .font(.headline)
                Text("Only these Entries change. Every other Entry in the Set is left as it is found, and if the Set changed since it was read, nothing is written at all.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.pendingSummary.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Theme.mono)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
            }
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))

            Text("Values are not shown. A byte count is enough to check you staged what you meant to.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Discard All", role: .destructive) { model.discardPending() }
                Spacer()
                Button("Not Yet", role: .cancel) { model.reviewing = false }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { model.applyPending() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 480)
    }
}
