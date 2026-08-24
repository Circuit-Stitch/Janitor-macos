//  AcknowledgmentsView.swift
//  The third-party notices for everything compiled into JanitorKit.
//
//  Janitor links 272 open-source packages. Most are offered under MIT, which asks that
//  the copyright notice travel with the software, so the notices have to ship inside the
//  app rather than sit on a web page. This window is where they are readable.
//
//  WHY THE LIST IS A FILE RATHER THAN SOMETHING COMPUTED
//
//  The shell compiles no Rust and has no Cargo.lock, so it cannot discover what it
//  links. `THIRD-PARTY-LICENSES.txt` is generated in the core repository, published to
//  the depot beside the framework zip under the same immutable key, and committed here
//  when the version and the checksum are bumped. See JanitorKit/Package.swift.
//
//  WHY SEARCH RATHER THAN FILTER
//
//  The search box scrolls to a match. It never hides lines. A notice file is a legal
//  statement and the whole of it has to be presentable, so a filter that showed only
//  matching rows would be the wrong control no matter how much nicer it read.

import SwiftUI

struct AcknowledgmentsView: View {
    /// The scene id. Opening the window and declaring it both name it, so they name one
    /// constant.
    static let windowID = "acknowledgments"

    /// The resource the generator writes and the publish workflow uploads.
    static let resource = "THIRD-PARTY-LICENSES"

    @State private var lines: [String] = []
    @State private var failure: String?
    @State private var query = ""
    @State private var matches: [Int] = []
    @State private var current = 0

    var body: some View {
        VStack(spacing: 0) {
            if let failure {
                ContentUnavailableView(
                    "Notices are missing",
                    systemImage: "doc.questionmark",
                    description: Text(failure)
                )
            } else {
                searchBar
                Divider()
                notices
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { load() }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find a package or a license", text: $query)
                .textFieldStyle(.plain)
                .onSubmit(advance)
                .onChange(of: query) { _, _ in find() }

            if !matches.isEmpty {
                Text("\(current + 1) of \(matches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Next", systemImage: "chevron.down", action: advance)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            } else if !query.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var notices: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { i in
                        NoticeLine(text: lines[i], marked: isCurrentMatch(i))
                            .id(i)
                    }
                }
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .onChange(of: current) { _, _ in scroll(proxy) }
            .onChange(of: matches) { _, _ in scroll(proxy) }
        }
    }

    /// Whether the search is currently sitting on this line.
    private func isCurrentMatch(_ i: Int) -> Bool {
        !matches.isEmpty && matches[current] == i
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard !matches.isEmpty else { return }
        withAnimation { proxy.scrollTo(matches[current], anchor: .center) }
    }

    /// Collect every matching line. The file runs to thousands of lines, so this walks it
    /// once per edit rather than per frame.
    private func find() {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else {
            matches = []
            current = 0
            return
        }
        matches = lines.indices.filter {
            lines[$0].range(of: needle, options: .caseInsensitive) != nil
        }
        current = 0
    }

    private func advance() {
        guard !matches.isEmpty else { return }
        current = (current + 1) % matches.count
    }

    // MARK: Loading

    /// Read the notices out of the bundle.
    ///
    /// A missing file is reported rather than swallowed. It means the resource was not
    /// copied or the version bump skipped it, and silently showing an empty window would
    /// turn a build mistake into a false statement about what Janitor links.
    private func load() {
        guard lines.isEmpty, failure == nil else { return }

        guard let url = Bundle.main.url(forResource: Self.resource, withExtension: "txt") else {
            failure = "\(Self.resource).txt is not in the app bundle. It is generated in "
                + "the core repository and committed here with the JanitorKit version."
            return
        }
        do {
            lines = try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: .newlines)
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// One line of the notice file.
///
/// A row rather than an inline closure so the type checker sees a small expression. The
/// file is thousands of lines and `LazyVStack` builds each one, so the body stays cheap.
private struct NoticeLine: View {
    let text: String
    let marked: Bool

    var body: some View {
        // An empty line still needs height, or the blank rows between license blocks
        // collapse and the file reads as one wall of text.
        Text(text.isEmpty ? " " : text)
            .font(Theme.monoSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(marked ? Color.accentColor.opacity(0.25) : .clear)
    }
}
