# Architecture decisions

Decisions specific to the macOS shell. Everything about the domain, the security posture,
and the core lives in
[Janitor's decision log](https://github.com/Circuit-Stitch/Janitor/tree/main/docs/adr).
Splitting a decision log fragments it, so nothing there is copied here.

The two that created this repository:

- [ADR 0035](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0035-swiftui-macos-shell-over-uniffi.md)
  — a SwiftUI macOS shell over the Rust core via UniFFI.
- [ADR 0036](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0036-three-repos-core-slint-shell-macos-shell.md)
  — three repositories: the core, the Slint shell, and the macOS shell.

## This repository

| ADR | Decision |
|---|---|
| [0001](0001-repository-layout-and-the-generated-xcode-project.md) | The Xcode project sits at the repository root, and how the entitlements reach the archive. Amended: the project is committed source, XcodeGen is gone, and the build settings live in `Config/*.xcconfig`. |
| [0002](0002-one-seam-to-the-core-and-a-stub-behind-it.md) | One protocol is the whole seam to the core, with a stub behind it until the framework is published. Amended: the framework landed, and the stub is a test fixture with no rules of its own. |
| [0003](0003-the-reveal-lifetime-and-the-pasteboard-markers.md) | How long a reveal lives, and what marks a copied Value on the pasteboard. |
| [0004](0004-ci-is-dispatched-to-the-self-hosted-mac-and-release-goes-through-xcode-cloud.md) | CI is dispatched to the self-hosted Mac. Release goes through Xcode Cloud. Amended: the self-hosted lane is off, and Xcode Cloud is the only lane. |
| [0005](0005-manage-is-a-window-settings-is-a-settings-scene.md) | Manage is a real window bound to one Application. Settings is a Settings scene. The wizard's three states are one property. |
| [0006](0006-editing-a-cell-stages-a-batch-and-the-value-is-never-drawn-twice.md) | A cell edit stages a batch for one Environment. The review dialog shows names and sizes, never Values. |
| [0007](0007-the-slint-view-tests-become-two-lanes.md) | The Slint view tests become layout arithmetic in `MatrixLayout` and XCUITest against the running app. |
| [0008](0008-the-about-window-and-where-the-notices-come-from.md) | Janitor draws its own About window. The third-party notices are generated in the core and travel with the framework. |
