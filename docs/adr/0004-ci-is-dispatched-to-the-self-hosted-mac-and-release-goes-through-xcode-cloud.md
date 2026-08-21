# CI is dispatched to the self-hosted Mac, and release goes through Xcode Cloud

**Status:** accepted, 2026-08-21; **the self-hosted lane was turned off 2026-08-21**
(see the amendment at the end — `ci.yml` is commented out, and Xcode Cloud is the only
lane).

Follows
[ADR 0035](https://github.com/Circuit-Stitch/Janitor/blob/main/docs/adr/0035-swiftui-macos-shell-over-uniffi.md),
which put the release on Xcode Cloud. This settles the other lane.

Adopts the split
[WirelessOrderTelegraph-kmp's ADR-0010](https://github.com/Circuit-Stitch/WirelessOrderTelegraph-kmp/blob/main/docs/adr/0010-the-push-gate-runs-on-linux-and-apple-is-dispatched.md)
records, with one difference that matters.

## Context

Every job in this repository needs a Mac. There is no Linux half to put on a hosted
runner, because there is no Rust here and no Kotlin — the shell is Swift and the core
arrives prebuilt.

Circuit Stitch has one macOS runner: `deferno-ios-vm`, a Tart virtual machine on the
development Mac, registered under the `deferno-ios` label in the `apple-builders`
organisation runner group. Its scripts live in `Circuit-Stitch/deferno-runner`.

Two properties of that runner decide the trigger, and both are already recorded.

**It is not running.** The host cannot carry the guest and an interactive session at
once, so it is started by hand before a build and stopped after. A job triggered by a
push would sit queued until somebody booted it, and GitHub cancels a queued job after
twenty-four hours. A gate that reports nothing is worse than no gate: a green check that
never ran looks the same as one that did.

**Its safety rests on what can reach it.** It is a virtual machine on the machine the
work is done on. `deferno-runner`'s own decision record states the arrangement is safe
only while the workflows targeting that label are dispatched rather than triggered by
contributed code.

**The difference from WOT: this repository is public.** ADR-0010 lowered the second risk
by noting that WirelessOrderTelegraph-kmp is private, so the fork pull request cannot
happen there — while adding that visibility is one setting away from changing and no
workflow file would notice. Here it has already changed. A `pull_request` trigger on this
repository would run a stranger's code on the development Mac.

## Decision

**One workflow, `ci.yml`, on the self-hosted runner, triggered by `workflow_dispatch` and
a nightly schedule.** No `push`, and no `pull_request`.

It checks the two things App Review would otherwise catch days later. A cold clone must
reach an archive through `ci_scripts/ci_post_clone.sh`, which is the same script Xcode
Cloud runs. And the archive must carry exactly the three entitlements — all three
present, and the count exactly three.

**There is no release lane in GitHub Actions.** Xcode Cloud builds, signs, and uploads to
App Store Connect. It owns the certificates, the provisioning profile, and the App Store
Connect key, so none of them are in this repository or in its secrets.

**`ci_post_clone.sh` installs XcodeGen only when it is missing.** Xcode Cloud's runner is
ephemeral and has none. The self-hosted runner is persistent and already has one, so it
skips a network round trip on every run. Both lanes run the same script, which is what
keeps the Xcode Cloud path exercised.

## Considered options

- **A hosted `macos-26` runner on every push.** Always available, and it gates every push.
  Rejected on cost: GitHub bills macOS minutes at ten times the Linux rate, and avoiding
  that is the reason the self-hosted runner exists. This was the first version of the
  workflow and it is what this ADR replaces.
- **Push to `main` on the self-hosted runner.** Safe, since only collaborators can push.
  Rejected on availability: most pushes would produce a queued job and no answer, and a
  cancelled queue reads as a failure rather than as "the runner was down".
- **`pull_request` on the self-hosted runner.** Rejected outright. The repository is
  public, so this runs fork code on the development Mac.
- **A second runner registered to this repository.** Keeps `deferno-runner`'s
  "repository level, never organisation level" rule intact. Rejected as more moving parts
  than the problem needs, for the same reason ADR-0010 rejected it.

## Consequences

- **This repository must be added to the `apple-builders` runner group.** It holds
  `deferno-kmp` and `WirelessOrderTelegraph-kmp` today. Until `Janitor-macos` joins them,
  a dispatched run queues and is cancelled after twenty-four hours.
- **Boot the guest before dispatching.** `~/Code/deferno-runner/macos/ship.sh`.
- **A push gets no automatic check.** The nightly finds a break within a day if the guest
  is up, and a dispatch finds it the moment somebody asks. Neither is a push gate.
- **A fork pull request gets no check at all.** That is the correct posture for a public
  repository with a self-hosted runner, and it means a contributed change is verified by
  a maintainer dispatching a run after reading it.
- **Revisit if the runner becomes a service rather than a hand-started VM.** Push on
  `main` becomes reasonable the moment a queued job is no longer the normal case.

## Amendment (2026-08-21): the self-hosted lane is off

`ci.yml` is commented out in full. Nothing in GitHub Actions builds this repository.

The Decision rested on keeping contributed code away from the runner by choosing the
triggers carefully. `workflow_dispatch` and `schedule` do that. The objection is broader.
A public repository should not be wired to a virtual machine on the development Mac at
all. One repository setting, or one careless trigger added later, is the whole distance
between the safe arrangement and a stranger's code on that machine.

Xcode Cloud is the only lane now. It builds, signs, and uploads. It runs
`ci_scripts/ci_post_clone.sh` first, so a cold clone is still proven to reach an archive
on every release build.

The entitlement assertion is what goes uncovered — all three present, and the count
exactly three. Run it by hand before an upload. The steps survive in the commented
workflow.

The file is commented rather than deleted. One `sed`, printed in its header, restores it
byte for byte.

Commenting it out is half the disable. GitHub still evaluates a workflow file on a push,
and an empty one produces a failed run titled after its path rather than its name. The
commit that turned the lane off left exactly one of those in the run history. So the
workflow is disabled in the Actions tab as well:

    gh workflow disable ci.yml --repo Circuit-Stitch/Janitor-macos

Re-enabling takes both halves, in that order: uncomment, then `gh workflow enable`.

Two consequences above are moot while this stands. This repository does not need to join
the `apple-builders` runner group, and there is nothing to boot before a dispatch.

Revisit when the runner stops being a virtual machine on the development Mac, or when a
hosted macOS runner is worth its cost.
