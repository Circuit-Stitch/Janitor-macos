# The About window is Janitor's own, and the notices arrive with the framework

**Status:** accepted, 2026-08-24

Follows [Janitor ADR 0037](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0037-apache-2-0-replaces-gpl-3-0-only.md),
which relicensed the project to Apache-2.0.

## Context

Janitor had no About surface. It used the standard AppKit panel, and the only copy in it
was one Info.plist string: *"Janitor is free software under the GNU General Public
License v3."* That string did two jobs at once, asserting the copyright and stating the
license, and the relicense separated them.

There was also an attribution gap, and it predates the relicense. `JanitorKit.xcframework`
carries 272 third-party packages. 55 are MIT-only and 157 are dual MIT-or-Apache. MIT asks
that its copyright notice be included in copies of the software. GPLv3 asked for the same
thing. Janitor shipped none of them, in either shell.

The shell cannot fix that by itself. It compiles no Rust, has no `Cargo.lock`, and
resolves one binary target by URL and checksum. That is the whole point of ADR 0035:
fetching one zip keeps Rust out of the Apple build. The consequence is that this build
cannot enumerate what it links.

## Decision

**Janitor draws its own About window.** `CommandGroup(replacing: .appInfo)` points the
menu item at it, because the stock item calls `orderFrontStandardAboutPanel` and would
leave the custom window unreachable.

It holds the Circuit Stitch mark, the app name, the version and build, the copyright, the
license, a link to the site, a link to the source, and a way through to the
acknowledgments. The stock panel has room for the first three and nowhere to put the
rest.

**Every string comes from the bundle.** The version, the build, and the copyright are read
from Info.plist, which XcodeGen generates from `project.yml`. The window cannot disagree
with what shipped.

**`NSHumanReadableCopyright` carries the copyright alone.** It reads
`Copyright © 2026 Circuit Stitch`. The About window states the license itself, so putting
it in the plist as well would print it twice.

**The logo is one template asset.** `circuit-stitch.svg` is a single-color stroke drawing
with no background, so the asset catalog renders it as a template and the tint comes from
the `BrandStroke` color set — `#BD6B00` in light appearance, `#FFD700` in dark.

A pair of fixed-color images was the alternative. It was rejected twice over. The finished
dark and light art bakes in its own substrate rect, which would read as a card pasted onto
the window material. And a static pair responds to appearance but not to Increase Contrast,
where a tint drawn from a color set follows both. This is a narrow exception to
`Theme.swift`, which takes colors from the system semantic set precisely so there is no
second palette to maintain.

**The acknowledgments get their own window.** The list runs to 8,682 lines. An About panel
sized to hold it stops being an About panel.

**The window searches, it does not filter.** The search box scrolls to a match and never
hides a line. A notice file is a legal statement, so all of it has to stay presentable.

**The notices are a generated file that travels with the framework.**
`scripts/third-party-licenses.py` in the core repository resolves the closure from
`Cargo.lock` and writes `THIRD-PARTY-LICENSES.txt`. The publish workflow uploads it beside
the zip, under the same immutable key scheme, so the notices are frozen with the bytes
they describe. Bumping the JanitorKit version fetches it and commits it here. That is step
4 of the ritual in `JanitorKit/Package.swift`, beside the version and the checksum it
belongs with.

## Considered options

- **Update the Info.plist string and stop.** One line, but leaves 272 packages
  unattributed.
- **`Credits.rtf` in the bundle.** AppKit loads it into the standard panel with no code at
  all. Rejected: no room for the publisher mark or the links, and the notice list is far
  too long for the panel's credits area.
- **A bundled text file opened in TextEdit.** Almost no UI to build. Rejected: it hands
  the operator off to another app for something Janitor should show.
- **Link to a hosted page.** Rejected: MIT asks that the notice be included in copies of
  the software, and a URL is not inclusion. It also breaks offline and rots if the page
  moves.
- **Generate the list during the Xcode Cloud build.** Always current. Rejected: it needs a
  Rust toolchain and a `Cargo.lock` in the Apple build, which ADR 0035 exists to prevent.

## Consequences

- **The version bump grows a fourth step.** Skipping it leaves the app asserting
  attribution for a dependency set it no longer links. `Package.swift` says so where the
  bump happens.
- **The app bundle grows by about 440 KB.** The notice file is plain text and compresses
  well in the archive.
- **Two new scenes.** Neither takes the model, so neither can touch a Secret Set, and
  `ScreenshotShield` does not apply: no Value ever reaches these windows.
- **The shell opens its first URLs.** The sign-in browser hand-off happens in the Rust
  core through `open::that`. The two links here are the first from Swift. Neither needs a
  fourth entitlement, because handing a URL to LaunchServices is permitted inside the
  sandbox. `Support/Janitor.entitlements` stays at three.
- **The Slint shell still has no acknowledgments surface.** It has the same obligation and
  the same gap. That is tracked in `Janitor-slint`, not here.
