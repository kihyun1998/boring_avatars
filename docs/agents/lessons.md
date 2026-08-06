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

### A mutation can survive because the *inputs* are degenerate (#37)

Two of twelve mutants survived the whole suite, for the same reason and neither
of them a test-quality problem in the ordinary sense.

- Swapping `cy` for `cx` where the rasterizer reads a `<circle>` changed
  nothing. `ring`'s only circle is at (45, 45). So is `bauhaus`'s. **No variant
  in the six could ever catch a transposed coordinate.**
- Removing the clamp on F.6.5's centre square root changed nothing. All six of
  `ring`'s arcs have *horizontal* chords, and a horizontal chord makes the
  radicand exactly zero in float64 — never the −1e-16 the clamp exists for.

Both are the #34 rule ("a mutation surviving means one of two opposite things")
in its second form: the mechanism was unreachable *from this variant's inputs*.
The tempting reading — "unreachable, so delete it" — is wrong for the second
one: a parameter search found `r = 1/7` with an angled chord where `lambda`
computes as exactly `1.0`, F.6.6 therefore does not fire, and the unclamped
`sqrt` returns `NaN` that kills the whole render. The guard was right; only the
evidence was missing.

**The rule this earns:** when a mutant survives, ask whether the *variant* can
reach the mechanism before asking whether the test is weak. If it cannot,
construct the input rather than deleting the code or shrugging — and if you
cannot construct one, say so with the search you ran.

### A substitution that matches nothing reads as a surviving mutation (#34, #36, #37)

Third occurrence. The mutation runner captured a `perl` error message into the
variable it was going to print as an edit count, so every failed substitution
printed `SURVIVED <-- gap` — the exact opposite of the truth, in the report
whose whole job is to say which mechanisms are unguarded.

**The rule this earns:** print the match count, and **parse it strictly**. A
count that can be a error string is not a count. The runner is now a Node script
doing literal `split`/`join`, which cannot mistake a pattern for a regex, and it
prints `NO MATCH — the mutation never applied` as its own outcome rather than
folding it into either verdict.

### A runner can report a false *kill*, which is the worse direction (#39)

Fourth and fifth occurrence of "a substitution whose application is not verified
is not a mutation", both in one session, and the first one in the direction
nobody had seen.

- **The false kill.** The runner spawned `flutter test` with
  `execFileSync(cmd, args, {shell: true})`, which concatenates the arguments
  **unquoted**. `--name "reproduces upstream byte for byte"` arrived as five bare
  words, the filter never applied, the whole file ran, and a mutation the
  filtered group is provably blind to was reported **killed**. The claim being
  measured was "the byte sweep cannot see this", so the runner returned the
  opposite of the truth on the one question it was asked.
- **The five silent no-matches.** The working tree is CRLF. Every multi-line
  pattern was written with `\n` and matched nothing; every single-line one
  applied. The runner said `NO MATCH` rather than folding them into either
  verdict, which is the #34/#36/#37 fix working — the pattern was then
  translated to the file's own line ending.

The first is worse than the recorded direction. A false survivor sends you
hunting a hole that is not there and costs time; a false kill **retires a real
question as answered**.

**The rule this earns:** a mutation runner needs three outcomes, not two, and
the third has to cover *green over zero tests* as well as *no substitution*. It
now parses the test count out of the run and refuses to call a filtered-to-empty
run a survivor. Quote arguments yourself when the shell is doing the joining.

### An output-neutral change is invisible to every test that looks at output (#69)

#69 split one `null` into three states — an absent `fill`, `fill="none"`, and a
colour notation the rasterizer cannot read — all of which paint nothing. The
ticket's own premise was that not one byte moves, and none did: 493 tests green,
14 goldens unchanged.

Six mutations were run. Five died. The sixth was the measurement that mattered:
**reverting `resolvePaint` to its pre-#69 one-liner survived the entire suite**,
because the old code and the new code give identical answers on every one of the
four states. So the eight seam-level tests written for this change — `none`
draws nothing, absent draws nothing, unreadable draws nothing — are *pins*, not
discriminators. Every one of them passes against the code the ticket exists to
replace.

What does discriminate is the vocabulary's own type-level assertions
(`readColourDeclaration('none')` is `NoneColour` and not `UnreadableColour`) and
the `<stop>` side, where absent and unreadable already had different answers.
Those are the mutations the ticket asked for, and they are the only ones that
could have been asked for.

**The rule this earns:** when a change is deliberately output-neutral, the
regression suite cannot be its evidence — it is *guaranteed* to pass, which is
the ticket's acceptance criterion, not a test result. Say which assertions would
survive a full revert before claiming the change is covered, and put the
discriminating power where the change actually is. The same run that proves the
goldens did not move proves nothing about whether the new code is reached.

### A concurrent agent in the same worktree invalidates a measurement (#39)

Two completeness lenses ran in parallel against one checkout. One of them left
three mutations applied in `lib/src/raster/transform.dart` while the other was
measuring, so that run's first pass reported two `NO MATCH`es and a `SURVIVED`
against a baseline that was already wrong — the "substitution that matched
nothing" trap in a new form: *a substitution applied on top of an unknown
baseline*. The affected lens re-ran everything with a `git status` assertion
before and after each case, and the debris was isolated with `git stash push`
(never `git checkout --`, the house rule) rather than discarded, so it could be
inspected before being dropped.

**The rule this earns:** a mutation run asserts the tree is clean before it
starts, not just afterwards. Parallel read-only lenses are cheap; parallel
*measuring* lenses share one mutable working tree and are not.

## Step 4 — real round-trip proof

### A bar can be recorded, believed, and never run (#33 → #37)

The layer-3 calibration bar — "interior 0, antialiased edges ≤1/255 against a
real Chrome render" — was written into the bindings in #33 and treated as
satisfied ever since. #37 built the harness and ran it for the first time.

It fails. Not only for `ring` (worst edge 66–101/255) but for **`pixel`**, which
merged in #36 (71/255). Nobody had lied; the bar had simply never been executed,
and four tickets of work read as though it had.

The failure is also not ours. Measured against areas that need no browser:
Chrome's `<circle r=40>` is 32 px² short of πr² — **0.13 px inside the true
circle** — and its `<path>` half-disc of r=38 is 17 px² short. Ours are within
0.02. Chrome antialiases straight edges to about 0.003 px and *approximates
curves*, so a ≤1/255 bar against it cannot be met by anything except a matching
approximation.

Two separate things went wrong and they are worth separating. The bar was never
run; and the bar, as written, was unmeetable in principle for half the shapes in
the package. Only the first is a process failure.

**The rule this earns:** a bar that has never produced a number is a plan, not a
gate — record *when it was last executed and what it measured*, not just its
threshold. And before believing a reference, measure the reference: the outside
opinion that needed no negotiation here was πr², not Chrome.


### A gate can be blind to a whole capability, not just to a defect in it (#39)

`bauhaus` added a stroked `<line>` to the rasterizer, and the Chrome
calibration reported **interior mismatches 0** on all three of its cases. That
was written into the commit as evidence that "the transform composition, paint
order and stroke geometry are right".

The refuting lens deleted the entire stroked-line capability — the rule simply
not drawn — and re-ran it. **Interior mismatches: still 0, on all three.**
Reproduced independently before it was believed.

The cause is not a weak tolerance. `_isEdge` calls a pixel interior when its
3×3 neighbourhood is uniform in the reference, and a 2-unit stroke at 1 device
pixel per unit has no such pixel anywhere — every pixel of the band has a
neighbour outside it. So the classifier files 100% of the rule as edge, and the
interior count cannot move whatever happens to it. The worst *edge* delta does
move, 71 → 174–255, but the recorded bar is ≤1 and the baseline is already 71
because of Chrome's own curve error (#27), so no threshold separates a missing
shape from a browser artefact.

`flutter test` killed the deletion, and killed three other wrong pictures the
lens built (every shape shifted 0.3 px, the disc 3% small, the rule one unit
thick). The Chrome run killed none of them.

**The rule this earns:** hidden-state #42 said the interior/edge split is
"defeated by a gradient". It is defeated by anything a 3×3 window does not fit
inside, which now includes every stroke this package will draw — `beam` adds
two more. A statistic that *cannot* respond to a change is worse than a loose
one, because it reads as coverage. Before quoting an aggregate as evidence,
delete the thing it is supposed to be evidence about and check that it moves.

### A tripwire's power can come from corpus membership rather than construction (#39)

`bauhaus`'s `isSquare` is `getBoolean(numFromName, 2)` with no loop index, so
all four elements share one flag and only element 1 is ever read. Threading `i`
through it — the change a reader is most likely to make — survives the whole
100-render byte sweep. A dedicated layer-1 test was written for it, the
mutation died, and the comment beside it explained why with a number.

The number was for the wrong condition. Two different thresholds sit here and
they had been collapsed into one:

- the **sweep** is blind while element 1's flag holds, which needs
  `hash ≢ 99 (mod 100)` — 0.2 expected over 20 names, 0 observed;
- the **tripwire** trips when any of `hash…hash+3` crosses a hundred, which
  needs `hash mod 100 ∈ {97, 98, 99}` — 0.6 expected, **2 observed**
  (`single-char`, hash 97; `punctuation`, hash 218314798).

So the test was passing on two corpus names. Delete them and it goes green and
silent — the #34 failure again, one rung further out: not a test whose subject
never appears in its assertions, but one whose subject appears only because of
what a *fixture* happens to contain.

Fixed with three constructed names, one per residue. `aaK` (hash 96299) is the
sharp one: it is the class where element 1's own flag moves, so it is the name
that would have closed the hole at layer 2. The blindness was never the port's —
it was the corpus's, and one more name would have ended it.

**The rule this earns:** when a test's discriminating power depends on a corpus,
say which entries carry it and add a constructed witness beside them. And check
which condition your number is about — two nearby thresholds that differ by one
digit of arithmetic will both look like "the obvious one".

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

### A new guard can make a whole group pass for the wrong reason (#37)

`pixel_raster_test.dart`'s scene helper built a `<mask>` with no `id` and a
`<g mask="url(#m)">` pointing at it. That was harmless until #37 added a check
that the reference names a mask that exists — after which **every assertion in
that group was satisfied by the reference throwing**, not by the thing each test
names. A mutation removing an unrelated guard stayed green, which is how it was
found.

The lesson is not "write better fixtures". It is that tightening a seam
*retroactively changes what every existing test proves*, and a test suite going
from green to green is exactly the transition nothing reports.

**The rule this earns:** after adding a guard that fires early, re-run the
mutation set — not just the suite. A test that was passing for the right reason
yesterday can be passing for the new guard's reason today, and only a mutant
distinguishes the two.

### A true observation is not therefore a useful gate (#37)

The layer-3 bar against Chrome fails, and the reason is Chrome's, not ours
(hidden-state #27). The obvious next move — and the one proposed — was to
replace it with a gate built from what the failure actually looks like: every
differing pixel is an antialiased boundary pixel, interior mismatches are zero,
and the total ink differs by under 1%. All three were measured and all three
held.

The proposal was refuted by rendering deliberately broken variants through it:

| what was broken | interior | boundary-only | ink | the proposed gate |
|---|---|---|---|---|
| every path shifted 0.3 px | 0 | 0 | 0.18% | **passes** |
| centre disc 3% small | 0 | 0 | 0.24% | **passes** |
| mask applied per shape | 0 | 0 | −0.45% | **passes** |
| flattening 64× coarser | 0 | 0 | 0.24% | **passes** |
| sweep flags swapped | 486 | 1134 | 0.24% | caught |

One of five. The observation was true and stayed true for a shape moved
sideways, which is precisely the defect it was supposed to catch — translate a
shape and its interior is untouched and only its edges move.

`flutter test` kills all five, and always did. The Chrome comparison was never
what was holding the line; the in-repo geometry assertions (πr², centroid,
measured radius) and the goldens were.

**The rule this earns:** before proposing a check as a gate, run the wrong
pictures through it. A property that holds for the correct output tells you
nothing until you know it *fails* for the incorrect one — and "it only differs
at the edges" is the description of a half-pixel error as much as of a
resolution artefact. This is the #34 rule again, applied to a gate that was
being designed rather than one already written.

### A value nothing reads is not a value that works (#37, #40, #39)

Three times now, the hardest arithmetic in a change turned out to be unreachable
from any real input, and every time the whole suite was green over it.

- `#37` — every arc upstream writes has a chord equal to its diameter, so
  F.6.5's centre offset is exactly zero and the `largeArc` flag multiplies it.
  Two mutants on the sign rule survived.
- `#40` — **every gradient this package rasterises is vertical.** `sunset`
  writes `x1 = x2 = 40`, so `dx` is zero and the x half of the projection is
  multiplied away. Replacing both `x1` and `x2` with `-12345` changed not one
  pixel of any render. Three mutants survived, including one that deleted the
  x-term outright.

- `#39` — **every transform any variant writes is `translate · rotate`.** So in
  `Affine.multiply` the left operand's `c` and the right operand's `b` are never
  both non-zero, and two of the six terms are dead: deleting `c * other.b` from
  slot `a`, or `b * other.c` from slot `d`, left all 465 tests green. Two more
  in the same file: the one-argument `translate(x)` form (§7.4's `ty = 0`
  default), which no variant and no test wrote, and `<line>`'s zero-length
  branch, which was asserted on the helper but never driven through
  `rasterizeScene`.

Neither is a defect and neither is fixable by finding better upstream input:
the reference will never produce the case. What closes it is a **constructed**
one — a diagonal gradient, a horizontal one, a reversed axis, two rotations
composed, `translate(5)` — written knowing that no variant will ever exercise it.

`#39` also produced the fourth answer's first clean instance: a guard that was
**unsatisfiable**, not merely unreached. `parseTransform` ended with
`if (!found && source.trim().isNotEmpty) throw` — and `!found` implies the
source trims to empty, so the conjunction can never hold. Every unreadable
prefix already throws inside the loop; measured over `''`, `'   '`, `'\t\n'`,
`','`, `'x'`, `'()'`, `'translate'`, `'translate(1 2) x'`. Deleted, like #40's
redundant gradient clamps, rather than tested.

The same pass also found two guards that no mutation could kill because they
*did nothing*: the gradient's explicit `pad` clamps were already implemented by
the interpolation factor's own clamp. Those were deleted rather than tested.

**The rule this earns:** a surviving mutant asks a third question beyond "is
the test weak?" and "is the variant degenerate?" — **is the code reachable at
all?** Answer it before writing a test, because the three answers have three
different fixes: strengthen, construct, or delete.

## Step 5 — adversarial completeness pass

### Two lenses on the same material disagreed usefully (#37)

Both lenses read `ring`, the rasterizer and the reference. The gap-hunting one
found a `<g transform>` walking through unchecked and a `url(#…)` fill drawing
nothing; the refuting one found those *and* three the first missed — the mask
being applied per shape rather than to the composited group, a subpath after `z`
being welded onto the previous contour, and the `largeArc` flag being
dead-valued across the entire corpus.

More useful than the extra findings: the refuting lens measured that the
*existing* proofs were weaker than claimed. All nine of `ring`'s band samples
sat on the column `x = 45`, so a centre disc rasterised 3% small and a 0.3 px
global shift both passed every one of them — "verified independently of any
golden" was false in the direction that mattered. It also measured that
`largeArc` and F.6.5's centre offset are unreachable from any real input,
which no amount of corpus coverage would have revealed.

Both were briefed on both corpora, so each finding arrived with a direction
already attached rather than as an errand.

**The rule this earns:** on a sacred surface, the second lens's job is not more
findings — it is to measure what the first pass's evidence actually covers.
Ask it to break the *proof*, not the code.


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
