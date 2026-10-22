# version-selectors

## What it is
`BoringAvatarsVersion` — the public, required choice of which upstream release a
render reproduces — and the two version-dependent questions `buildAvatarScene`
answers from it: whether the document carries a `<title>`, and which *drawing*
the selector uses (today only `pixel`'s colour index differs). It also holds the
scope of the package: which upstream releases exist, which are in scope, and how
they are grouped into selectors. One selector value per package release, one
release per distinct **output** state; a shipped value is frozen.

## Governing decisions
No ADR. Four maintainer rulings, plus a derived extension of the fourth. The
release → selector → covered-versions table itself lives in `CLAUDE.md`
principle 3 and is copied elsewhere — see
[selector-coverage-copies](../invariant/selector-coverage-copies.md).

### Scope boundary — the ladder is git tags, not npm versions (maintainer, 2026-07-28)
A product call, shown the npm survey below, recorded with its **validity
condition** so the investigation is not re-run and the consequence is not later
mistaken for a defect.

The npm registry publishes **69 versions** collapsing to **38 distinct code
states** — more than double what the git tags describe. The package tracks
**git tags only**, valid **as long as it does not claim npm-version-level
fidelity**. Three concrete divergences follow:

- **npm `1.2.1` ships `0.1.4`-era code** (identical content hash): only
  `abstract` and `geometric`, default `name: "abcdefg"`, while git `v1.2.0`
  already had beam/eye/marble/ring/turbulence. A version number is not a point
  on the code's timeline.
- **npm `0.1.3`, `1.8.0`, `1.9.0` shipped no JavaScript at all** — `main` points
  at a `build/` directory absent from the tarball. Nobody could have run them.
  `v1.8.0`/`v1.9.0` as *git* states are still reachable: their content equals
  `v1.10.0`'s.
- **27 npm versions predate the first git tag** (`0.0.1` … `1.1.2`, from
  2020-12-30): real code, out of scope.

Eight of the 38 npm states exist only as minified webpack UMD bundles with no
tag and no `sourcesContent`; recoverable at a cost, and avoiding that cost is
part of why the boundary sits at tags. **If a user reports "your `v1_x` does
not match my npm install", this is the answer, not a bug report.** Moving the
boundary is a scope change and goes back to the user.

### Scope boundary — the ladder starts at v1.6.1, not v1.2.0 (maintainer, 2026-07-28)
Superseding the earlier "walk the whole history from v1.2.0" call. A product
judgement, theirs to reverse. **Shown:** weekly npm download share per state,
and the cost of the second hash era. `v1.6.1` is where `getNumber` is replaced
by `hashCode` — a cut along an **algorithm boundary**; the coverage number is a
consequence, not the criterion.

| Starting at | Coverage of weekly npm downloads | Hash functions | Reachable variants | Tag states |
|---|---|---|---|---|
| v1.2.0 | 99.79% | 2 | 11 | 17 |
| **v1.6.1** | **99.64%** | **1** | **6** | **8** |

The nine states below v1.6.1 total **0.14%** — roughly 360 downloads a week,
of which `v1_6_0` alone is 19. Supporting them would pull in `getNumber`, which
walks code points where `hashCode` walks code units, so the eras share no
helper (hidden-state #6, [upstream-utilities](upstream-utilities.md)), and a
second `getContrast` return format (`'black'`/`'white'` vs hex). **Out of scope,
not deferred**: no placeholder issue exists and none should be opened.
Re-entering scope is a fresh decision by the user.

### The states in scope — grouped by output, not by source (maintainer, 2026-07-29)
Superseding "one selector per distinct source tree". A product judgement,
theirs to reverse. **Shown:** the four measurements below, and that grouping by
source gives 8 selectors where grouping by output gives 3.

> **"꼭 버전마다 하나씩 만드는건 아니고 사용자 입장에서 결과물이 같으면 묶어서
> 하는거임. 문법은 상관없어. 결과물이 중요."**

**Two upstream versions share a selector when a caller gets the same thing out
of them.** Source identity is neither necessary nor sufficient — `1.11.1` and
`1.11.2` have different source trees and identical output, while `1.11.0`
shares `1.11.1`'s intent and differs in what it emits. Measured, re-runnable
by [version-grouping](version-grouping.md) (`tool/versions`, `npm run group`):
fifteen versions × six variants × four names under four readings of "the same":

| What is compared | Groups |
|---|---|
| the raw bytes | 6 |
| internal ids normalised (`id`, `url(#…)`, `mask`, `filter`) | 4 |
| ids normalised **and** `<title>` set aside | 3 |
| ids normalised, `title` forced on | 3 |

The `v1_7_0` → `v1_10_1` boundary is one variant wide: over six names, `pixel`
differs on 6 of 6 and the other five are byte-identical.

**`1.11.0` is skipped (maintainer, 2026-07-29).** It spreads its own props onto
the `<svg>` element (hidden-state #37) —
`<svg … width="80" height="80" colors="#92A1C6,#146A7C,#F0AB3D,#C271B4,#C20D90" name="Clara Barton" …>`
— measured on all six variants; upstream fixed it in `1.11.1` by destructuring
the props it consumes. Under the output criterion it would need its own
selector, and supporting it would mean **reproducing the junk attributes**,
since a selector promises what that version emits. A caller pinned to `1.11.0`
is told it is unsupported rather than given a neighbour's output. If reversed,
the state is `v1_10_1` plus the leaked attributes and nothing else. Found by
grouping rendered output, which a source diff had classified as inert.

**`1.8.0` and `1.9.0` need no selector of their own** — inside `v1_7_0`; their
npm tarballs contain no JavaScript (verified by installing them), so no user
has ever run them, and their evidence is that their `src/lib` tree *is*
1.10.0's (fixture `groupProof.bySourceTree`, all `bd8b225d…`).

So the eight in-scope tag states map to **two render paths and three byte
paths**, and the three byte paths are the three selectors.

*A correction this replaced:* an earlier note claimed the state count differs
per layer (2 values / 3 bytes / 2 pixels) and that all eight selectors should
be kept "so someone pinned to 1.8.0 can name it". Keeping a selector whose
output is byte-identical to its neighbour buys a name and costs a release; the
user ruled the name is not worth it. *(That superseded sentence survived ten
lines below its own correction until #43 — the section argued both sides at
once.)*

### Generated ids are not reproduced — the ruling, as an event (maintainer, 2026-08-13)
**Background (2026-07-29 measurement).** From 1.8.0 upstream names its mask with
React's `useId()`, whose value depends on the element's position in the render
tree. What that changes is two characters of an internal reference; shapes,
coordinates and fills are byte-identical, so the same name yields the same
avatar on every page. At `v1_6_1` the question does not arise: every id is a
literal, and the one that must not collide already carries the name
(`sunset`'s `gradient_paint0_linear_ClaraBarton`) while the one that does
collide is a mask identical for every avatar of that variant.

**Why it became a ruling:** #43 shipped `v1_7_0`, covering 1.8.0–1.10.0 — the
first selector telling callers it reproduces releases whose mask id it does not
emit. Carried back to the user, because output that differs from upstream's is
never adjudicated by the agent ([upstream-divergences](../aggregate/upstream-divergences.md)).

**What they were shown:**

| | |
|---|---|
| the difference | ours `id="mask__marble"`, upstream 1.10.0 `id=":R0:"` |
| whether it can be reproduced | **no** — measured: the same avatar is `:R0:` alone, `:R3:` as a third child, `:R2:` after a `<span>`, and **two copies in one document get `:R1:` and `:R2:`**. 1.8.0 has no fixed bytes for an avatar, so nothing can reproduce them, including 1.8.0 |
| what it looks like on screen | **nothing.** `tool/crosscheck` put upstream **1.10.0**'s own documents and ours through one Chrome: **1200 renders, 1150 pixel-identical**, the other 50 being 40 agreed refusals and the 10 already-ruled `sunset` blanks. Zero unruled differences |

The pixel comparison used **1.10.0, not 1.7.0**: 1.7.0 is what the port already
matches byte for byte, so comparing it would be the tautology
[crosscheck](crosscheck.md)'s own header warns about.

**What they chose:** emit 1.7.0's literal at every position, and say so plainly
in the README (and [fidelity.md](../../fidelity.md) §3) rather than letting
"reproduces 1.8.0" carry an asterisk nobody reads. Recorded in the fixture as
`idPositions` and asserted. **Theirs to reverse.**

**#45 applied the same ruling to `v1_10_1` — a derivation from this event, not a
new one.** All nine covered releases write `useId()` mask ids
(`groupProof.rawIdSamples`: nine `:R0:`), with `idPositions` showing the same
position-dependence; `marble`'s filter id joins the class from 1.10.2
(`rawFilterIdSamples`: literal `prefix__filter0_f` at 1.10.1, `filter_:R0:`
after). The port emits the pre-useId literals for both, asserted **raw**
through the public `v1_10_1` path — because the refuting lens measured that,
until then, a port renaming its ids *only for the new selector* passed every
gate (`normalise` erases ids, goldens are id-blind, and `buildPixelScene` is
the one builder that receives version information).
[lessons.md](../../agents/lessons.md): "The one builder that knows the version
is the one place ids can drift (#45)".

## Design model
From `version.dart`, `avatar.dart` and the fixtures (the rulings above are the
record; the mechanism is source-only).

- **Three values** — `v1_6_1` (1.6.1–1.6.3), `v1_7_0` (1.7.0, 1.8.0, 1.9.0,
  1.10.0), `v1_10_1` (1.10.1, 1.10.2, 1.11.1, 1.11.2, 2.0.0–2.0.4) — each
  carrying `upstreamVersions`. Every release appears under exactly one value
  (`a shipped selector never loses or gains a release`).
- **`latest` is a hand-maintained alias that moves** — `v1_6_1` in 0.1.0,
  `v1_7_0` in 0.2.0, `v1_10_1` since 0.3.0. Nothing defaults to it
  ([public-svg-surface](public-svg-surface.md), ruling 2026-08-08). Pinned both
  as a literal and as `values.last`, because the exhaustive switches force a new
  value to be *rendered* but nothing else forces `latest` to *move*.
- **Question 1 — `<title>`** (hidden-state #16). 1.6.x emits
  `<title>{name}</title>` unconditionally and has no `title` prop; 1.7.0 adds
  the prop defaulting off, and every later release keeps `title = false` in the
  destructuring through `master` (re-verified at `v1.10.1`, `v1.11.x`
  `defaultProps`/destructuring, `v2.0.x`, `master`). `emitsTitle` is an
  exhaustive `switch (version)`: `v1_6_1` → `true` for `null`/`true`,
  `ArgumentError` for `false`; `v1_7_0 || v1_10_1` → `title ?? false`. The
  flag is decided once here and passed to all six builders, which carry
  upstream's own `{props.title && …}`. The 1.6.3 → 1.7.0 source diff is 7 files,
  14 insertions: 6 lines are this element and 6 are whitespace inside a JSX
  expression (re-verified `git diff --numstat`), so this row is the whole of
  `0.2.0`; `v1_7_0` with `title: true` is byte-identical to `v1_6_1` for all
  six variants (`title_test.dart`).
- **Question 2 — which drawing** (`_Drawing`). `v1_6_1 || v1_7_0` →
  `_Drawing.v1_6_1`; `v1_10_1` → `_Drawing.v1_10_1`. Each drawing is then
  spelled per variant at the one knob that moves: `pixelColourIndex` is
  `loopIndex` or `loopIndexPlusOne` (hidden-state #17: 1.10.1 changed
  `numFromName % i` to `% (i + 1)`, the only drawing change in the supported
  range — the tile-0 consequence is in [pixel](pixel.md)). The enum exists
  because flattening the dispatch in #43 narrowed the old guard: with only
  `emitsTitle`, a selector that draws differently would compile and render its
  neighbour's picture. Adding a `_Drawing` value breaks every switch over it,
  at exactly the knob that has to decide.
- **Generated ids** — every selector emits the pre-useId literals (ruling
  above); the literals themselves are written by the variant builders
  ([marble](marble.md), [pixel](pixel.md), …) and serialised by
  [svg-emission](svg-emission.md).
- **The `size` default is out of the version state** only because `size` is
  required — see [public-svg-surface](public-svg-surface.md) for the
  three-valued default history and its validity condition.

### The upstream version ladder — source archaeology, not the port order
What the 28 git tags contain; how the v1.6.1 boundary was decided. Do not read
a row as a release: rows 11–17 map to only **two** selectors, and row 15
(v1.11.0) to none.

| # | Tags | Hash | Variant set |
|---|---|---|---|
| 1 | v1.2.0 | `getNumber` | geometric (default), abstract, beam, eye, marble |
| 2 | v1.3.0–v1.3.1 | `getNumber` | marble (default), dome, moholy, beam, ring |
| 3 | v1.4.0 | `getNumber` | + bauhaus, pixel, sunset (9) |
| 4 | v1.4.1 | `getNumber` | 9 |
| 5 | v1.4.2 | `getNumber` | 9 |
| 6 | v1.5.3–v1.5.5 | `getNumber` | `dome` dropped → the modern 6; `geometric`/`abstract` become aliases |
| 7 | v1.5.6 | `getNumber` | 6 — reverted at v1.6.0 |
| 8 | v1.5.7–v1.5.8 | `getNumber` | 6 — reverted at v1.6.0 |
| 9 | v1.6.0 | `getNumber` | **byte-identical to v1.5.3** |
| 10 | **v1.6.1–v1.6.3** | **`hashCode`** ← the switch | 6 |
| 11 | v1.7.0 | `hashCode` | 6 |
| 12 | v1.8.0–v1.10.0 | `hashCode` | 6 |
| 13 | v1.10.1 | `hashCode` | pixel only |
| 14 | v1.10.2 | `hashCode` | marble only |
| 15 | v1.11.0 | `hashCode` | 6 |
| 16 | v1.11.1–v1.11.2 | `hashCode` | 6 — `defaultProps` → destructuring defaults, same values |
| 17 | v2.0.0–v2.0.2 (+ 2.0.3/2.0.4 on `master`) | `hashCode` (TS rewrite) | 6 |

("Variant set" for rows 13/14 names the one component that changed.) Row 15 is
the row the table gets wrong on its own terms — it reads as ordinary, and
rendering it shows the prop leak; a blob diff cannot see that, which is why the
grouping criterion moved to output. **States 7–9 are the trap:** v1.5.6–v1.5.8
changed all six components and v1.6.0 restored v1.5.3's blobs exactly —
upstream reverted them; never carry their changes into state 10. **npm 2.0.4
(and 2.0.3) has no git tag** — the latest tag is v2.0.2; that state is resolved
from npm's recorded `gitHead`, which lands on `master`'s `src/lib` tree
(fixture `groupProof.npmProvenance`).

**Measured this map pass (2026-10-22), by `src/lib` tree hash over all 28 tags:**
18 distinct trees, not 17, plus a 19th at `master`. Row 9 is confirmed
(`v1.6.0` shares `162bc873…` with v1.5.3–v1.5.5). The extra state is inside row
17: `v2.0.2` (`a54785ce…`) differs from `v2.0.0`/`v2.0.1` (`e0b7957c…`) by the
`size = '40px'` default and a `types.ts` edit, and `master` (`5790e5c5…`)
differs from `v2.0.2` by types only. And `v2.0.0` vs `v2.0.1` is not "only
`types.ts` moved" within `src/lib` — the two trees are identical. Row 16's two
tags are also two trees (`7ca89734…`, `eb3203da…`), which the row already says.
The table's 17 counts row 16 and row 17 as one "state" each by intent, not by
bytes; the history of that count (16 → 17 after #1 found row 15 held two) is
why it is worth stating which reading a number uses.

## Code
- `lib/src/version.dart — BoringAvatarsVersion` (`v1_6_1`, `v1_7_0`,
  `v1_10_1`, `upstreamVersions`, `latest`)
- `lib/src/avatar.dart — buildAvatarScene` (`emitsTitle` switch, `drawing`
  switch, `pixelColourIndex` switch)
- `lib/src/avatar.dart — _Drawing`
- `lib/src/variants/pixel.dart — PixelColourIndex` (the knob; owned by
  [pixel](pixel.md))
- Fixtures: `test/fixtures/<selector>/svg.json` → `upstreamReleases`,
  `groupProof` (`rendered`, `bySourceTree`, `npmProvenance`, `rawIdSamples`,
  `rawFilterIdSamples`, `idPositions`, `renderedFrom`), `titleRenders`.
- Tests: `test/api_surface_test.dart` — group `BoringAvatarsVersion`;
  `test/title_test.dart` (all groups); `test/v1_7_0_parity_test.dart` and
  `test/v1_10_1_parity_test.dart` — groups `the group this selector claims`,
  `the change is confined to pixel`, `title behaves as 1.10.1 does`;
  `test/fixtures_test.dart — a version covering more than one release proves it
  did`, `they declare the upstream releases this version claims`.
- Mutation case files: `tool/mutate/cases/43-drawing.json`,
  `43-title.json`, `45-pixel-index.json` ([mutation-harness](mutation-harness.md)).

## Reference behaviour
- Pinned tree: `git -C /Volumes/T7/GitHub/.refs/boring-avatars` — `avatar.js`
  at each tag for `title`, `index.tsx` at `v2.0.x`/`master`;
  `components/avatar-pixel.js` at `v1.10.0` vs `v1.10.1` for the colour index.
- `test/fixtures/<selector>/svg.json` `groupProof` — every covered release
  rendered against the selector's `renderedFrom` (2,400 documents each for
  `v1_10_1`'s eight others and `v1_7_0`'s 1.10.0, zero mismatches — re-read
  this pass).
- [version-grouping](version-grouping.md) — the re-runnable grouping
  measurement; [crosscheck](crosscheck.md) — the Chrome pixel comparison
  behind the ids ruling.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — a shipped
  value's output and its `upstreamVersions` list never change. All three are
  shipped — `v1_6_1` in 0.1.0 (2026-08-12), `v1_7_0` in 0.2.0 (2026-08-13),
  `v1_10_1` in 0.3.0 (2026-08-14); latest published 0.3.3 (queried
  `https://pub.dev/api/packages/boring_avatars`, 2026-10-22).
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) —
  `upstreamVersions` and these doc-comments are one of several copies of the
  release → selector → versions mapping.
- [byte-gates-erase-ids](../invariant/byte-gates-erase-ids.md) — the `v1_7_0`/`v1_10_1` parity tests normalise ids; `v1_7_0` has no raw assertion of the port's own ids.
- [version-required-everywhere](../invariant/version-required-everywhere.md) — `latest` moves each release, which is why no surface may default to it.

## Blast radius
- [pixel](pixel.md) — the only builder that receives version information; a
  `_Drawing` change or a mis-mapped selector redraws 100% of one era's pixel
  avatars, and it is the one place ids could drift per selector.
- [variants](../aggregate/variants.md) — all six take `title` from
  `emitsTitle`; a wrong answer adds or drops an element no pixel test sees.
- [public-svg-surface](public-svg-surface.md) — the enum is public and
  `version` is required on the strength of `latest` moving; adding a value
  changes what `latest` means for every caller who passed it.
- [widget-lifecycle](widget-lifecycle.md) — the widget requires a version too
  and passes `title: null`; it assumes the title flag never changes pixels.
- [version-grouping](version-grouping.md), [parity-harness](parity-harness.md),
  [upstream-watch](upstream-watch.md), [milestones-sync](milestones-sync.md),
  [release-and-publishing](release-and-publishing.md)
  — each holds its own list of covered releases or selectors; a new selector
  that is added here and not there leaves one of them describing a different
  package (the invariant above names the copies).

## Known holes / open
- A new upstream release is a new selector only if [version-grouping](version-grouping.md)
  says its output differs; nothing in this territory runs that check.
- The `_Drawing` guard forces a decision only at knobs that already switch on
  it. A future drawing that moves a variant with no knob yet compiles and draws
  the old picture until someone adds the switch — the comment says so; nothing
  enforces it.
- `idPositions` and `rawIdSamples` are recorded from the harness's render
  positions; the "same avatar, same pixels" half of the ids ruling rests on the
  [crosscheck](crosscheck.md) run, which is not a gate.
