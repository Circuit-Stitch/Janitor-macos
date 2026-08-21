//  DiagnosticLogView.swift
//  The Diagnostic Log panel.
//
//  An App Store app has no terminal behind it. When a load fails, this is where the
//  failure gets to explain itself.
//
//  Every line here is metadata: an Environment name, an Entry name, a scrubbed reason.
//  The core scrubs failure detail before it leaves Rust, and the reducer never writes a
//  Value into a line. A copied Value is logged as `NAME[env] copied to clipboard`, which
//  names the cell and not its contents.

import SwiftUI

struct DiagnosticLogView: View {
    let lines: [LogLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Diagnostic Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    Pasteboard.copyPlain(lines.map(Self.format).joined(separator: "\n"))
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(lines.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            Text(Self.format(line))
                                .font(Theme.monoSmall)
                                .foregroundStyle(color(line.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: lines.last?.id) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
        .frame(height: 180)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func color(_ level: LogLine.Level) -> Color {
        switch level {
        case .info: .secondary
        case .warn: Theme.drift
        case .error: Theme.gap
        }
    }

    private static let clock: Date.FormatStyle = .dateTime.hour().minute().second()

    private static func format(_ line: LogLine) -> String {
        "\(line.at.formatted(clock))  \(line.level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0))  \(line.message)"
    }
}
