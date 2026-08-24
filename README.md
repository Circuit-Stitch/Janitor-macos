# Janitor for macOS

The SwiftUI shell for [Janitor](https://github.com/Circuit-Stitch/Janitor), built for
the Mac App Store.

**macOS only.** Linux and Windows keep the Slint shell, in
[Janitor-slint](https://github.com/Circuit-Stitch/Janitor-slint). File Linux and Windows
issues there.

## What Janitor is

Janitor is an ephemeral desktop client onto your AWS secrets. It compares the same
logical Secret Set across several Environments in a masked matrix, so a missing or
mismatched Entry is visible without a Value ever appearing on screen.

It stores no secrets and no credentials of its own. It borrows them on demand and
forgets them. The only thing written to disk is configuration: where Secret Sets live,
never what is in them.

The domain vocabulary, the threat model, and every architectural decision live in
[Janitor](https://github.com/Circuit-Stitch/Janitor). This repository does not copy
them.

- [CONTEXT.md](https://github.com/Circuit-Stitch/Janitor/blob/main/CONTEXT.md) — the
  glossary. Secret Set, Entry, Value, Environment, Application, and the
  Aligned / Drift / Gap states.
- [THREAT-MODEL.md](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/THREAT-MODEL.md)
  — what Janitor defends against, and what it explicitly does not.
- [ADR 0035](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0035-swiftui-macos-shell-over-uniffi.md)
  — why this shell exists and how it reaches the Rust core.
- [ADR 0036](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0036-three-repos-core-slint-shell-macos-shell.md)
  — why the shells live in their own repositories.

Decisions specific to this shell live in [docs/adr](docs/adr).

## Why a second shell

The macOS artifact was an unsigned `.dmg`, so Gatekeeper warned on first open. An
operator installed a tool that holds their AWS secrets by dismissing a warning that it
could not be trusted.

Three things blocked the App Store. Slint is used under its GPLv3 option, and GPLv3
forbids the further restrictions the App Store terms impose. There was no Xcode project,
and the upload needs one. The App Store requires App Sandbox, which breaks the loopback
OAuth listener.

The license half is settled. Dropping Slint took Slint's GPL out of this build, and the
core then relicensed to Apache-2.0, because nothing in it ever depended on Slint.

A native shell answers all three, and two of the answers make the app better.
`ASWebAuthenticationSession` gives an ephemeral sign-in that isolates the Identity Center
portal cookie. `NSPasteboard` can mark a copied Value concealed, which the current
clipboard cannot.

## Status

Early. The shell renders the masked matrix, groups Entry rows by prefix cluster, reveals
one cell at a time on press and hold, and copies a Value to the pasteboard marked
concealed. It archives with the sandbox entitlement.

Applications are managed too. The Manage window adds, renames, and removes them, and its
guided Discovery wizard fills in a new Environment: the operator types a name and picks a
method, and the account, the role, and the Set are discovered. Global Settings holds the
Identity Center fields, the browse-region picker, and the read-write unlock.

It reads real AWS. `JanitorKit.xcframework` — the Rust core compiled for macOS, with
the UniFFI-generated Swift compiled into it — arrives as a SwiftPM binary target pinned
by URL and checksum. Xcode never compiles Rust. `JANITOR_MOCK=1` swaps the Provider for
the offline one, which makes no AWS call and holds Config in memory, so a demo run cannot
edit real Applications.

The framework is built and published from
[Janitor](https://github.com/Circuit-Stitch/Janitor). To work against a local build of
it, check that repository out beside this one, run its
`scripts/build-xcframework.sh`, and set `JANITORKIT_LOCAL=1` for both `xcodegen` and
`xcodebuild`. See `JanitorKit/Package.swift`.

Editing works too, behind the read-write unlock. A cell edit stages into a batch for one
Environment; the review dialog lists each edit by Entry name and byte count, never by
Value; and Apply sends the batch through the engine that leaves every Entry it was not
given alone.

The matrix is tested in two lanes: the layout arithmetic as plain functions, and the
rendered views against the running app through XCUITest. Bringing the Slint shell's view
tests over found three real defects — the comparison columns pushed the table out of its
pane, a released Value stayed on screen until it timed out, and the two bands of the
freeze pane were eight points out of step.

Still to come: the real core behind all of it.

## Architecture

The shell is thin. It renders state and sends intents. No auth, no AWS calls, no
comparison, no write logic — all of that stays in the Rust core, where it is tested.

```
Sources/
  JanitorApp.swift      the composition root
  Core/
    JanitorCore.swift   the one seam between the shell and the core
    CoreDefaults.swift  where that seam reaches JanitorKit, for every core at once
    JanitorKitCore.swift the real core: the Rust worker and the Config store
    KitTypes.swift      the names the shell writes, bound to the generated types
    StubCore.swift      scripted events, for the tests
  Model/
    AppModel.swift      the reducer and every piece of rendering state
  Views/                the windows, the matrix, the cells, the wizard, the log panel
    MatrixLayout.swift  the matrix's layout arithmetic, kept out of the views
  Platform/
    Pasteboard.swift    concealed and transient markers, and the timed clear
```

The boundary is the worker's command and event protocol. Commands go in and return
immediately; answers arrive on an `AsyncStream` of events. No `async` function crosses
it, so Swift never drives the Rust runtime.

Every pure rule the matrix depends on — prefix clustering, the name split, the type
badge, the state glyph, the drift badge, the error banner — is a function on
`JanitorCore`, implemented in Rust. The shell calls them. It does not reimplement them.
`CoreDefaults.swift` is the one place those calls land, so the shipping core and the test
fixture cannot answer differently. The tests in `Tests/JanitorTests` pin the rules
themselves.

Config is the core's too. `ConfigStore` holds the one copy, and every edit runs the Rust
rule before it saves: a blank Application name is refused, a duplicate Environment is
refused rather than overwritten, and a stored column width is never returned below the
layout floor.

What the shell does own is layout, and layout lives in `MatrixLayout` rather than inside a
`body` where nothing can reach it. How wide a comparison column is, where it stops
shrinking, how a drag on the ENTRY column tracks the cursor, which cluster header floats
at a given scroll offset — each is a function with a test.

## Security

The invariants are the project's, not this shell's, and the
[threat model](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/THREAT-MODEL.md)
states them. What this shell adds:

- **One cell reveals at a time**, because the model holds a single optional rather than
  a set. A reveal clears on release, on the window losing focus, and after ten seconds.
- **A reveal that arrives after the release is dropped**, so a slow round trip cannot
  flash a Value on screen after the operator let go.
- **A revealed cell excludes the window from other processes' screen captures**, and the
  window becomes shareable again the moment the reveal ends.
- **A copied Value is marked concealed, transient, and sensitive**, and the pasteboard
  is cleared after 45 seconds if nothing else has claimed it.
- **A Value being edited is drawn once, concealed**, in the editor that types it. The
  review dialog, the pending bar, and the log describe an edit by Entry name and byte
  count. Locking read-write mode again, or quitting, discards whatever was staged.
- **A revealed Value is read by VoiceOver.** macOS gates third-party accessibility behind
  an explicit permission grant and screen recording behind a separate one, so hiding one
  while the other stays open defends nothing. It would only make the feature unusable for
  a blind operator.
- **Read-only, and the worker is the authority.** The badge reads the worker's lock
  rather than a constant, and unlocking is a deliberate menu action.

## Entitlements

Three, and nothing else.

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | The Mac App Store takes sandboxed apps only. |
| `com.apple.security.network.client` | Outbound TLS to AWS. Without it every call fails with EPERM. |
| `com.apple.security.network.server` | The loopback listener that receives the OAuth code. IAM Identity Center rejects every redirect URI except a loopback one. |

No keychain group, no file exceptions, no hardened-runtime exceptions. Check that an
archive carries these three and only these three before every upload — an archive that
loses one still builds and uploads, and review rejects it days later. The CI section
below has the command, and says why it is a manual step.

## Build and run

Requires Xcode 26 or newer, macOS 15 or newer, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate        # Janitor.xcodeproj is generated and gitignored
open Janitor.xcodeproj
```

From the command line, in two lanes:

```bash
# Unit tests. No signing identity needed, and it finishes in about a second.
xcodebuild test -project Janitor.xcodeproj -scheme Janitor \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# UI tests. Launches the app and drives it, so it does need one, and it takes a minute
# and a half. It also moves the pointer and types, so it needs a real login session.
xcodebuild test -project Janitor.xcodeproj -scheme JanitorUITests -destination 'platform=macOS'
```

The two lanes are separate schemes on purpose. The UI tests drive the built app through
the accessibility tree, which needs a signed, launchable app; a fresh clone with no
certificate can still run everything in the first lane.
[ADR 0007](docs/adr/0007-the-slint-view-tests-become-two-lanes.md) records the split and
what each lane covers.

Run `xcodegen generate` again after editing `project.yml` or after adding a source file.

## CI

There is none right now. `ci.yml` is commented out in full and the workflow is disabled in
the Actions tab, so nothing in GitHub Actions builds this repository. Both halves are
needed: GitHub evaluates a workflow file on a push, and an empty one produces a failed run
rather than no run.

That workflow ran on a self-hosted runner, which is a virtual machine on the development
Mac. This repository is public, and a public repository should not be wired to that
machine. Xcode Cloud is the only lane now.
[ADR 0004](docs/adr/0004-ci-is-dispatched-to-the-self-hosted-mac-and-release-goes-through-xcode-cloud.md)
and its amendment record the decision. The workflow's own header holds the one-line `sed`
that brings it back.

Two checks it made are yours to run until then. The tests, with both `xcodebuild test`
commands above. And the entitlement set, after an archive:

```bash
codesign -d --entitlements :- path/to/Janitor.app
```

Exactly three must be there: `com.apple.security.app-sandbox`,
`com.apple.security.network.client`, and `com.apple.security.network.server`. A missing one
fails review. An extra one costs a review round trip.

## Release

Xcode Cloud builds, signs, and uploads. It owns the certificates, the provisioning
profile, and the App Store Connect key, so none of them are in this repository. There is
no release lane in GitHub Actions.

It runs no cargo. The Rust arrives as a prebuilt `JanitorKit.xcframework` from the
depot, pinned by URL and checksum. Building the core on every run would compile the AWS
SDK and a large C library from cold each time, with no cache.

`ci_scripts/ci_post_clone.sh` runs first and regenerates the Xcode project. Without it a
fresh clone has nothing to build. Xcode Cloud is now its only automated caller, so run it
by hand from a clean clone before a release to check it still works.

## License

[Apache-2.0](LICENSE), following the core it is built on. Copyright 2026 Circuit Stitch.

GPLv3 blocked the App Store, so the core relicensed
([Janitor ADR 0037](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0037-apache-2-0-replaces-gpl-3-0-only.md)).
Slint was never the cause for the core: it reaches only the Slint shell, and nothing
depends on that shell. `JanitorKit.xcframework` carries no Slint and no GPL crate.

The Slint shell in
[Janitor-slint](https://github.com/Circuit-Stitch/Janitor-slint) stays GPL-3.0-only,
because it does link Slint.

### Third-party notices

Janitor links 272 open-source packages, all permissive apart from one MPL-2.0 crate.
Their notices are in [Support/THIRD-PARTY-LICENSES.txt](Support/THIRD-PARTY-LICENSES.txt)
and the app shows them in its Acknowledgments window.

This build compiles no Rust, so it cannot work out what it links. The file is generated
from `Cargo.lock` in the core repository, published beside the framework zip, and
committed here whenever the JanitorKit version is bumped. See
[ADR 0008](docs/adr/0008-the-about-window-and-where-the-notices-come-from.md).
