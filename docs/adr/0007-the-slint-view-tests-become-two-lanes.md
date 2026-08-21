# The Slint view tests become two lanes: layout arithmetic, and XCUITest

**Status:** accepted, 2026-08-21

Answers the open question left by
[Janitor#99](https://github.com/Circuit-Stitch/Janitor/issues/99): what replaces the
Slint shell's 26 view tests.

## Context

The Slint shell tests its views. A headless backend builds the window, feeds it
properties, forces a size, and reads back real element geometry. Elements are found by
accessible label. Twenty-six tests assert layout facts that way — column widths, band
alignment, the frozen columns, the pinned cluster header, the momentary reveal.

SwiftUI has no equivalent. A `body` is not reachable from a test, and hosting a view in
an `NSHostingView` inside a unit test produces an accessibility tree with no children:
macOS builds that tree for a client in another process, not for the process itself. The
choice was between XCUITest, snapshot tests, and giving the coverage up.

Two smaller facts decided it. Every layout rule the Slint tests assert is arithmetic on
numbers, and arithmetic can be tested without a view. And the app already carries a rich
accessibility tree — the matrix describes every cell to VoiceOver — which is exactly what
XCUITest reads.

## Decision

**Every layout rule is a function in `MatrixLayout`, and the views call it.** Column
width, the content floor, the room left beside the frozen pair, the ENTRY column's drag
and its floor, and which cluster header is pinned. Eighteen unit tests cover them, in the
fast lane with the rest of `JanitorTests`.

**The views are asserted against the running app, through XCUITest.** Nineteen tests in
`JanitorUITests` launch the app on `StubCore` and read the accessibility tree: the
comparison columns stretch and then hold their floor, each Environment name sits over its
own column, STATE stays left of ENTRY, a cluster header pins when its rows scroll under
it, dragging the ENTRY column reflows the comparison columns and stops at the floor, and
no cell shows anything but a masked shape.

A rule can be right and unused. The unit tests prove the arithmetic; the UI tests prove
the views are wired to it. Neither lane is enough alone.

**Elements are found by accessibility identifier, and every identifier is structural.**
`envcell-3-1`, `entryhdr`, `pinned-database.*`, `legend-gap`. An identifier says where an
element is or which cluster it labels. It never carries a Value, a length, or anything
derived from one.

**A test that needs a window size says so.** `JANITOR_WINDOW_SIZE` is a debug-only hook
in the app, read once at launch. Which layout the matrix uses depends on how much room it
has, so a test asserting one has to name a width. It is compiled out of release builds.

The hook pins the window, not the content. macOS restores a window's frame from the last
launch, so pinning only the content leaves the window at whatever size it was restored to
with the matrix floating in the middle of it, ringed by dead space.

**A synthesized pointer event that goes missing is retried, not asserted on.** A scroll or
a drag sent by XCUITest is sometimes dropped or cut short — a real pointer moving across
the screen at the same moment is enough to do it. What the app owes is where the column
ends up and what pins after the body moves, so the tests repeat the gesture until the app
gets there and fail only if it never does.

**The UI tests get their own scheme.** They drive the built app, so they need a signing
identity, and the unit tests do not. Keeping both in one scheme would mean a fresh clone
with no certificate could run no tests at all.

```bash
xcodebuild test -scheme Janitor       -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme JanitorUITests -destination 'platform=macOS'
```

## What the port found

Three defects, each one the thing its Slint test was written to catch.

**The comparison columns pushed the matrix out of its pane.** A horizontal `ScrollView`
asks for as much width as its content, so widening the ENTRY column did not narrow the
comparison columns — it made the table wider than the window, and the whole matrix slid
left out from under its own header and under the sidebar. The pane's width now decides
every width in the table, read once from a `GeometryReader` and handed down.

**A released Value stayed on screen.** The reveal was a `DragGesture`, and on macOS its
end event never arrives for a press that does not move. The Value stayed up until the
ten-second timeout took it down. It is an `onLongPressGesture` now, whose
`onPressingChanged` reports the release.

**The two bands of the freeze pane were eight points out of step.** Padding applied
outside a fixed-width frame made the header's ENTRY column wider than the body's, so
every Environment name sat eight points right of its own column. Padding is inside those
frames now, in both bands and in the cells.

## What did not come over

- **A Value showing while the press is held.** XCUITest cannot look at the screen in the
  middle of its own press. The showing half stays a model test; the release half is a UI
  test.
- **The Slint scrollbar tests.** Three of the twenty-six assert a hand-built horizontal
  scrollbar. macOS draws its own.
- **The settings card's geometry.** Two more assert a centered, width-bounded card drawn
  inside the main window. Settings is a `Settings` scene here (ADR 0005), so what is
  asserted instead is that the window opens with its three tabs and their controls.
- **A cluster header handing off to the next one.** The seeded matrix is nine rows, and
  the body scrolls sixty points, which reaches the first cluster and not the second. The
  handoff is covered as arithmetic.
- **The Secret ARN subtitle.** The Slint shell shows a representative ARN under the
  Application title. This shell does not show one yet.

## Consequences

- **The suite is 79 unit tests and 19 UI tests.** The unit lane runs in under a second.
  The UI lane takes about a minute and a half, because every test launches the app.
- **The app carries accessibility identifiers it did not have.** They cost nothing at
  runtime and they are what makes the shell testable, the same way the Slint shell's
  accessible labels are.
- **The UI lane needs a Mac that can run the app.** It signs, launches, moves the pointer,
  and types. It is not a lane that runs on a headless box without a session.
- **VoiceOver reads the matrix better than it did.** A grouped row drops the prefix its
  cluster header shows, and until now that was all a screen reader got. The whole Entry
  name is in the label now, and on hover.
