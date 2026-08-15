# `tool/mutate` — the mutation harness

The **run** is a tool, not a gate — `flutter test` never invokes it, and it
costs a full suite per case. **`--check` is a gate** (#107): it starts no test
process, finishes in milliseconds, and is on Step 7's list.

```bash
node tool/mutate/run.mjs cases/41-marble.json           # every case
node tool/mutate/run.mjs cases/41-marble.json --only=A  # one group

node tool/mutate/run.mjs --check                        # every case file, no tests
node tool/mutate/run.mjs cases/41-marble.json --check   # one file
```

## Why it is committed

A claim like *"12 of 12 mutants died"* is a claim about a **measurement**, and
this repo already applies one rule to those, in `docs/agents/theflow.md`:

> the release plan is a claim about measurement, and a claim whose evidence
> cannot be re-run is one nobody can check.

Before this existed the claim was true and uncheckable. Three separate runners
were written from scratch in a single session — one per lens plus the main
thread — and **each one re-learned the same traps**, which is the argument for
the file rather than against it.

## What a case file holds

`cases/<issue>-<area>.json`. Each entry is a literal substitution:

| field | meaning |
|---|---|
| `group` | a letter, for `--only`. By convention: A layer 1, B layer 2, C the rasterizer, D whole-capability deletions |
| `name` | what the mutation *means*, not what it edits |
| `file` | repo-relative |
| `from` / `to` | literal text, never a pattern. `to` may be absent, meaning deletion |
| `expectEdits` | how many times it must apply. A different count is `NO MATCH`, not a result |
| `test` | narrow the run. Defaults to `spec.test`, and `null` means the whole suite |
| `runner` | which suite to run: `flutter` (default) or `node`. Defaults to `spec.runner` |

The default is the **whole suite** on purpose: several `marble` mutants are
killed by a file other than the obvious one, and a narrowed run would report a
survivor.

`runner: node` arrived with #51, whose logic is a `.mjs` under `tool/` and so is
invisible to `flutter test` — a suite the gate cannot reach is exactly where an
unkilled mutant would sit forever. A runner is a command **and** a way to count
the tests that ran: without the count, `NO TESTS` collapses into `SURVIVED` and
the third outcome below stops working. That is why adding one means adding both,
and why the `node` runner asks for TAP output rather than the default reporter —
the default prints its totals behind an `ℹ`, and a count that depends on a
non-ASCII character surviving a pipe on Windows is a count that can read 0.

## Five outcomes, not two

`killed` · `SURVIVED` · `NO MATCH` · `NO TESTS` · `BASELINE RED`.

The middle two are the ones that pay. A substitution that never applied is not
a survivor, and a green run over zero tests is not one either — folding either
into a verdict is how a report says the opposite of the truth in the one place
whose job is to say which mechanisms are unguarded.

The runner **caught itself** on the `NO TESTS` half the first time it ran: its
`cmd.exe` invocation was malformed, every case failed to start, and it reported
`NO TESTS` on all 32 rather than 32 survivors.

`BASELINE RED` (#45) is the same honesty one level up: before applying
anything, each (test, runner) pair the cases use is run once **unmutated**. If
that run already fails, no verdict is possible — "the suite exited non-zero"
is then true for a no-op edit, so every case would report `killed` whatever it
did and a survivor would be unrepresentable. #45 recorded 7/7 kills over a
tree whose README gates were deliberately red (the release plan orders docs
after the browser sweep) before the refuting lens noticed the report was
unfalsifiable; the runner now refuses instead, with exit 2.

Exit status is 0 only when everything was killed. A stale case is a failure, so
that nobody has to notice it in the log.

## `--check` is not a sixth outcome

It asks **one of the five, early and cheaply**. Whether a `from` still applies
is a string search; *printing* `NO MATCH` costs a full suite per case, because
the runner has to reach that case to say it. The two are four orders of
magnitude apart, and the harness used to charge the high price for both — so
the cheap question went unasked, and two cases rotted for months. One of them
had never applied at all, under a commit message claiming `13/13 mutations
killed` (#106).

`--check` and the run share `staleReason` rather than each implementing the
rule. Two copies would eventually disagree about what stale means, and the
copy nobody re-derived would be the cheap one on the gate.

**What a clean `--check` says, and what it does not.** It says every case still
points at its target. It says **nothing** about whether any mutant dies — that
still costs the run. Reading `110 checked · 0 stale` as coverage is the same
error as reading a stale case file as coverage, which is the error that bought
this flag. The output says so on its own line for that reason.

Three ways it fails, all of them stale in the same way: the substitution never
applies, it applies a different number of times than `expectEdits` says, or the
target file cannot be read at all (a case pointing at something deleted or
renamed — which reads as `0` unless the two are distinguished).

## What this harness structurally cannot measure

**A compile-time guarantee.** A mutation that fails to compile produces zero
tests, which the runner reports as `NO TESTS` — correctly, since it measured
nothing. So a claim of the form *"this cannot be got wrong, the compiler
refuses it"* can never appear here as a `killed`, and a case file that tried
would be a permanently red case.

Found in #59, whose exhaustive `switch (version)` is exactly such a claim: a
future selector value cannot be added without dispatching it. That is true —
verified separately, a non-exhaustive enum switch *expression* is an error in
both the analyzer and the CFE — but the evidence is a language property
asserted by hand, not a dead mutant. Say so when a commit leans on one.

## What a surviving mutant means

Three questions, from `docs/agents/lessons.md`, in order:

1. **Is the test weak?** → strengthen it.
2. **Is the mechanism unreachable from this variant's inputs?** → construct the
   input; do not delete the code (`#37`'s F.6.5 clamp was right and only its
   evidence was missing).
3. **Is the code reachable at all?** → delete it. `_coverRect` went this way in
   #41: nothing can build a filtered `<rect>`, so 32 lines came out.

Answer the third before writing a test, or you write a test for an input no
caller can produce.
