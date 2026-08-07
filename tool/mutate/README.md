# `tool/mutate` — the mutation harness

A **tool, not a gate**. `flutter test` never runs it.

```bash
node tool/mutate/run.mjs cases/41-marble.json           # every case
node tool/mutate/run.mjs cases/41-marble.json --only=A  # one group
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

The default is the **whole suite** on purpose: several `marble` mutants are
killed by a file other than the obvious one, and a narrowed run would report a
survivor.

## Four outcomes, not two

`killed` · `SURVIVED` · `NO MATCH` · `NO TESTS`.

The last two are the ones that pay. A substitution that never applied is not a
survivor, and a green run over zero tests is not one either — folding either
into a verdict is how a report says the opposite of the truth in the one place
whose job is to say which mechanisms are unguarded.

The runner **caught itself** on the second of those the first time it ran: its
`cmd.exe` invocation was malformed, every case failed to start, and it reported
`NO TESTS` on all 32 rather than 32 survivors.

Exit status is 0 only when everything was killed. A stale case is a failure, so
that nobody has to notice it in the log.

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
