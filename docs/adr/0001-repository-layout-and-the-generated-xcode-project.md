# Repository layout and the generated Xcode project

**Status:** accepted, 2026-08-21

Implements [ADR 0035](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0035-swiftui-macos-shell-over-uniffi.md)
and [ADR 0036](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0036-three-repos-core-slint-shell-macos-shell.md)
in the repository they created. Both were written before this repository existed, so
two details in them describe a layout that no longer applies.

## Context

ADR 0035 placed the Xcode project at `apple/project.yml`, because the shell was going to
live inside `Janitor` beside the Rust. ADR 0036 then moved the shell into its own
repository. An `apple/` subdirectory in a repository that holds nothing else names a
distinction that is gone.

`AnimalSpin-iOS` is the sibling that already has this shape: `project.yml`, `Sources`,
`Support`, `Tests`, and `ci_scripts` at the root, with the `.xcodeproj` generated and
gitignored.

Two build-system details also had to be settled before the first archive.

## Decision

**The Xcode project is generated at the repository root.** `project.yml` is the source.
`Janitor.xcodeproj` and `Support/Info.plist` are generated and gitignored.
`ci_scripts/ci_post_clone.sh` regenerates them, and Xcode Cloud runs it before it reaches
`xcodebuild`. GitHub Actions runs the same script, so the path Xcode Cloud depends on is
exercised on every push.

**The entitlements path is set as a build setting, not through XcodeGen's `entitlements`
key.** That key *generates* the entitlements file from a `properties` block. Given a
`path` and no `properties`, it writes an empty plist over the file at that path. The
first archive built this way was signed with an empty entitlements dictionary, which the
Mac App Store rejects. Setting `CODE_SIGN_ENTITLEMENTS` directly leaves the hand-written
file alone.

**The entitlements file holds the three sandbox and network keys and nothing else.** The
research spec's listing also carried `com.apple.application-identifier` and
`com.apple.developer.team-identifier` built from `$(TeamIdentifierPrefix)`. Signing
injects both from the provisioning profile. Writing them by hand pins a team identifier
into the repository and produces a malformed identifier in an ad-hoc archive.

**The deployment floor is macOS 15.** The freeze pane needs the header band to track the
matrix body's horizontal scroll offset, and `onScrollGeometryChange` is what reads that
offset. It arrived in macOS 15. Without it the alternative is the offset-plumbing the
Slint shell spends about 400 lines on.

**The default actor isolation is `nonisolated`.** Xcode 26 defaults new projects to
`MainActor`, and the UniFFI-generated Swift does not compile under it. Pinning
`nonisolated` now means the setting is already right when `JanitorKit` arrives. The model
carries an explicit `@MainActor`.

**The bundle identifier is `com.circuitstitch.apps.janitor`**, which is what packaging
already declares and what Circuit Stitch applications use.

## Consequences

- **The generated project is not in the repository, so a clone cannot be opened
  directly.** `xcodegen generate` comes first. The README says so, and Xcode Cloud proves
  a cold clone reaches an archive on every release build.
- **The entitlement set is asserted, not just its presence.** All three keys, and the
  count exactly three. An archive with a fourth entitlement invites a review question
  that costs a round trip, and an archive missing one is rejected days later. This ran in
  CI when it was written. ADR 0004's amendment turned that lane off, so it is a manual
  check before an upload until something else carries it.
- **macOS 14 is not supported.** macOS 15 shipped in September 2024, and Janitor is a
  developer tool, so the floor is not a real constraint. Dropping to 14 means writing the
  scroll-offset plumbing by hand.
- **`apple/build-rust.sh` from the research spec has no home here.** Xcode Cloud runs no
  cargo, so there is no build script phase and no Rust toolchain requirement.
