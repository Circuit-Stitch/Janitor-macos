//  Theme.swift
//  The colors and metrics the matrix is drawn with.
//
//  Colors come from the system semantic set wherever one fits, so light mode, dark
//  mode, increased contrast, and accent-color changes all follow the operator's
//  settings without a second palette to maintain.
//
//  The three state colors are the exception. Aligned, Drift, and Gap have to stay
//  distinguishable, and each one is paired with a glyph, so the reading never depends
//  on color alone.

import SwiftUI

enum Theme {
    /// Present everywhere with identical Values.
    static let aligned = Color.green
    /// Present everywhere, Values differ.
    static let drift = Color.orange
    /// Missing somewhere. The highest-signal finding.
    static let gap = Color.red

    static func color(for state: EntryState) -> Color {
        switch state {
        case .aligned: aligned
        case .drift: drift
        case .gap: gap
        }
    }

    /// The fixed sizes the matrix is built from. The widths that change with the window
    /// or with a drag are computed in `MatrixLayout`, which is where they can be tested.
    enum Metrics {
        static let stateColumn: CGFloat = 34
        static let rowHeight: CGFloat = 30
        static let headerHeight: CGFloat = 26
        /// The hairline between the frozen pair and the comparison columns.
        static let dividerWidth: CGFloat = 1
    }

    /// The tabular figures the matrix reads in. Lengths line up column to column.
    static let mono = Font.system(.body, design: .monospaced).monospacedDigit()
    static let monoSmall = Font.system(.caption, design: .monospaced).monospacedDigit()
}
