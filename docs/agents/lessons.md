# lessons — war stories, indexed by theflow step

Per-incident evidence for the rules in [`theflow.md`](theflow.md). Each entry is
a *precedent*: a rule that caught (or failed to catch) a real defect, with the
issue number that proves it happened.

**Empty so far — this repo has no incidents.** That is the honest state, not an
oversight.

Do not seed this file with anticipated problems. The enumerated JS/SVG semantics
traps live in `theflow.md`'s **hidden-state list**, which is *pre-incident*
enumeration. A row moves here — with its issue number — the first time it
actually catches something in this codebase.

## Step 1 — verify references against real source

### A file existing is not the feature existing (#1 → closed #8)

Working #1, the variant roster was drafted from the **git tree file listing** —
`avatar-turbulence.js` is there from v1.2.0 to v1.5.2, so `turbulence` went into
the plan and got its own ticket (#8), sized as the project's heaviest item
(`feTurbulence`'s spec PRNG plus `feDisplacementMap`).

Reading `avatar.js` — the **dispatch** — killed it. `turbulence` appears **zero
times across all 28 tags**. Its blob SHA never changed (`4055bd`) for the same
reason: nothing referenced it. No caller could render it, so there is no upstream
output to reproduce and not even a layer-1 fixture can be generated. #8 closed as
not planned.

The same read produced three more corrections the file listing could not have
shown: `eye` is dispatched **only** at v1.2.0 though its file survives to v1.5.2;
`geometric`/`abstract` mean three different things by era (real variants → 
unreachable → deprecated aliases); and an unknown variant **degrades to the era
default rather than throwing**.

**The rule this earns:** for a port, the reference's *entry point* is the
authority on what exists. A component file tells you how something is
implemented, never whether it is reachable. Read the dispatch before the
components.

**And on sampling:** the first sweep read 14 of 28 tags and was about to be
called done. The exhaustive sweep is what makes "zero in every version" a fact
instead of a strong guess — for an enumeration that *is* the deliverable, sample
size is not a detail.

## Step 2 — mechanism / policy boundary

_(none yet)_

## Step 3 — TDD and the test-trust gate

### A tripwire that cannot trip reads as coverage (#34)

A test guarding "we deliberately did not port `getModulus` and `getAngle`" was
written as `expect(const <String>['jsHashCode', …], hasLength(6))` — a literal
asserting its own length. Adding either function would have left it green. It
looked like a decision under guard and guarded nothing.

Replaced with one that reads `utilities.dart` and asserts the declarations are
absent (and that the six real ones are present, so it fails on a moved or
emptied file rather than passing on a missing string).

**The rule this earns:** a test whose subject never appears in its own
assertions is not testing that subject. Mutate the thing it claims to protect
and watch it go red, or delete it.

### A mutation surviving means one of two opposite things (#34)

Seven mutations were run against the primitives; five went red. The two
survivors had *opposite* causes and needed opposite responses:

- **`getUnit`'s `index == 0` guard** — a real hole. No fixture entry used index
  `0`, because no upstream caller does. Fixed by widening the fixture to
  measure index `0` from upstream; the mutation now kills 10 assertions.
- **`getDigit`'s float division** — not a hole. Integer division is provably
  indistinguishable for non-negative input, so there was nothing to cover. The
  honest response was to prove the equivalence, record the validity condition,
  and pin the negative-input divergence with measured upstream values.

Treating the second like the first would have produced a test for an input no
caller can produce. Treating the first like the second would have left a real
divergence undefended.

## Step 4 — real round-trip proof

### A byte gate catches what a picture never shows (#36)

`pixel` emits its 64 tiles in a scattered DOM order — `x = 0, 20, 40, 60, 10,
30, 50, 70` across the top row, then column by column — and the tile at each
position takes a colour index that follows that order, not the grid.

Rewriting the table in reading order was run as a mutation. **The rendered
image is identical**: every tile still lands where it belongs with the colour it
had, because the coordinates travel with the index. Only the *serialisation*
moves. It broke 24 assertions — all of them layer-2 byte comparisons against
upstream's real output.

Nothing at layer 1 or layer 3 could have seen it. A pixel-only gate would have
shipped it.

**The rule this earns:** where the port reproduces a *document* and not only a
drawing, the document is part of the contract. Order, whitespace and attribute
presence are behaviour, and only a byte comparison against real output tests
them.

### A golden that agrees with itself proves nothing (#36)

The first golden was generated from the same code the test would run, so the
comparison was guaranteed to pass — it locks against *regression* and says
nothing about *correctness*.

What makes it evidence is the assertions written beside it: which tile covers
the centre pixel, that the four corners are cut by the circular mask, that some
pixels carry partial alpha at all, that `rx: 160` on an 80-wide rect clamps to
40. Those are checkable without any golden. The golden then freezes that
verified state.

Also added: a check that the three goldens are not the *same* image — a
generator bug writing one render three times would otherwise satisfy every other
assertion.

## Step 5 — adversarial completeness pass

### A suite can be green for a mechanism it never runs (#36)

Five mutations were run against the rasterizer and all five went red, so the
layer looked defended. A refuting lens then found **four wrong rasterizers that
passed the entire suite** — including one with the exact rect-coverage
calculation *deleted outright*.

Every one was invisible for the same reason, and it was not weak testing. It was
that `pixel` is an 8×8 grid of integer-aligned tiles under a **square** mask:

| Deleted mechanism | Why `pixel` cannot see it |
|---|---|
| exact rect coverage (`rowOverlap × colOverlap`) | a tile edge at a multiple of 10 makes that factor exactly 1 |
| `min(width/2, height/2)` in the `rx` clamp | on a square mask, `width/2` alone agrees |
| "only draw what is under the masked group" | nothing in `pixel` sits outside it |
| the `mask-type` guard | nothing ever declares a type but `alpha` |

The tracer bullet was chosen *because* it is the simplest shape — and the same
simplicity is what makes it a poor witness for the general machinery it
installs. The mutations that went red were the ones `pixel` exercises; the ones
that survived were the ones the next five variants exercise.

**The rule this earns:** when a slice installs machinery wider than the slice
itself, mutation-test the machinery against inputs the slice does not produce.
The five tests added here — a sub-pixel rect, a non-square mask, a shape outside
the mask group, a foreign `mask-type` — are all things `pixel` never creates.

A footnote on the run itself: one mutation appeared to survive re-testing and
had not actually been applied — a `perl` substitution that silently matched
nothing. A mutation whose application is not verified is not a mutation. The
re-runs now print the applied-edit count before the suite.

### The same edge case behaves differently per variant (#33)

Building the parity harness, the completeness check was "does the corpus cover
every input the hidden-state list names?" It did not: **`colors: []`** — entry #8
— was missing. Adding it looked like a one-line fix.

Rendering it revealed the entry itself was wrong. #8 said "JS degrades where
Dart throws". Measured across all six variants × 20 names at v1.6.1:

- `marble`, `pixel`, `ring`, `sunset`, `bauhaus` — the `undefined` colour goes
  straight into a `fill`, React drops the attribute, the render succeeds;
- **`beam` throws.** It hands the same `undefined` to `getContrast`, which calls
  `.slice` on it.

So the port faces *both* failure modes on one input: crashing where upstream
degrades, and succeeding where upstream crashes. A rule written as "empty
palette degrades" would have been half wrong in a way the other half hides.

**The rule this earns:** a hidden-state entry describes a *mechanism*, and the
mechanism can reach different call sites with different tolerances. Before
trusting an entry, run it against every variant that touches it — the entry is a
hypothesis until it has been measured across its whole surface.

The harness now records a throw as data (`{"__throws": "TypeError"}`) rather
than dying, so upstream's crash is itself a reproducible fixture.

## Step 6 — surface sweep

### The hidden-state list is a hypothesis, and gets things wrong (#34)

Three entries were corrected by the work that consumed them, not by a later
audit:

- **#4** claimed a `~/` mutation "survives the whole suite". True when written;
  false an hour later, because the same change added the negative-input test
  that kills it. A claim about the *suite* rots whenever the suite moves.
- **#2** was stated as a live hazard. It is inert at v1.6.1 for exactly the
  reason #4 is — every reachable dividend is non-negative — and said nothing
  about it, so the two neighbouring entries described the same situation in
  opposite tones.
- **#8** described the empty palette reaching `colors[NaN]` and missed that
  `pixel` reaches the same `NaN` through a completely different route, its loop
  index. That one fires on **every** render rather than on an edge input, and a
  port following the list alone would have shipped it wrong.

**The rule this earns:** entries age against the code and against the tests.
Re-read the ones a change touches *as part of that change* — including the
sentences that were true when written.

## Step 7 — gates, release, downstream

### "0 warnings" shipped a 44 MB build artifact (#1)

`flutter pub publish --dry-run` reported **0 warnings** on an archive of
**13 MB** — for a package whose entire source is about 20 KB. The gate was green
and the package was wrong.

Cause: adding a root `.pubignore` **disables pub's git-based file listing
entirely**. `.gitignore` stops being consulted, so everything it excluded —
`build/`, `.idea/`, `*.iml`, `.dart_tool/`, `pubspec.lock` — starts shipping. A
single `flutter test` run had left a 44 MB `.cache.dill.track.dill` under
`build/`, and it went straight into the archive.

`../flutter_table_plus`'s bindings already record this exact trap. It was read
during setup, written into this repo's Step 6 surface list, and still walked
into — because `.pubignore` was authored as an *additive* list of extra
exclusions rather than as a *replacement* for `.gitignore`.

Fix: `.pubignore` now mirrors `.gitignore` in full, with the reason at the top
of the file. Archive went 13 MB → **5 KB**.

**The rule this earns:** a gate reporting zero problems is not the same as the
gate having checked the thing you care about. Read the dry-run's **file tree**
and its **archive size**, not just its warning count. And a `.pubignore` is a
replacement, never an addition.
