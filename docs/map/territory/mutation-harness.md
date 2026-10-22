# mutation-harness

## What it is
`tool/mutate/` is the **test-trust gate made re-runnable**: it applies literal
substitutions (mutants) to the source, runs the suite, and reports whether each
mutant died. A claim like "12 of 12 mutants died" is a claim about a
measurement, and a claim whose evidence cannot be re-run is one nobody can
check. The **run** is a tool (a full suite per case, nobody schedules it); its
**`--check`** half is a gate — first in the Step 7 block, a string search that
starts no test process (#107). See [gates](gates.md).

## Governing decisions
**None.** No ADR. The rules are scars recorded in `run.mjs`'s header and
`tool/mutate/README.md`, with incidents in `docs/agents/lessons.md` (Step 3).

## Design model
**The test-trust gate it automates.** Turn the fix off and watch the test go
red. Until #41 that was a throwaway script every time — three separate runners
were written from scratch in one session, each re-learning the same traps. To
revert a file by hand, use `git stash push -- <file>` / `git stash pop`,
**never `git checkout -- <file>`** (it destroys uncommitted work) — house rule.

**Case files** — `tool/mutate/cases/<issue>-<area>.json`, each entry a literal
substitution: `group` (A layer 1, B layer 2, C rasterizer, D whole-capability
deletions), `name`, `file`, `from`/`to` (literal, never a pattern; absent `to`
= deletion), `expectEdits`, `test` (default the **whole suite** — several
`marble` mutants die in a file other than the obvious one), `runner`.

**Five outcomes, not two**: `killed` · `SURVIVED` · `NO MATCH` · `NO TESTS` ·
`BASELINE RED`.
- `NO MATCH`: a substitution that never applied (or applied a different number
  of times than `expectEdits`, or whose file cannot be read) is not a survivor.
  The repo has been burnt by this five times (#34, #36, #37, #39, #41 —
  attributed).
- `NO TESTS`: a green run over zero tests is not a survivor. The runner caught
  itself on this the first time it ran (malformed `cmd.exe` invocation, 32 ×
  `NO TESTS` rather than 32 survivors).
- `BASELINE RED` (#45): each (test, runner) pair is run once **unmutated**
  first; if it already fails, every case would report `killed` whatever it did.
  #45 recorded "7/7 killed" over a tree whose README gates were deliberately
  red; the runner now refuses, exit 2.
- Exit status 0 only when everything was killed; a stale case is a failure.

**Runners.** `flutter` (default) or `node` (#51: the watcher's logic is a
`.mjs` that `flutter test` cannot see — a suite the gate cannot reach is where
an unkilled mutant sits forever). A runner is a command **and** a way to count
tests that ran; without the count `NO TESTS` collapses into `SURVIVED`. The
`node` runner asks for TAP output because the default reporter's totals sit
behind a non-ASCII `ℹ` that can read 0 through a Windows pipe.

**Other rules in `run.mjs`'s header**: literal `split`/`join`, never a regex;
argv as an array, never shell-joined (a shell-joined `--name "a b c"` ran the
whole file and reported a **false kill**, the worse direction, #39); read the
file's own line ending (`toFileEndings`) — a pattern typed with the wrong
ending comes back `NO MATCH`, which is the outcome that exists for it; verify
restoration against the saved bytes, not `git status` (#41); assert the tree is
untouched before starting (two measuring lenses in one worktree, #39).

**`--check` is not a sixth outcome** — it asks `NO MATCH` early and cheaply,
sharing `staleReason` with the run so the two cannot disagree about "stale".
A clean `--check` says the cases still point at their targets; it says
**nothing** about whether any mutant dies. Two cases matched nothing for months
— one since the day it was written — under a commit message claiming `13/13
mutations killed` (#106).

**What it structurally cannot measure: a compile-time guarantee.** A mutant
that fails to compile produces zero tests → `NO TESTS`. #59's exhaustive
`switch (version)` is such a claim; its evidence is a language property
asserted by hand, not a dead mutant — say so when a commit leans on one.

**A surviving mutant**, in order: is the test weak (strengthen it)? is the
mechanism unreachable from this variant's inputs (construct the input — #37's
F.6.5 clamp)? is the code reachable at all (delete it — `_coverRect` in #41,
32 lines)? Answer the third first.

**Input bounds:** case files are committed JSON; the run is bounded by their
count (115 at HEAD) × one suite each.

## Code
- `tool/mutate/run.mjs` — `toFileEndings`, `staleReason`, the runner table,
  baseline check, restoration check
- `tool/mutate/README.md`
- `tool/mutate/cases/` — measured with `node tool/mutate/run.mjs --check` on
  2026-10-22: **115 checked · 0 stale**. Per file: `110-pixel-snap` 5,
  `41-marble` 32, `43-drawing` 1, `43-title` 8, `45-pixel-index` 7,
  `51-watch` 10 (`runner: node`, `test: tool/watch/diff.test.mjs`),
  `58-scaling` 9, `59-dispatch` 22, `64-invalid-colours` 8, `95-colour4` 13.

```bash
node tool/mutate/run.mjs --check                        # the gate half
node tool/mutate/run.mjs cases/41-marble.json           # 32 cases
node tool/mutate/run.mjs cases/41-marble.json --only=A  # one group
node tool/mutate/run.mjs cases/51-watch.json            # 10 cases, runner: node
```

## Reference behaviour
**None** — it measures this repo's own tests.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — group A
  (layer 1) cases are the re-runnable evidence that the sacred surface's tests
  can fail.

## Blast radius
- Every territory a case file targets — a refactor that renames or rewrites a
  `from` string makes the case stale and reddens [gates](gates.md)' first line;
  rewrite the case in the same change. Sites: `rg -o '"file": *"[^"]*"' tool/mutate/cases | sort -u`.
- [upstream-watch](upstream-watch.md) — `51-watch.json` runs `diff.test.mjs`
  under the `node` runner; a change to that test's TAP output breaks the count.

## Known holes / open
- **Nobody schedules the run.** `--check` proves targets, not kills; the last
  recorded kill counts are per-issue claims in commit messages.
- **`run.mjs`'s header is partly stale**: "Three outcomes, not two" (there are
  five) and "The working tree is CRLF (`core.autocrlf=true`)" — a Windows
  checkout fact; on macOS the worktree is LF. The code (`toFileEndings`) reads
  the file's own ending, so behaviour is right.
