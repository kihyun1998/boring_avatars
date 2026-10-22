# js-semantics

## What it is
The JavaScript number and string semantics that Dart does not share, ported as
small primitives so every caller above them gets JavaScript's answer and not
Dart's: remainder sign, a zero divisor's `NaN`, `ToInt32` narrowing,
`String(n)` number formatting, `parseInt(s, 16)` and `substr`. It is the floor
of Layer 1 (data): [upstream-utilities](upstream-utilities.md) and every
variant builder compute through it, and [scene-model](scene-model.md) formats
every numeric attribute through `jsNum` at emit time. Part of the sacred surface
(`lib/src/js/`, `CLAUDE.md` "Layer 1 is frozen on publish").

## Governing decisions
No ADR governs this. What governs it is `CLAUDE.md`'s first principle — the
reference is the specification — applied to the language rather than to the
library: a primitive here is correct when it gives the value JavaScript gives,
however un-Dart-like. The working rule that came with it (maintainer's routing
table in the retired `theflow.md`, Step 1): **JS language semantics are settled
by running a Node probe and reading the number, cross-checked against
ECMA-262 — never from memory, and reading the code is not observing what it
does.** [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md) sits
adjacent and does not govern: it decides what a *colour declaration* means to
the rasterizer; `jsParseIntHex` here only reproduces what `getContrast` does
with a palette string.

## Design model
From the source and its doc-comments (no record): one function per place a
direct translation silently produces a different answer, each named after the
JS behaviour it reproduces.

- **`%` is a remainder, not a modulo** (`jsMod` = `remainder`): `-7 % 5` is `-2`
  in JS and `3` in Dart. **Inert at every supported selector**: `jsHashCode` is
  `Math.abs`'d and every caller passes it, `hash + i`, or `hash * (i + 1)`, all
  non-negative (re-verified at HEAD by reading every call site in
  `lib/src/variants/`). Swapping `jsMod` for Dart `%` therefore breaks no
  fixture assertion; only the helper's own test pins it. Kept so the port is
  already right the day a negative appears.
- **A zero divisor is `NaN` in JS and a throw in Dart.** `jsMod` deliberately
  rejects zero (pinned: `jsMod(645088871, 0)` throws). Callers that can see a
  zero use `jsModOrNull`, whose `null` is the Dart shape of `NaN` — everything
  downstream of a `NaN` upstream ends as `undefined` and React drops the
  attribute. Reachable twice: an empty palette (`range == 0`, handled inside
  `jsGetRandomColor`) and `pixel`'s `hash % i` at `i == 0` before 1.10.1 (see
  [pixel](pixel.md), [version-selectors](version-selectors.md)).
- **`ToInt32`** (`toSigned32`): Dart `int` is 64-bit and never wraps; JS bitwise
  operators narrow. Used by `jsHashCode` every iteration.
- **`String(n)`** (`jsNum`): integral doubles print without `.0`, `-0` prints
  `0`, integral values print in full below `1e21` (Dart switches to exponent
  earlier and `toInt()` saturates at 2^63), `NaN`/`±Infinity` spelt as JS spells
  them; non-integral values already round-trip identically (both emit the
  shortest representation). Without it, layer-2 bytes break (`4.0` vs `4`).
- **`parseInt(s, 16)`** (`jsParseIntHex`), per ECMA-262: skips `StrWhiteSpace`,
  consumes one sign, strips a `0x`/`0X` prefix (so `parseInt('0x', 16)` is
  `NaN` — `'0xFF0000'` contrasts as white), stops at the first non-hex digit,
  and returns `double.nan` when there are no digits. The `NaN` is load-bearing:
  it propagates through `getContrast`'s arithmetic and makes `NaN >= 128` false.
- **`substr`** (`jsSubstr`) clamps where Dart's `substring` throws.

Input bound: these are pure functions over values the caller passes. Two
outside inputs reach them unbounded: palette strings (to `jsParseIntHex` via
`jsSubstr`, which cuts each to two characters first) and a numeric `size` (to
`jsNum`, any `num` including `1e300` or `Infinity`).

## Code
- `lib/src/js/js_number.dart — jsMod`
- `lib/src/js/js_number.dart — jsModOrNull`
- `lib/src/js/js_number.dart — jsModDouble` (the float remainder `jsGetDigit` needs)
- `lib/src/js/js_number.dart — toSigned32`
- `lib/src/js/js_number.dart — jsNum`
- `lib/src/js/js_number.dart — jsParseIntHex`, `_isJsWhitespace`, `_isHexDigit`
- `lib/src/js/js_number.dart — jsSubstr`
- Tests: `test/js_primitives_test.dart` — group `JS number semantics`
  (`jsMod keeps the sign of the dividend, unlike Dart %`, `toSigned32 wraps the
  way a JS bitwise op does`, `jsNum prints an integral value without a decimal
  point`, `jsNum prints large integral values in full, not saturated`, `jsNum
  handles the non-finite values String() names`, `jsModOrNull expresses the NaN
  that jsMod cannot`); group `getContrast matches upstream` (`jsParseIntHex is
  parseInt(s, 16), not a hex scanner`, `a hex string shorter than six digits
  clamps instead of throwing`).

## Reference behaviour
- ECMA-262 `ToInt32`, `Number::toString`, `parseInt`, `String.prototype.substr`
  — the spec text is the reference; the behaviour is re-measured by Node probe
  (maintainer's routing rule above).
- Upstream's own `utilities.js` at `v1.6.1`
  (`/Volumes/T7/GitHub/.refs/boring-avatars`, `git show v1.6.1:src/lib/utilities.js`)
  is where each primitive is used; the values in `test/fixtures/<selector>/utilities.json`
  were dumped from that module by [parity-harness](parity-harness.md).

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — every
  shipped selector's numbers and bytes pass through here.

## Blast radius
- [upstream-utilities](upstream-utilities.md) — every utility's value is one of
  these primitives applied to `hashCode`; a change in sign, narrowing or
  zero-divisor handling moves the hash or a unit for every avatar.
- [scene-model](scene-model.md) / [svg-emission](svg-emission.md) — every
  numeric attribute is printed by `jsNum`; a formatting change is a byte change
  on every render while pixels stay identical, so only the byte gates see it.
- [pixel](pixel.md) — the pre-1.10.1 era depends on `jsModOrNull`'s `null` to
  leave tile 0 without a `fill`; a `NaN`-as-zero shortcut fills it on 100% of
  `v1_6_1`/`v1_7_0` pixel renders.
- [marble](marble.md), [beam](beam.md), [bauhaus](bauhaus.md) — they build
  `transform` strings by concatenating `jsNum` output; that string is what the
  rasterizer later parses ([transforms](transforms.md)).
- [public-svg-surface](public-svg-surface.md) — a numeric `size` is printed by
  `jsNum` into `width`/`height`, and the caller expects `String(n)`'s spelling
  there. The `sizePassthrough` fixture only measures `40` and `80`, so a
  formatting change for any other number reaches callers unseen.
- [beam](beam.md) — the only consumer of `jsParseIntHex`/`jsSubstr` (via
  `getContrast` on a palette entry); a stricter parser changes which face colour
  a malformed palette gets.

## Known holes / open
- `jsMod`'s sign behaviour and `jsGetDigit`'s float division are both
  unobservable on every reachable input (non-negative). Their correctness is
  pinned only by the primitives' own tests, not by any fixture. Valid as long as
  every caller passes `hashCode` output or non-negative multiples of it.
- `jsNum`'s large-integral, exponent (`|d| >= 1e21`) and non-finite branches are
  reachable by no variant's geometry — only through `size`, which is consumer
  policy written straight into `width`/`height` and bounded by nothing
  ([public-svg-surface](public-svg-surface.md)). Pinned by unit tests only; no
  upstream fixture renders a `size` of `1e19` or `Infinity`.
