# Editing a cell stages a batch, and the Value is never drawn twice

**Status:** accepted, 2026-08-21

Closes the last of [Janitor#99](https://github.com/Circuit-Stitch/Janitor/issues/99)'s
three open questions, and gives `Command::ApplyEdits` its first producer in either shell.

## Context

Everything under the write was already built and tested. The write engine changes the
Entries it was given and leaves the rest of the Set as it found it. The worker holds the
lock and refuses a write without making a call. `summarize_edits` describes a pending edit
by Entry name and byte count. What was missing was the thing that produces an edit.

Two facts shape what that thing can be. The engine writes one Set at a time, so a batch
commits against one Environment. And a new Value is the only secret the operator types
into Janitor, which makes it the one secret with a lifetime the shell controls rather than
the core.

## Decision

**A cell edit stages. It does not write.** The context menu on a cell offers Edit Value
and Remove Entry when read-write mode is on. Both add to a batch. A bar above the matrix
says how many edits are staged and for which Environment, and it is the only way to the
review dialog, so a staged batch cannot be forgotten.

**One batch, one Environment.** Staging into a second column is refused with a message
naming the first. Letting a batch span columns would suggest the whole thing commits or
fails together, and it would not.

**The review dialog is the last look, and it shows no Values.** One line per edit, from
`summarizeEdits` in the core: Entry name, and either a byte count or "removed". A byte
count is enough to check that the right thing was staged. Apply sends the batch.

**A Value is drawn once, in the editor, concealed.** A `SecureField` with an explicit
reveal toggle, because an editor left open is a Value on screen for as long as the
operator is away. The field is cleared when the sheet closes. Opening the editor also ends
any live reveal — the old Value beside a field for the new one is two Values on screen at
once.

**Locking again discards the batch.** Keeping Values in memory behind a lock the operator
just closed is the opposite of what closing it asked for. Quitting discards it too.

**A refused write keeps the batch.** A conflict means the Set changed and nothing was
overwritten; a retry should not mean typing every Value again. Only a committed write
clears it, and that also refreshes the matrix so it shows what is there rather than what
was.

**The two refusals have different titles.** "Edit not staged" and "Nothing was written"
are different events. A batch that survives a refused write reads as lost if the alert
claims the edit never staged.

## Consequences

- **This shell can write before the Slint one can.** The rail existed in both; the
  affordance exists here. `Command::ApplyEdits` had no producer anywhere until now.
- **v1 still ships read-only.** Read-write mode is off every launch and is never
  persisted, and the worker refuses a write regardless of what the UI offers.
- **A staged Value lives longer than a revealed one.** A reveal ends on release, on focus
  loss, or after ten seconds. A staged Value lives until applied, discarded, locked out,
  or quit. Nothing renders it in that window, and nothing logs it, but it is the longest a
  Value is resident in the shell and the reason discarding is wired to so many exits.
- **The Diagnostic Log records the shape of every edit and none of the content.** Staging,
  applying, and every outcome are logged by Entry name, Environment, and byte count.
