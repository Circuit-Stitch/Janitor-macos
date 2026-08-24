# One seam to the core, and a stub behind it

**Status:** accepted, 2026-08-21

## Context

`JanitorKit.xcframework` does not exist. Four slices in `Janitor` produce it: move the
worker into the core, add the UniFFI boundary, grant a depot publisher tenant, publish
the framework. Until they land, the shell has no core to talk to.

The view work does not depend on any of that. The matrix, the freeze pane, the cells, the
reveal gesture, the log panel, and the menu bar are net-new SwiftUI regardless of what
sits underneath. Waiting would leave the largest part of the shell unbuilt for no
benefit.

The risk in building first is writing a model layer against a guess, then rewriting it
when the real types arrive.

## Decision

**One protocol, `JanitorCore`, is the whole seam.** Everything below it is Rust and
everything above it is view code. It has two halves: `send` plus an `AsyncStream` of
events, and a set of synchronous pure functions.

**The asynchronous half mirrors the Rust worker's protocol exactly.** Command and event
names match the Rust variants, so swapping in the generated types is mechanical. This
slice mirrors the seven commands and twelve events the masked matrix drives. The
Discovery, write, and update halves arrive with the rest of the surface.

**The pure functions are the tested Rust seams, called rather than copied.** Prefix
clustering, the Entry-name split, the type badge, the state glyph, the drift badge, the
error banner, and the main-pane choice are all functions on `JanitorCore`.
Reimplementing any of them in Swift would move a tested rule into an untested layer.

**`StubCore` is the only implementation today.** It serves the same canned Applications
the offline mock Provider serves, and it carries local copies of the pure rules. It makes
no network call and holds no real secret material.

**The stub's copies are pinned by tests.** `StubCoreTests` asserts each rule against the
behavior the Rust seam has: the cluster label is the longest common prefix cut at a
separator and suffixed with `*`, the zebra stripe restarts under each header, a grouped
row drops the prefix its header shows, the drift badge appears only on the selected
loaded row. The tests catch a copy drifting, and they keep their assertions when they
are repointed at the real implementation.

**No `async` function crosses the seam.** A command returns immediately and its answer
arrives as an event. Swift never drives the Rust runtime, which is what keeps the
Provider's single-thread ownership sound.

## Considered options

- **Wait for the xcframework.** Rejected: it blocks the view work, which is most of the
  shell and depends on none of it.
- **Write the views against the generated types directly.** Not possible — they do not
  exist yet.
- **Skip the protocol and let the model hold the stub directly.** Rejected: the swap
  would then touch the model rather than one file.
- **Let the shell compute the clustering and the name split itself.** Rejected. They are
  tested in Rust, and a Swift reimplementation would be a second definition with no test
  tying it to the first. The stub's copies exist only because there is nothing to call
  yet, and the tests say so.

## Consequences

- **`StubCore` is temporary and should be deleted, not grown.** Every rule added to it is
  a rule that has to be reconciled with Rust later.
- **`Protocol.swift` is deleted when `JanitorKit` lands.** The views and the model were
  written against those names and keep compiling.
- **The stub's canned data has to track the mock Provider's.** It reproduces the same
  four Applications and the same Payments API matrix, so what the shell shows before and
  after the swap is recognizably the same thing.
- **The reveal round trip is real, not faked.** The stub answers a reveal asynchronously,
  so the release race the model guards against actually happens in development.

## Amendment 2026-08-24 — the framework landed, and the stub became a fixture

`JanitorKit.xcframework` exists. `JanitorKitCore` drives the real Rust worker and is
what the app runs on. The swap went the way this ADR planned: the views and the model
were written against names the generated types also carry, so replacing the hand-written
vocabulary was mechanical.

**`Protocol.swift` is deleted.** The generated types are what the shell uses.
`KitTypes.swift` is what is left of it: three typealiases, a few conformances SwiftUI
needs, and the `Usize` conversions. `SecretMethod` is still not called `Method`, for the
reason this ADR gave — a type named `Method` shadows the Objective-C runtime's `Method`
for the whole module.

**`StubCore` carries no copies of the rules any more.** It scripts events and holds an
in-memory `ConfigStore`, so every Config rule and every pure rule it answers is the Rust
one, reached through `CoreDefaults`. Prefix clustering, the name split, the glyphs, the
badges, and the pane copy were about 250 lines of Swift; they are gone. `StubCoreTests`
became `CoreRulesTests` and kept its assertions, which now pin the real rules rather than
guarding a copy against them.

**`CoreDefaults.swift` is where the seam meets the kit.** The pure rules are default
implementations on `JanitorCore` itself. The Config calls are default implementations for
anything that has a `ConfigStore`. Both cores inherit both sets, so there is one place a
call reaches Rust and no way for two implementations to answer differently.

**The seam changed shape in four places, because the Rust protocol is what it is.**
`loadApp` carries the Application rather than an index — the worker holds no Config.
`reveal` and `copyValue` carry the row's key, so a reveal is addressed by what it names
rather than by where it sits. There is no `endReveal`: a reveal is one round trip and the
core keeps no pending state, so dropping the plaintext in the model is the whole of it.
`applyEdits` carries the Mapping, because the write engine needs the account, the region,
the Set, and the role.

**A test never touches a real config file.** Both the fixture and `JANITOR_MOCK=1` build
their store with the in-memory constructor, which runs every rule and stops before the
write. The UI tests set `JANITOR_MOCK=1` for the same reason, and because a launched app
would otherwise open a browser for a real sign-in.
