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

A native shell answers all three, and two of the answers make the app better.
`ASWebAuthenticationSession` gives an ephemeral sign-in that isolates the Identity Center
portal cookie. `NSPasteboard` can mark a copied Value concealed, which the current
clipboard cannot.

## Status

Early. The shell renders the masked matrix, groups Entry rows by prefix cluster, reveals
one cell at a time on press and hold, and copies a Value to the pasteboard marked
concealed. It archives with the sandbox entitlement, and CI asserts that.

It does not read real AWS yet. `JanitorKit.xcframework` — the Rust core compiled for
macOS — is not published, so the shell runs against `StubCore`, which serves the same
canned Applications the offline mock Provider serves. Four slices in
[Janitor](https://github.com/Circuit-Stitch/Janitor) gate the swap: moving the worker
into the core, adding the UniFFI boundary, granting a depot publisher tenant, and
publishing the framework.

Still to come: the Discovery wizard, the Manage window, Settings, the browse-region
picker, and the in-matrix cell edit.

## Architecture

The shell is thin. It renders state and sends intents. No auth, no AWS calls, no
comparison, no write logic — all of that stays in the Rust core, where it is tested.

```
Sources/
  JanitorApp.swift      the composition root
  Core/
    Protocol.swift      the command and event vocabulary, mirroring the Rust worker
    JanitorCore.swift   the one seam between the shell and the core
    StubCore.swift      canned data, until JanitorKit is published
  Model/
    AppModel.swift      the reducer and every piece of rendering state
  Views/                the window, the matrix, the cells, the log panel
  Platform/
    Pasteboard.swift    concealed and transient markers, and the timed clear
```

The boundary is the worker's command and event protocol. Commands go in and return
immediately; answers arrive on an `AsyncStream` of events. No `async` function crosses
it, so Swift never drives the Rust runtime.

Every pure rule the matrix depends on — prefix clustering, the name split, the type
badge, the state glyph, the drift badge, the error banner — is a function on
`JanitorCore`, implemented in Rust. The shell calls them. It does not reimplement them.
`StubCore` carries temporary copies, and the tests in `Tests/JanitorTests` pin those
copies to the Rust behavior so they cannot drift before they are deleted.

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

No keychain group, no file exceptions, no hardened-runtime exceptions. CI asserts the
archive carries these three and only these three, because an archive that loses one
still builds and uploads, and review rejects it days later.

## Build and run

Requires Xcode 26 or newer, macOS 15 or newer, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate        # Janitor.xcodeproj is generated and gitignored
open Janitor.xcodeproj
```

From the command line:

```bash
xcodebuild test -project Janitor.xcodeproj -scheme Janitor \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Run `xcodegen generate` again after editing `project.yml`.

## CI

There is none right now. `ci.yml` is commented out in full, so nothing in GitHub Actions
builds this repository.

That workflow ran on a self-hosted runner, which is a virtual machine on the development
Mac. This repository is public, and a public repository should not be wired to that
machine. Xcode Cloud is the only lane now.
[ADR 0004](docs/adr/0004-ci-is-dispatched-to-the-self-hosted-mac-and-release-goes-through-xcode-cloud.md)
and its amendment record the decision. The workflow's own header holds the one-line `sed`
that brings it back.

Two checks it made are yours to run until then. The tests, with the `xcodebuild test`
command above. And the entitlement set, after an archive:

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

[GPL-3.0-only](LICENSE), following the core it is built on. The license is under review
in [Janitor#102](https://github.com/Circuit-Stitch/Janitor/issues/102): dropping Slint
removed the cause of the GPL, not the license itself, and the xcframework is still
compiled from GPL crates.
