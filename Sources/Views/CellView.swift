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
    /// The column's width, which the table computes from the room it has.
    let width: CGFloat
    let environment: String
    let entryName: String
    /// The cell's position in the matrix, as `envcell-<row>-<column>`. Structural only:
    /// it names where the cell is, never what is in it.
    let identifier: String
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
            // The padding is inside the frame, so the cell is exactly one column wide
            // and the body's columns step by the same amount the header's do.
            .padding(.horizontal, 8)
            .frame(width: width, height: Theme.Metrics.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(isStaged ? Theme.drift.opacity(0.18) : .clear)
            // Press and hold, reported by `onPressingChanged`: true when the press
            // lands, false when it lifts or is cancelled. A `DragGesture` reads more
            // naturally here and is what this was, but on macOS its `onEnded` never
            // arrives for a press that does not move — so the Value stayed on screen
            // after the operator let go, until the ten-second timeout took it down.
            //
            // The duration is never reached, and `perform` is never called. The press
            // always ends first, and its ending is the only event this needs.
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: .infinity,
                perform: {},
                onPressingChanged: { isPressing in
                    guard isPresent else { return }
                    pressing = isPressing
                    if isPressing { onPress() } else { onRelease() }
                }
            )
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isPresent ? "Press and hold to reveal the value" : "")
            .accessibilityIdentifier(identifier)
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
