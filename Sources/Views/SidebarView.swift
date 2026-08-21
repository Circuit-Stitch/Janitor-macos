//  SidebarView.swift
//  The Applications list.
//
//  The drift badge shows on one row only: the selected, loaded one. The count comes
//  from the matrix that is loaded, and that matrix describes the selected Application
//  and nothing else. Putting a count on the other rows would mean fetching every
//  Application's secrets on launch.

import SwiftUI

struct SidebarView: View {
    let model: AppModel

    var body: some View {
        List(selection: selection) {
            Section("Applications") {
                ForEach(model.apps) { app in
                    row(app)
                        .tag(app.id)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selection: Binding<Int?> {
        Binding(
            get: { model.selected },
            set: { if let index = $0 { model.select(index) } }
        )
    }

    private func row(_ app: SidebarApp) -> some View {
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
