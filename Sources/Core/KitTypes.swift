//  KitTypes.swift
//  The names the shell writes, bound to the types JanitorKit generates.
//
//  This file replaced Protocol.swift, which declared the command and event vocabulary by
//  hand so the views could be built before the xcframework existed. UniFFI generates the
//  same shapes from the Rust, so the hand-written copies are gone and the views kept
//  compiling — which is what that file was for.
//
//  What is left is the reconciliation, and it is small:
//
//  * Three names differ. Rust calls the enums `Method`, `Command`, and `Event`. A type
//    named `Method` shadows the Objective-C runtime's `Method` for this whole module —
//    it compiles, and then tooling resolves the wrong one in any file that does not see
//    ours. `Command` and `Event` are too general to read well beside SwiftUI's own
//    vocabulary. Three typealiases, and the generated types are what they name.
//
//  * Conformances the shell needs and a generated type has no reason to carry:
//    Identifiable for the collections SwiftUI iterates, and two conveniences that read
//    better than a switch at the call site.
//
//  * `Usize`. Rust counts with `usize` and UniFFI crosses it as `UInt64`, so every index
//    and length arrives as one. Converting at the edge is what keeps `Int(...)` out of
//    the views.
//
//  Nothing here decides anything. Every rule is in Rust, reached through JanitorCore.

import Foundation
import JanitorKit

// MARK: - Names

/// Named `Method` in the Rust and in the generated Swift. See the note above for why it
/// is not named that here.
typealias SecretMethod = JanitorKit.Method

/// Shell to core. Every command returns immediately; the answer arrives as an event.
typealias JanitorCommand = JanitorKit.Command

/// Core to shell.
typealias JanitorEvent = JanitorKit.Event

// MARK: - Conformances

extension Mapping: @retroactive Identifiable {
    /// Environment names are unique within an Application — adding a duplicate is
    /// refused rather than applied — so the name identifies the row.
    public var id: String { environment }
}

extension SecretMethod: @retroactive Identifiable {
    public var id: Self { self }
}

extension SidebarApp: @retroactive Identifiable {
    /// The sidebar is built from Config in order, so a row's position is its identity
    /// for as long as the list is.
    public var id: String { name }
}

extension MatrixView {
    /// Nothing loaded. The matrix holds no Values, so an empty one is just an empty one.
    static let empty = MatrixView(environments: [], rows: [])
}

extension EnvEdit {
    /// The Entry name this edit touches. A name is metadata, so it is safe to show and
    /// to log.
    var key: String {
        switch self {
        case .set(let key, _): key
        case .remove(let key): key
        // JanitorKit ships with library evolution, so Swift treats every enum in it as
        // able to gain a case. An edit this build cannot name has no key to show.
        @unknown default: ""
        }
    }
}

extension EditSummary {
    /// One reviewable line: the Entry name and what happens to it, with a `set` reduced
    /// to the new Value's byte count. The Value itself is never here — the core masked
    /// it before this crossed.
    var line: String {
        switch action {
        case .set: "\(key) — set, \(valueLen ?? 0) bytes"
        case .remove: "\(key) — remove"
        @unknown default: key
        }
    }
}

// MARK: - Rendered row list

extension MatrixItem {
    /// The row's index into `MatrixView.rows`, or nil for a header. This is the reveal
    /// coordinate space.
    var rowIndex: Int? {
        if case .row(let index, _, _) = self { Int(index) } else { nil }
    }
}

/// One prefix cluster as the table draws it: its header, if it has one, and the rows
/// under it.
///
/// The core decides the clusters. This is the same list nested rather than flat, which is
/// what a section-pinning stack needs and what a flat list cannot express. Rows that
/// belong to no cluster arrive as a leading section with no header.
struct MatrixSection: Identifiable {
    /// The section's position in the list, which is stable for as long as the list is.
    var id: Int
    var header: (label: String, count: Int)?
    var rows: [(index: Int, zebra: Bool, groupLabel: String?)]
}

extension MatrixItem {
    /// Nest a rendered row list into its sections, converting the Rust counts as it
    /// goes so nothing above this line handles a `Usize`.
    static func sections(_ items: [MatrixItem]) -> [MatrixSection] {
        var sections: [MatrixSection] = []
        for item in items {
            switch item {
            case .header(let label, let count):
                sections.append(
                    MatrixSection(id: sections.count, header: (label, Int(count)), rows: [])
                )
            case .row(let index, let zebra, let groupLabel):
                if sections.isEmpty {
                    sections.append(MatrixSection(id: 0, header: nil, rows: []))
                }
                sections[sections.count - 1].rows
                    .append((index: Int(index), zebra: zebra, groupLabel: groupLabel))
            // A line this build cannot name is dropped rather than drawn wrong. The
            // rendered list comes from the core, so this cannot happen against a
            // matching JanitorKit.
            @unknown default:
                continue
            }
        }
        return sections
    }
}

// MARK: - Bounds

extension Array {
    /// The element at `index`, or nil when it is out of range. Manage windows and
    /// pending loads both outlive the Application they name, so several reads here have
    /// to tolerate an index that no longer exists.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
