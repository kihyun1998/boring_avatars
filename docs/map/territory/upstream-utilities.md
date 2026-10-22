# upstream-utilities

## What it is
The port of upstream's `src/lib/utilities.js`: `hashCode` (name → 32-bit-derived
number) and the five functions every variant derives its values from —
`getDigit`, `getBoolean`, `getUnit`, `getRandomColor`, `getContrast`. Every
avatar in the package starts at `jsHashCode`, so a value wrong here is wrong in
every variant and every selector at once, and — once shipped — irreversibly.
The most sacred part of Layer 1 (`CLAUDE.md`, "Layer 1 is frozen on publish").

## Governing decisions
Two maintainer rulings bound this territory; neither is an ADR.

- **Scope starts at v1.6.1, where `getNumber` is replaced by `hashCode`**
  (maintainer, 2026-07-28). Held in full in
  [version-selectors](version-selectors.md#governing-decisions). Its
  consequence here: only `hashCode` is ported. `getNumber` (states 1–9) is out
  of scope, not deferred, and no helper is shared with it (see Design model).
- **Unreachable upstream code has no output to reproduce** — the same judgement
  that closed `turbulence` ([variant-dispatch](variant-dispatch.md)).
  Applied here: `getModulus` and `getAngle` are exported by upstream and
  imported by no component, and `getModulus` is not called by the other
  utilities either, so neither is ported. Re-verified at HEAD in the pinned
  tree at `v1.6.1` and at `master` (`git grep` finds only their definitions).

## Design model
From the source and its doc-comments, every claim measured against values
dumped from upstream's own module (no record). Nothing is derived from first
principles; each function reproduces what upstream does, including where that
is odd.

- **`hashCode`'s `hash = hash & hash` is not a no-op** (hidden-state #1).
  `hash << 5` narrows to 32 bits, but the following `- hash` and `+ character`
  run in float64 and escape again; the `&` pulls it back each iteration. Ported
  as `toSigned32(toSigned32(hash << 5) - hash + character)`. Without it the
  hash diverges on longer names. **No narrowing after `Math.abs`**: the raw
  accumulator can land on exactly −2³¹, whose absolute value is 2147483648 and
  does not fit back into int32 (pinned by a constructed name; no corpus name
  reaches it).
- **Iteration is over UTF-16 code units** (`codeUnitAt`, `length`), matching
  `charCodeAt` (hidden-state #5). `runes` would diverge on non-BMP input; a
  surrogate pair counts twice. The out-of-scope `getNumber` era does the
  *opposite* — `Array.from(name)` walks code points, then `charCodeAt(0)` of
  each (hidden-state #6) — so the two eras can share no helper. Recorded so a
  future re-entry of the pre-1.6.1 range does not reuse `jsHashCode`'s loop.
- **`getDigit` divides in float64** (hidden-state #4): `number / 10^ntn`, then a
  float remainder and `floor`. For non-negative input this equals integer
  division always — writing `n = q·10^k + r`, the float quotient is `q + f`,
  `0 ≤ f < 1`, so `floor((q + f) % 10) == q % 10` — verified over 11.2M
  reachable pairs (measured, retired `theflow.md` hidden-state #4). They differ
  only on negative input (`getDigit(-15, 1)` is −2 float, −1 integer — measured
  from upstream's module). **Valid as long as `getDigit` only receives
  `hashCode` output and non-negative multiples of it** — re-verified at HEAD:
  callers pass `numFromName` or `numFromName * (i + 1)`. Kept as float because
  that is what upstream writes, and the negative cases are pinned so a `~/`
  mutation is caught. `math.pow(10, ntn)` takes two `int`s, so it is exact and
  not a libm call.
- **`getUnit`'s `if (index && …)` treats `0` as falsy** (hidden-state #3).
  `getUnit(645088871, 10, 0)` and `getUnit(645088871, 10)` both give `1`
  (measured). A Dart `index != null` would negate at 0. **No caller passes 0**
  (re-verified: callers pass 1, 2, 3 or nothing), so the fixture was widened to
  index 0 deliberately — until it was, a mutation removing the guard passed the
  whole suite.
- **`getRandomColor` returns `null` where upstream returns `undefined`**:
  `range == 0` (empty palette, `% 0` is `NaN`) or an index outside the list.
  That is what lets five variants degrade on an empty palette; `beam` crashes
  because it hands the `null` to `getContrast`, which upstream also does
  (ruling S-2, [upstream-divergences](../aggregate/upstream-divergences.md);
  the per-variant split of hidden-state #8 lives in [beam](beam.md) and the
  other variant notes).
- **`getContrast` never throws on a malformed colour**: `parseInt` yields
  `NaN`, YIQ propagates it, `NaN >= 128` is false, so it answers `#FFFFFF`. The
  exact YIQ boundary `128` answers `#000000`. Built on
  [js-semantics](js-semantics.md)' `jsParseIntHex`/`jsSubstr`.
- **Version-independent by measurement**: upstream's `utilities.js` blob is
  identical at every tag from `v1.6.1` to `v1.11.2`
  (`1ac822c1…`), and `utilities.ts` at `v2.0.0`–`master` (`bf653ac2…`) is the
  same functions with type annotations and `var` → `const`/`let` (measured this
  map pass, 2026-10-22, by blob SHA and reading the file). That is why nothing
  here takes a version.

## Code
- `lib/src/js/utilities.dart — jsHashCode`
- `lib/src/js/utilities.dart — jsGetDigit`
- `lib/src/js/utilities.dart — jsGetBoolean`
- `lib/src/js/utilities.dart — jsGetUnit`
- `lib/src/js/utilities.dart — jsGetRandomColor`
- `lib/src/js/utilities.dart — jsGetContrast`
- Fixtures: `test/fixtures/v1_6_1/utilities.json`, `v1_7_0/utilities.json`,
  `v1_10_1/utilities.json` — per-name `hashCode`, `derived` (`getDigit`,
  `getBoolean`, `getUnit` keyed `range,index@multiple`, `getRandomColor`) and
  `getContrast`, dumped from upstream's module at each selector's `tag`.
- Tests: `test/js_primitives_test.dart` — groups `hashCode matches upstream on
  every corpus name` (incl. `Math.abs of the most negative 32-bit hash leaves
  int32 range`), `getDigit matches upstream`, `getDigit — what the float
  division does and does not buy`, `getBoolean matches upstream`, `getUnit
  matches upstream, with and without the index argument` (incl. `the fixture
  covers every range the six components actually pass`), `getRandomColor
  matches upstream` (incl. `an empty palette yields null rather than throwing`,
  `pixel's first tile is unfilled for every name and palette`), `getContrast
  matches upstream`, `the utilities upstream never reaches are not ported`.
- `test/fixtures_test.dart — utilities cover every corpus name`, `hashCode
  values are non-negative 32-bit-derived integers`.

## Reference behaviour
- Pinned upstream file: `git -C /Volumes/T7/GitHub/.refs/boring-avatars show v1.6.1:src/lib/utilities.js`
  (and `master:src/lib/utilities.ts`) — the generator body is the whole spec.
- `test/fixtures/<selector>/utilities.json` — values dumped by
  [parity-harness](parity-harness.md) (`tool/parity/dump.mjs`) by importing
  upstream's module from the reference tree at the selector's tag.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — this is
  the sacred surface's centre; every selector's output starts here.

## Blast radius
- [marble](marble.md), [beam](beam.md), [pixel](pixel.md),
  [sunset](sunset.md), [ring](ring.md), [bauhaus](bauhaus.md) — each
  derives every colour, translation, rotation and boolean from these; a changed
  hash or unit redraws that variant for every name at every selector.
- [beam](beam.md) — relies on `jsGetRandomColor`'s `null` reaching
  `jsGetContrast` and failing (S-2); returning a fallback colour would make
  `beam` render where upstream throws.
- [pixel](pixel.md) — its pre-1.10.1 era relies on `getRandomColor` receiving
  a `null` index for tile 0; its colour index is the one utility input that
  varies by selector.
- [parity-harness](parity-harness.md) — the fixture's key shape
  (`range,index@multiple`) assumes the call sites' ranges and multiples; a new
  call site with a new range is uncovered until the dump adds it.

## Known holes / open
- Hidden-state #4's float/integer equivalence and #2's sign equivalence are both
  unobservable on reachable inputs; only unit tests pin them (see
  [js-semantics](js-semantics.md)).
- `getContrast` receives arbitrary palette strings (consumer policy, unbounded
  length); `jsSubstr` bounds what is read to six characters.
