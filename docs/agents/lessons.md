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

### A row nobody can act on yet is a row nobody checks — again (#38, #41)

Second occurrence, and the first one's rule predicted it exactly. Hidden-state
**#11** said the default filter region is "-10% / -10% / 120% / 120% **of the
bbox**". It is of the **viewport** — SVG 1.1 §7.10, for percentages under
`filterUnits="userSpaceOnUse"`. For `marble`'s 80 x 80 viewBox that is
`(-8, -8, 96, 96)` rather than something around the blob.

The row had been wrong since it was written in #1, through six tickets, inside
the file whose job is to hold exactly this kind of fact. Nothing caught it
because nothing *could*: `marble` is the only variant with a filter and it was
unported, so no code read the number and no test rendered it. It was found in
the first hour of #41, by rendering the two readings in Chrome and seeing which
one the browser agreed with — they differ enormously (ink from 18.25 to 61.75
against a hard cut at 34…46).

**The rule this earns** is #38's, unchanged, and the point of recording it twice
is that it is now a pattern rather than an anecdote: a hidden-state row about
code that does not exist yet is a **hypothesis written in the same font as a
measurement**. Re-derive it from the reference when its ticket opens. What #41
adds is the *second* half — the row was not only wrong, it was wrong in a way
that would have been invisible even after implementing it, because for `marble`
both readings are inert: the region contains the mask, so the mask cuts first.
A wrong row can survive its own ticket. Construct the case that separates the
readings, or the row stays unfalsified.

### One sentence governed two values and the port applied it to one (#41)

`§15.7.2` says a filter's `userSpaceOnUse` values are in "the user coordinate
system in place at the time when the filter is referenced". #41's first pass
read that, applied it to `stdDeviation` — correctly, worth 27/255 — wrote a
doc-comment quoting the sentence, and then resolved the region's
`x/y/width/height` in **viewport** space three functions away. One clause, two
values, one of them honoured.

The completeness pass found it. Nothing else could have: the region is inert
for `square: false` (the disc mask has already removed everything the region
would), so three of the four `marble` goldens do not move when it is fixed, and
the fourth was already committed with the wrong picture in it.

Two things about the *shape* of the miss are worth keeping.

* **An internal inconsistency is a stronger signal than a spec disagreement.**
  The argument that found it was not "the spec says X" but "this file cites one
  sentence for one value and ignores it for its neighbour". That is checkable
  without re-reading the spec at all.
* **The calibration number went the wrong way, and that was correct.** Fixing
  the region took `marble-clara-square`'s worst edge from 5/255 to 11 (hard
  clip) and then 9 (antialiased). The 5 was the *feature not running*. Chrome
  clips that render by 23 pixels; the port clipped none. A metric improving
  when you delete a capability is #39's lesson, and this is its mirror — the
  metric getting worse when you *add* one.

**The rule this earns:** when a change applies a rule to one value, grep for
the rule's other subjects in the same commit. And when a reference-comparison
number moves the wrong way after a fix, ask whether the old number was measuring
the thing at all before treating it as a regression.

### A filter's units are the element's, not the canvas's (#41)

`marble` declares `stdDeviation="7"` and its blobs carry `scale(1.2)` or
`scale(1.3)`. The blur was implemented with sigma 7 in device pixels, which is
the reading every part of the code around it invites — the viewBox is 80, the
target is 80, one user unit is one device pixel, so 7 is 7.

It is not. §15.7.2 says `userSpaceOnUse` means the user coordinate system in
place *where the filter is referenced*, and an element's own `transform` is part
of that system. The blur is **8.4** or **9.1** device pixels.

What makes this worth recording is how it surfaced. The whole-scene calibration
was **interior 0** on three of four `marble` cases — which reads as agreement
and is not, because a blur leaves no 3x3-uniform pixel for the classifier to
call interior (hidden-state #42). The fourth case had a two-colour palette,
where `overlay` against an opaque backdrop **saturates** a region flat and
manufactures the uniform neighbourhood the statistic needs. So the bug was
visible on exactly one of four cases, through a mechanism unrelated to the bug,
and it showed up as 10 interior mismatches of 8/255 rather than as the 27/255
it actually was.

Isolating it took cutting one stage at a time — overlay off, blob 2 removed,
blob 1 removed, filter removed — until the unfiltered shape was shown to match
Chrome and the blurred one not to. Then a sweep of sigma against Chrome's fixed
render put the minimum at 8.5, and 7 x 1.2 = 8.4 named the cause.

**The rule this earns:** when a comparison against a reference is off by an
amount that is not obviously rounding, sweep the parameter you are least sure
of before touching the algorithm. A one-line unit error and a wrong kernel look
identical in a diff of the output, and only the sweep separates them. And a
statistic that reports agreement on 3 of 4 cases is not 75% right — check
whether it *could* have disagreed.

### A reasoned default was the worst value on the curve (#80)

The banded rasteriser shipped with a 4 ms slice, chosen by argument:
comfortably inside a 16.7 ms frame, so it cannot drop one. Measured in Chrome
against 2629 ms of uninterrupted work at 480 physical pixels:

| slice | total | worst stall |
|---|---|---|
| 4 ms | 10130 ms | 28 ms |
| 8 ms | 5450 ms | 23 ms |
| 16 ms | 5144 ms | 32 ms |
| 33 ms | 3407 ms | 47 ms |
| 100 ms | 2310 ms | 110 ms |

4 ms was the **worst available choice**, and not by a little. Every yield on the
web is a `setTimeout(0)` the browser clamps to about 4 ms, so a slice at the
clamp spends most of its wall time waiting rather than drawing. The reasoning was
sound and simply did not contain the fact that decided the answer.

8 ms also beats 16 ms on *both* axes, which no amount of reasoning would have
predicted either — the worst stall does not shrink with the slice, because one
scanline is indivisible and already costs milliseconds at that size.

**A default is a measurement, not a derivation.** Especially one whose units
belong to a platform the code does not run on while you are choosing it.

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

### The CRLF trap, and a restoration check that outlived its assumption (#39, #41)

Two failures in one mutation run, both of them the runner rather than the code.

* **Five multi-line patterns matched nothing.** Same cause as #39: the working
  tree is CRLF and the patterns were built from bare newlines. The runner said
  `NO MATCH` rather than folding them into either verdict — the #34/#36/#37 fix
  working — and they were re-run against the file's own line ending, read off
  the file instead of assumed. All three then died.
* **The restoration guard stopped the run on its first case, correctly and for
  the wrong reason.** It asked `git status --porcelain` whether the mutated file
  was clean. That was right when it was written, because the files under test
  were untracked; by #41 they were tracked *and* legitimately modified as part
  of the work in progress, so `git status` was dirty by design and the guard
  could not tell a mutation from the change it was testing. Replaced with a
  direct comparison against the bytes the runner itself saved, which answers
  exactly the question being asked.

**The rule this earns:** a guard's *premise* ages like everything else. "The
tree is clean" was a proxy for "the mutation was backed out", and the proxy
stopped tracking the thing the moment the file's status changed. Prefer a check
that compares against what you are actually asserting — here, the saved
original — over one that infers it from a tool whose answer depends on
unrelated state.

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

### A probe that returns "no difference" three times is usually the probe (#41)

Three facts had to be pinned before `marble`'s rasterizer could be written: does
the filter region clip the *source* or only the output, what backdrop does
`mix-blend-mode` see, and does `color-interpolation-filters` change anything.
The first probe answered **no** to all three. Two of those answers were the
probe's fault and one was real:

* the colour-space case sampled the **exact midpoint** of a symmetric
  black-to-white ramp — the one x where sRGB and linearRGB agree by symmetry;
* the blend case used a blue backdrop and a green source, and
  `overlay(blue, green)` **is** blue, so the "blended" pixel equalled the
  unblended one by arithmetic. The probe's own printed expectation said so and
  it was read past.

Rebuilt with a **discrimination control** in every case — a companion input
that must come out different, printed beside the result — all three questions
answered cleanly, and one of the three original answers survived: the region
really does clip the output only. The colour-space answer also survived, but for
a reason the first probe could not have supported: a *flat-colour* source is
genuinely space-independent, because only its alpha varies and alpha is not
gamma-encoded. The control (two colours inside one filter) differs by 60/255,
which is what makes that a finding rather than a coincidence.

**The rule this earns:** a probe that reports "no difference" has two possible
causes and only one of them is about the subject. Every negative result needs a
control that produces a *positive* one in the same run, or it is not a
measurement. This is #37's "run the wrong pictures through it" applied one stage
earlier — to the instrument rather than to the gate.

### The runner caught itself, on the outcome it exists for (#41)

`tool/mutate/` was written to make the test-trust gate re-runnable, with the
four outcomes five previous incidents had earned. Its first full run reported
**`NO TESTS` on all 32 cases**.

Nothing was wrong with the mutations. `flutter` is a `.bat`, so it cannot be
`execFile`d directly, and handing `cmd.exe` a multi-part argv gets Node's
escaping applied on top of cmd's own — every invocation died with "The syntax
of the command is incorrect" before a single test started.

A two-outcome runner would have reported **32 survivors**: 32 mechanisms
declared unguarded, on a sacred surface, in the report whose entire job is to
say which ones are. The fix was one line — build the command string and quote
it here, which is #39's *prescription* rather than its prohibition; what that
incident caught was an argv array being concatenated unquoted by someone else.

**The rule this earns:** the third and fourth outcomes are not bookkeeping for
unusual cases, they are what makes the tool safe to believe on its *first* run,
before anyone has calibrated it. A harness whose failure mode is "reports the
opposite of the truth" has to be able to say "I did not measure anything" —
and it has to say it in the exit status, not only in the log.

### Closing a fan-out gap on one axis leaves the next axis open (#59)

The entry below records `size` being compared to upstream on `marble` only.
Widening it per variant closed that — and the completeness pass then measured
that the fix had moved the hole rather than removed it. With the widened
section still running **one name, one palette and `square: false`**, two arms
could be broken with all 677 tests green:

- honour `size` only when the name is `Clara Barton`;
- drop `size` whenever `square` is set.

Both survive because the second axis never varies *alongside* the first. And
the **String** half of `size`'s public type was worse: covered on `marble`
alone, against the package's own 80-render rather than upstream's, with the
upstream half supplied by a probe that had been deleted after it ran — which is
two of this repo's own rules at once (a fixture that agrees with itself, and a
claim whose evidence cannot be re-run).

`sizePassthrough` is now `variant × name × square`, each at both sizes, and
`sizePassthroughStrings` carries the String half for all six.

**The rule this earns:** the previous entry said the unit is "the prop varies
on every path that carries it". That was still one axis short. A prop is
covered where it varies **on a path something else varies on too** — otherwise
the fixture proves the prop reaches the output, never that it survives contact
with the rest of the input. Closing a coverage gap is the moment to ask which
axis the fix *froze*.

### Two lenses predicted nine survivors and all nine survived (#59)

The completeness pass ran as two lenses over the same material with opposite
jobs — one hunting gaps, one attacking the *evidence*. Between them they
proposed nine mutations the committed 14-case set was claimed to cover, each
with a prediction. **All nine survived**, including two the case file's own
notes said were guarded.

What makes it worth recording is the shape of the miss. Fourteen mutants had
died an hour earlier, and the conclusion drawn from that was "the dispatch is
covered". The fourteen were all mutations *I* thought of, and they shared a
blind spot with the tests I had written moments before — both were built from
the same mental model of what could go wrong. A green mutation run says the
tests kill the mutants someone imagined; it cannot say the imagination was
complete.

Two of the nine then turned out to be **inert rather than defective**, and only
running them showed which: a re-export leak that a `show` clause had already
made impossible (measured both ways — `SvgNode` is undefined at the barrel with
the `show`, and resolves without it), and an iteration-order swap that no unique
key set can observe. Both were dropped from the permanent case file rather than
kept, because a case that cannot die makes the runner's non-zero exit
meaningless — the guard for each moved to the property that *can* fail.

**The rule this earns:** on a surface that is about to be published, the
mutation set you wrote alongside the tests is not independent evidence about
those tests. Buy the second opinion, brief it on the *proof* rather than the
code — and when its findings survive, sort them into "unguarded" and "already
impossible" by running them, because those two look identical in the report.

### A prop compared to upstream on one variant is compared on none of the rest (#59)

Third occurrence of #37's rule, and the first where the gap was *created* by a
later change rather than shipped with the prop.

`sizePassthrough` was added in #33 precisely because "a prop the matrix never
varies is a prop nobody has compared to upstream". It rendered `marble` at 40
and at 80. That was enough while `size` was an argument to six separate builders
with six separate parity files, and stopped being enough the moment #59 put a
dispatch in front of them — because a dispatch has six places to drop the
argument and only one of them had a second number to disagree with.

Measured, before it was widened: hardcoding `size: 80` on the `ring`, `beam`,
`pixel`, `sunset` or `bauhaus` arm left **all 677 tests green**. Five of six arms
could discard the caller's size in silence. The main matrix renders at exactly
80, `sizePassthrough` was `marble`-only, and the string-size case was `marble`
too — so nothing in the suite ever asked the other five to change size.

The fix is #37's, applied one level down: the section is keyed `<variant>|<size>`
and generated for all six. Regenerating changed **only** that section — `renders`,
`squareRenders`, `maskIdentifiers`, `derivedIdentifiers` and `utilities.json`
came back byte-identical, which is also the first independent confirmation that
the harness reproduces its fixture on a second machine and a second Node major.

`test/fixtures_test.dart`'s guard had to move with it, and that is its own small
lesson: it asserted that *every* entry strips to one string, which was the whole
check while the section held one variant and would now be a **failure** — six
different avatars cannot strip to one. The premise aged, not the assertion.

**The rule this earns:** the unit is not "the prop appears in a fixture", it is
"the prop varies on every path that carries it". When a change introduces a new
fan-out over an existing prop — a dispatch, a router, a factory — the prop's
coverage has to fan out with it, and the way to find out is to hardcode the
argument on each branch and watch which ones nobody notices.

### A default nobody can reach is unreachable code, not a convenience (#59)

Nine mutations were run against the new dispatch and eight died. The survivor
changed `buildAvatarScene`'s default `variant` from `marble` to `beam` and the
whole suite stayed green — 677 tests, including a sweep that asserts the default
variant is `marble` against upstream's own render.

Not a weak test. `boringAvatarSvg` is the function's only caller and it always
passes `variant` and `square` explicitly, so the internal defaults were a second
copy of upstream's API defaults that nothing could read. The tempting fix — a
test calling `buildAvatarScene` without them — would have manufactured a caller
that does not exist in order to cover code no caller reaches.

Both are now `required`. Upstream's defaults belong on the surface a caller
meets, which is exactly one place.

**The rule this earns** is `#39`'s third question ("is the code reachable at
all?") arriving from a new direction: the previous instances were arithmetic no
*variant* could reach, and this one is a parameter no *caller* can reach. A
default is easy to read as harmless because it is not a branch — but it is a
value, and a value nothing reads is the same finding.

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

### A minimum over N repetitions is not a defence against a busy machine (#80 follow-up)

#80 left one question open: its absolute raster costs could not be reproduced,
and the session's own numbers contradicted each other — an AOT build measured
*slower* than JIT — so the costs were filed as unverified and the fix was
recorded as "re-measure on a quiet machine".

Re-measuring found that the premise was the defect. Eight runs, four JIT and
four AOT with the order alternated, each cell the **minimum of nine
repetitions** — and inside one process `marble` at 80 physical pixels measured
**39.3 ms** in the first table and **286.2 ms** in the second, minutes later.
Same binary, same code path, same run. The contention lasted longer than the
whole measurement, so every one of the nine repetitions met it and the minimum
inherited it in full. There was never an AOT-versus-JIT result to find; there
was a machine, doing something else.

What survived it was untouched. The banded-versus-sync ratio, measured back to
back inside each cell, came out at **1.00** across all forty cells — including
in the run whose absolute numbers were inflated tenfold. A 6.5x cost cliff
between neighbouring sizes reproduced exactly, twice.

**The rule this earns:** a minimum defends against *brief* interference and
nothing else, and it is dangerous precisely because it looks like it defends
against more. Before trusting an absolute number, ask how long the contention
would have to last to survive the estimator — if the answer is "less than the
run", the estimator is decoration. Prefer to state the claim as a **ratio whose
two halves are measured back to back**: the conditions they share divide out,
which is why the ratios here were reportable from data whose absolute values
were not. And carry a **control** that the mechanism predicts will not move; a
dip with no control is an observation, a dip beside a flat control is an
attribution.

### A row nobody can act on yet is a row nobody checks (#38)

Hidden-state **#26** said "`ring`'s viewBox is **90**; the other five are 80".
`beam`'s is **36** — `avatar-beam.js:4`, `const SIZE = 36`, and all 80 of its
renders in the committed fixture say so too.

The row had been wrong since it was written. Nothing caught it because nothing
*could*: `beam` was unported, so no code read the number, no test rendered it,
and the one consumer that would have noticed — the golden generator, which the
row itself warns takes a per-variant size — had no `beam` case to generate. The
error survived four tickets inside the file whose job is to hold exactly this
kind of fact.

It was found in the first ten minutes of #38 by reading the reference, which is
the only thing that could have found it.

**The rule this earns:** the hidden-state list has two kinds of row — one
describing code that exists, and one describing code that does not yet. The
second kind is unfalsifiable until its ticket starts, so it is a **hypothesis
written in the same font as a measurement**. When a ticket opens a row's
territory, re-derive the row from the reference before using it; do not spend
the row as though it had been checked. And prefer to write such a row with the
`file:line` it came from, so re-deriving it costs one `grep` instead of a
survey.

### A guard can catch the capability the enumeration missed (#38)

#38's Step 1 read `avatar-beam.js` in full and listed five capabilities the
rasterizer lacked: cubics, stroked paths, `scale`, `rx` on a drawn rect, and
§9.2's independent clamp. All five were real. The list was still incomplete —
`<g transform>` needed to **compose** down to its descendants, and that was not
on it.

Nothing in the reading caught it, because the face group's `transform` looks
exactly like the element transforms three lines below it. What caught it was the
seam: `<g transform="…"> is not implemented and would change the picture if
ignored`, thrown by the container allow-list that #37 added for precisely this
element (hidden-state #30). The first `beam` render failed on it immediately.

The failure it prevented is the one #30 describes: allowing the attribute
without applying it draws the face 4.5 units off and unrotated, throws nothing,
and a golden freezes it. Note that the *cheap* fix — adding `transform` to the
allow-list to make the error go away — is exactly that failure. The guard is
only worth its cost if the allow-list entry and the implementation land in the
same change.

**The rule this earns:** a completeness pass is not the only thing that finds
gaps, and it is not the earliest. A seam that refuses everything it cannot
honour turns an enumeration miss into a *failing test on the first run* rather
than into a wrong picture. When such a seam fires on new work, treat it as a
finding with the same weight as a lens's — and never discharge it by widening
the allow-list alone.

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

### A pump cannot bridge two zones, and a hang is not a failure (#80)

The widget's Step 4 proof — the produced `ui.Image` bytes against the goldens —
could not be taken through `pumpWidget`, and finding that out cost four
experiments that are recorded here so nobody runs them a fifth time.

A raster started from `build()` lives in the test binding's **fake-async zone**
while `decodeImageFromPixels` completes on a **real** callback. Measured:

| arrangement | result |
|---|---|
| `pumpWidget` inside `runAsync` | deadlock — **7 minutes+, silently**, never failing |
| one `pump` after `runAsync` | `the image never arrived` (1 s) |
| two `pump`s after `runAsync` | hang again — 3m30 to "did not complete" |
| `decodeImageFromPixelsSync` | **"not implemented on Skia"** — Impeller only, and the test backend is Skia |

Three lessons, in order of how much they cost.

**A test that hangs is worse than a test that fails.** The seven-minute
arrangement stopped the whole file with no output; moving the pump out turned it
into a one-second failure. That is a gain even though the test still failed —
a gate you can read is a gate.

**The fix was in the code under test, not in the test.** The proof moved to
`rasterAvatarImage`, a function with nothing of the widget in it, called from
inside `runAsync` so the future is *created* in the zone that will resolve it. An
earlier attempt proposed a `@visibleForTesting` completion future on the widget;
that would not have worked, because a future the widget creates is created in the
other zone either way.

**An unprovable area grows quietly.** By the end of #80 four widget behaviours
had no test — the error path, the one-raster-at-a-time bound, dropping a stale
picture, and the widget-level leak — each individually reasonable to defer, and
together a statement that the widget's asynchronous half is structurally
untestable here. They are listed in `test/widget_test.dart`'s header for that
reason: a gap named four times in four places reads as four small compromises,
and named once in one place reads as what it is.

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

### Two paths that agree make the choice between them invisible (#80 follow-up)

The rasterizer keeps two integrators for a rectangle: an exact closed-form one
when the matrix is a translation, and the general polygon scanline otherwise.
They agree — deliberately, and that agreement is tested. It is also what makes
the branch between them undefendable by anything in the suite: with the fast
path forced off, **758 of 760 tests stayed green**, every committed golden
included, and the two that failed were the ones written that afternoon to catch
exactly this.

The consequence is not cosmetic. `pixel` is **6.5x** cheaper at 80 physical
pixels than at 81 because 80 is the one target where the branch is taken. A
refactor that stopped taking it would have made the cheapest variant six times
dearer, shipped, and left a clean suite behind it.

This is the sibling of "a suite can be green for a mechanism it never runs"
above, with the failure moved one step: the suite *does* run the mechanism, on
every golden. It cannot see which one ran, because seeing that was never what a
byte comparison was for.

**The rule this earns:** when a change installs a second path to the same
output, ask what would go red if the *wrong* one were chosen. If the answer is
nothing, the property is a performance property and a correctness suite is
structurally blind to it — pin it **structurally** (assert the shape the
resolver produced) rather than by timing, because a timing test on a machine
whose absolute numbers move by 7x under load is a flake generator. The two go
together: the same session that found this also found it could not have measured
its way to a stable assertion.

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

### Going asynchronous deletes guarantees nobody wrote down (#80)

The completeness pass on the banded rasteriser found a defect the 752-test suite
could not see, and it was not a new bug — it was a **removed guarantee**.

`_sync` fired `unawaited(_raster(key))` on every rebuild whose inputs differed.
That line was unchanged by the work. What changed was underneath it: the raster
used to be synchronous, so a second one could not start until the first
finished. Concurrency was structurally one, and *because it was structural, no
comment, test or doc recorded it*. Moving the work off the frame deleted it in
silence — an animated `size` now started a `compute` per frame, each holding its
own O(area) buffers, and on web each one claimed a slice of the single thread, so
the avatar actually being waited for arrived **later** the more superseded ones
were in flight.

The general shape: **synchronous code hands out serialisation for free, and free
things do not get written down.** When a call becomes asynchronous, the checklist
is not only "what can now interleave" but "what was true only because nothing
could". Ordering, single-flight, and the lifetime of anything captured before the
first `await` are all in that class.

It is also why the pass was worth buying on a change whose own tests were green:
this is invisible to a suite that asserts outputs, because every individual
output was still correct.

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
