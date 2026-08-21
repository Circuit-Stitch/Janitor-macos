//  CellView.swift
//  One cell of the matrix.
//
//  A cell shows one of three things. Absent renders a dash. Present renders masked:
//  dots, the byte length, and the equality tag, which is enough to see that two
//  Environments agree without seeing what they agree on. Revealed renders the
//  plaintext, and only while the operator holds the press.
//
//  Value length is a deliberate, accepted side channel. It is what makes drift legible
//  while masked, and the threat model records the trade.
//
//  The revealed Value is read by VoiceOver. macOS puts third-party accessibility behind
//  an explicit permission grant and screen recording behind a separate one, so hiding
//  the reveal from one while the other stays open would not defend anything. It would
//  only make the feature unusable for a blind operator.

import SwiftUI

struct CellView: View {
    let cell: MatrixCell
    let environment: String
    let entryName: String
    /// The plaintext, present only while this cell is the revealed one.
    let revealedText: String?
    /// Whether this cell has an edit staged, which is drawn rather than described.
    let isStaged: Bool
    /// Whether editing is reachable at all. Read-write mode is the gate.
    let canEdit: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var pressing = false

    var body: some View {
        content
            .frame(width: Theme.Metrics.environmentColumn, height: Theme.Metrics.rowHeight,
                   alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(isStaged ? Theme.drift.opacity(0.18) : .clear)
            .gesture(pressGesture)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isPresent ? "Press and hold to reveal the value" : "")
            .contextMenu { menu }
    }

    @ViewBuilder
    private var content: some View {
        switch cell {
        case .absent:
            Text("—")
                .font(Theme.mono)
                .foregroundStyle(.tertiary)

        case .present(let len, _, let hex, _):
            if let revealedText {
                Text(revealedText)
                    .font(Theme.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.accentColor)
            } else {
                HStack(spacing: 6) {
                    Text("•••")
                        .font(Theme.mono)
                        .foregroundStyle(.secondary)
                    Text("\(len)")
                        .font(Theme.monoSmall)
                        .foregroundStyle(.secondary)
                    Text("#\(hex)")
                        .font(Theme.monoSmall)
                        .foregroundStyle(.tertiary)
                }
                .opacity(pressing ? 0.4 : 1)
            }
        }
    }

    /// Press and hold. `onPress` fires the moment the press starts and `onRelease` on
    /// the way up, including when the gesture is cancelled, so a drag off the cell ends
    /// the reveal the same way lifting a finger does.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isPresent, !pressing else { return }
                pressing = true
                onPress()
            }
            .onEnded { _ in
                pressing = false
                onRelease()
            }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Copy Entry Name") { Pasteboard.copyPlain(entryName) }
        if isPresent {
            Button("Copy Value") { onCopy() }
        }
        if canEdit {
            Divider()
            Button(isPresent ? "Edit Value…" : "Add Value…") { onEdit() }
            if isPresent {
                Button("Remove Entry", role: .destructive) { onRemove() }
            }
        }
    }

    private var isPresent: Bool {
        if case .present = cell { return true }
        return false
    }

    /// What VoiceOver reads. Masked cells describe the shape; a revealed cell reads the
    /// Value, which is the point of revealing it.
    private var accessibilityLabel: String {
        switch cell {
        case .absent:
            isStaged
                ? "\(entryName) in \(environment): absent, edit staged"
                : "\(entryName) in \(environment): absent"
        case .present(let len, _, let hex, _):
            if let revealedText {
                "\(entryName) in \(environment): \(revealedText)"
            } else if isStaged {
                "\(entryName) in \(environment): masked, \(len) bytes, group \(hex), edit staged"
            } else {
                "\(entryName) in \(environment): masked, \(len) bytes, group \(hex)"
            }
        }
    }
}
