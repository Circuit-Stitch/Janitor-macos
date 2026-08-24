//  MatrixLayout.swift
//  The matrix's layout arithmetic, kept out of the views that draw with it.
//
//  Everything here is a pure function of numbers. That is the point. A SwiftUI body is
//  not reachable from a test, so a rule that lives inside one is a rule nothing checks.
//  These are the rules the freeze pane, the column sizing, and the pinned header depend
//  on, and every one of them has a test.
//
//  The comparison columns share the width left over beside the frozen pair. They stretch
//  to fill it, down to a floor. Below the floor they stop shrinking and the region
//  scrolls instead, because a column narrower than the masked cell it holds shows
//  nothing worth reading.

import JanitorKit
import CoreGraphics

enum MatrixLayout {
    /// The narrowest a comparison column gets. A masked cell draws dots, a byte count,
    /// and an equality tag, and this is what fits them.
    static let environmentFloor: CGFloat = 200

    /// The narrowest the ENTRY column gets when dragged.
    static let entryFloor: CGFloat = 200

    /// The ENTRY column's width before anyone has dragged it.
    static let entryDefault: CGFloat = 300

    // MARK: The comparison columns

    /// One comparison column's width, given the room beside the frozen pair.
    ///
    /// With few columns and a wide window the columns divide the whole band, so there is
    /// no gutter on the right. With many columns, or a narrow window, they hold the
    /// floor and the band scrolls.
    static func environmentColumnWidth(available: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return environmentFloor }
        return max(environmentFloor, available / CGFloat(count))
    }

    /// How wide all the columns are together. Wider than `available` means the region
    /// scrolls horizontally.
    static func environmentContentWidth(available: CGFloat, count: Int) -> CGFloat {
        environmentColumnWidth(available: available, count: count) * CGFloat(count)
    }

    /// Whether the columns overflow the room they have.
    static func environmentOverflows(available: CGFloat, count: Int) -> Bool {
        environmentContentWidth(available: available, count: count) > available
    }

    /// Where one comparison column starts, measured from the left edge of the band.
    ///
    /// The header band and the body both use this, which is what puts an Environment
    /// name over its own column. One origin and one step, in both halves.
    static func environmentColumnOrigin(index: Int, width: CGFloat) -> CGFloat {
        CGFloat(index) * width
    }

    /// What the header band shifts by when the body has scrolled horizontally.
    ///
    /// The header band is not itself scrollable. It follows the body, so it moves the
    /// opposite way by the same amount.
    static func headerBandOffset(bodyContentOffset: CGFloat) -> CGFloat {
        -bodyContentOffset
    }

    // MARK: The frozen pair

    /// The two frozen columns together: the state glyph and the Entry name.
    static func frozenWidth(entryWidth: CGFloat) -> CGFloat {
        Theme.Metrics.stateColumn + entryWidth
    }

    /// The room left for the comparison columns beside the frozen pair.
    static func availableEnvironmentWidth(total: CGFloat, entryWidth: CGFloat) -> CGFloat {
        max(0, total - frozenWidth(entryWidth: entryWidth) - Theme.Metrics.dividerWidth)
    }

    // MARK: The ENTRY column drag

    /// The ENTRY column's width during a drag.
    ///
    /// `anchor` is the width when the press landed, and `translation` is how far the
    /// cursor has moved since. Measuring from the width at the press is what makes the
    /// column track the cursor: a drag that adds each frame's movement to the current
    /// width instead counts every frame twice and runs away from the pointer.
    static func entryWidth(anchor: CGFloat, translation: CGFloat) -> CGFloat {
        clampEntryWidth(anchor + translation)
    }

    /// The ENTRY column never goes below its floor, however far the drag goes.
    static func clampEntryWidth(_ width: CGFloat) -> CGFloat {
        max(entryFloor, width)
    }

    // MARK: The pinned cluster header

    /// Which cluster header floats at the top of the pane at a given scroll offset.
    ///
    /// Nil while the section's own header is still on screen — its inline copy is doing
    /// the job, and drawing a second one over it would double the label. Nil also for a
    /// section with no header, which is what ungrouped rows are.
    static func pinnedHeader(sections: [MatrixSection], offset: CGFloat)
        -> (label: String, count: Int)?
    {
        var top: CGFloat = 0
        for section in sections {
            let headerHeight = section.header == nil ? 0 : Theme.Metrics.headerHeight
            let height = headerHeight + CGFloat(section.rows.count) * Theme.Metrics.rowHeight
            if offset < top + height {
                guard offset > top, let header = section.header else { return nil }
                return header
            }
            top += height
        }
        return nil
    }
}
