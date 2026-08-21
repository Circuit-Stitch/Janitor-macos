# Manage is a window, Settings is a Settings scene, and the wizard has one state

**Status:** accepted, 2026-08-21

Implements the surfaces [Janitor#99](https://github.com/Circuit-Stitch/Janitor/issues/99)
lists, and answers the first of the three questions it left open.

## Context

The Slint shell drew both of these inside the main window. Manage was a second `Window`
component. Global Settings was a dimmed backdrop with a centered card, which is what a
framework without a settings convention leaves you to build.

One rule rides on the Manage window and it is the reason the window exists. It stays
bound to the Application it was opened for. A guided walk can take several seconds and
several clicks, and the operator keeps working in the matrix while it runs. If the window
followed the sidebar, a walk started for one Application would deposit its Environment in
whichever one happened to be selected when it finished. Nothing afterwards would look
wrong: the matrix would render, the column would have a name, and it would be pointed at
a different Secret Set.

## Decision

**Manage is a real secondary window, one at a time.**

A sheet was the alternative and it fails on the first sentence above: a sheet is modal, so
the matrix the operator is comparing against is unreachable while a walk runs. An
inspector fails on the second: an inspector belongs to the main window and follows its
selection, which is the retargeting this rule forbids.

It is a `Window` scene rather than a `WindowGroup`. The model holds one binding, so a
second window would be a second claim on it.

The binding lives in the model as `ManageSession.application`, fixed when the window
opens. `select` does not touch it. A discovered Mapping is appended to that index, and
`selected` is not consulted. Opening Manage again on a different Application does rebind
it — an explicit request is not the same as a side effect of a click somewhere else.

**Settings is a `Settings` scene.** It gets the Settings menu item, ⌘,, and the window
behavior every other Mac app has. Three tabs: Identity Center, Discovery, Access.

**The Discovery wizard's three states are one property.** Status, a choice picker, and a
free-text field are cases of `DiscoveryState`, so two of them cannot be on screen at once.
Slint held them as separate properties and kept them apart by convention.

An advisory is not one of the three. It describes the walk rather than asking anything —
that this read will be archived by org-wide session logging, for instance — so it rides
beside the question in its own property. Replacing a question with it would lose the
question.

**The browse region is one property bound in two places.** Settings shows it and so does
the Manage window, beside the field that adds an Environment. Not a copy and not an
observer: `AppModel.browseRegion` is the value both read, so they cannot disagree. It is a
picker in both places and never a text field, because a mistyped region fails a walk with
an error that reads like a permissions problem.

**Config is the core's, and the shell reads it through the seam.** `JanitorCore` gained
Environments, add, remove, rename, the region choices, and the Identity Center fields. The
shell holds the last answer, never its own copy. Two refusals stay core rules rather than
view rules: a blank Application name, and an Environment name that already exists.

## Consequences

- **The binding rule is testable without a view.** `ManageTests` opens a window, changes
  the selection, and asserts where the Mapping lands.
- **A blank name and a duplicate Environment are refused in one place.** The window shows
  what the core answered.
- **`SecretMethod`, not `Method`.** Rust calls it `Method` and so will the generated
  Swift, but a type named `Method` shadows the Objective-C runtime's `Method` for the
  whole module. It compiles, and then tooling resolves the wrong one in any file that
  cannot see ours. One typealias reconciles the two when JanitorKit lands.
- **`envDiscovered` carries the Mapping** rather than naming an Environment the core
  already filed. That keeps where it lands a shell decision, which is the only place the
  binding rule can live.
- **Two commands and two events are deliberately missing** from the mirrored protocol.
  They drive the Windows MSIX updater, and a Mac App Store build is updated by the App
  Store.
