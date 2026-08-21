//  ContentView.swift
//  The main window: Applications on the left, the matrix on the right, and the chrome
//  around it.
//
//  Three pieces of state here are worth naming.
//
//  The read-only badge reads the worker's lock, not a constant. The worker is the
//  authority on whether a write can happen, so the badge has to reflect what it says.
//
//  The window drops its reveal when it stops being the key window. Plaintext should not
//  sit on a background window while the operator works somewhere else.
//
//  The window is excluded from other processes' screen captures while a Value is
//  revealed, and shareable again the moment it is not.

import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            detail
        }
        .navigationTitle("Janitor")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .screenshotRedacted(model.revealed != nil)
        .onChange(of: activeState) { _, state in
            // Losing key window status ends the reveal.
            if state != .key { model.endReveal() }
        }
        .sheet(item: $model.editing) { target in
            EditValueSheet(target: target, model: model)
        }
        .sheet(isPresented: $model.reviewing) {
            ReviewEditsSheet(model: model)
        }
        .alert(
            model.editNotice?.title ?? "",
            isPresented: Binding(
                get: { model.editNotice != nil },
                set: { if !$0 { model.editNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.editNotice = nil }
        } message: {
            Text(model.editNotice?.message ?? "")
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if let banner = model.banner {
                ErrorBanner(text: banner)
            }

            PendingEditsBar(model: model)

            switch model.pane {
            case .matrix:
                MatrixTable(model: model)
            case .emptyApps:
                message(
                    title: model.paneTitle(.emptyApps),
                    body: "Add an Application in the sidebar to compare its Environments.",
                    systemImage: "tray"
                )
            case .signIn, .signing, .loading, .error:
                message(
                    title: model.paneTitle(model.pane),
                    body: model.paneBody(model.pane),
                    systemImage: icon(for: model.pane),
                    action: model.pane == .signIn || model.pane == .error
                        ? ("Sign In", { model.signIn() })
                        : nil
                )
            }

            if model.logVisible {
                Divider()
                DiagnosticLogView(lines: model.log)
            }

            Divider()
            statusBar
        }
    }

    private func message(
        title: String,
        body: String,
        systemImage: String,
        action: (String, () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.medium))
            Text(body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func icon(for pane: MainPane) -> String {
        switch pane {
        case .error: "exclamationmark.triangle"
        case .loading, .signing: "hourglass"
        default: "person.badge.key"
        }
    }

    // MARK: Chrome

    private var subtitle: String {
        guard model.selected < model.apps.count else { return "" }
        return model.apps[model.selected].name
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            // Reads the worker's lock rather than a constant. Janitor ships read-only,
            // and this says so only while that is true.
            Label(model.readWrite ? "Read-write" : "Read-only",
                  systemImage: model.readWrite ? "lock.open" : "lock")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(model.readWrite ? Theme.drift : .secondary)
        }
        ToolbarItem {
            Toggle("Group by prefix", isOn: $model.grouped)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        ToolbarItem {
            Button {
                model.loadSelected()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.status == .loading || model.status == .signingIn)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            legend("=", "Aligned", Theme.aligned)
            legend("≠", "Drift", Theme.drift)
            legend("∅", "Gap", Theme.gap)
            Spacer()
            if let identity = model.identity {
                Text(identity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let loadedAt = model.loadedAt {
                // `.relative` keeps counting on its own, so the operator can see how
                // stale the matrix is without the view owning a timer.
                (Text("read ") + Text(loadedAt, style: .relative) + Text(" ago"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button {
                model.logVisible.toggle()
            } label: {
                Label("Diagnostic Log", systemImage: "text.alignleft")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private func legend(_ glyph: String, _ name: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(glyph)
                .font(Theme.monoSmall)
                .foregroundStyle(color)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The failure banner. It names the Environment and shows the scrubbed reason the core
/// produced. A Value, a Credential, or SDK text never reaches it.
struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(Theme.gap)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gap.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}
