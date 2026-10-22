# Byte gates erase ids

## The fact
Every byte-for-byte comparison of this package's SVG against upstream
**normalises the same things away on both sides**: `id="…"`, `url(#…)`,
`mask="…"`, and the `prefix__` filter id. A byte gate therefore says nothing
about any id, and the goldens are id-blind too.

Ids are pinned only by separate raw assertions:
- `maskIdentifiers` and `derivedIdentifiers` in the `v1_6_1` fixture, asserted
  by the per-variant parity tests;
- the literal-id tests in `v1_10_1_parity_test.dart`.

The `v1_7_0` path has no raw assertion of the port's own ids. Its id tests
assert the *fixture's* upstream samples (`rawIdSamples`, `idPositions`), not
what the port emits.

## Why it is cross-cutting
The normalisation is written several times, with no shared helper:
- `normalise` in `tool/parity/dump.mjs`;
- a local `normalise` in each of `avatar_svg_test.dart`,
  `bauhaus_parity_test.dart`, `beam_parity_test.dart`,
  `marble_parity_test.dart`, `pixel_parity_test.dart`,
  `ring_parity_test.dart`, `sunset_parity_test.dart`,
  `v1_7_0_parity_test.dart` and `v1_10_1_parity_test.dart`.

Widening any one of them (erasing a new attribute) opens a hole in that gate
alone, and nothing reports it. The exclusion is right for the ids upstream's
`useId()` generates from 1.8.0, which have no fixed bytes. It buys nothing at
1.6.1, where every id is a literal in the JSX. Hence the rule this repo learned
the hard way: **a normalisation is a hole in the gate and needs its own
assertion beside it**.

## Territories it holds in
- [parity-harness](../territory/parity-harness.md) — `dump.mjs`'s `normalise`, and the raw sections `maskIdentifiers` / `derivedIdentifiers` / `rawIdSamples` / `idPositions`
- [version-selectors](../territory/version-selectors.md) — the `v1_7_0` and `v1_10_1` parity tests; the generated-ids ruling (maintainer, 2026-08-13)
- [public-svg-surface](../territory/public-svg-surface.md) — `avatar_svg_test.dart`'s `normalise`
- [sunset](../territory/sunset.md) — its gradient ids are derived from the name, so the erased thing is a real derivation, pinned only by `derivedIdentifiers`
- [marble](../territory/marble.md) — the `prefix__filter0_f` filter id, normalised away and asserted raw only on `v1_10_1`
- [crosscheck](../territory/crosscheck.md) — the one comparison that keeps ids: it renders unnormalised documents in one browser, so a dangling reference shows up as pixels
- [goldens](../territory/goldens.md) — pixels carry no ids

## What a violation looks like
A port that names its mask anything at all, or points a group at a dangling
reference, passes every byte gate. Measured: mutating `mask__ring` to
`mask__pixel`, or making a group's reference dangle, left the byte suite green.
`tool/crosscheck` then reported 22,468 differing pixels because the mask never
applied (#37). The #45 completeness pass also found that renaming ids *only for
the new selector* passed every gate until a raw assertion was added through the
public `v1_10_1` path.

## Discovery history
- #37 added `maskIdentifiers` after the mutation above survived.
- #40 added `derivedIdentifiers` for `sunset`.
- #45 added the raw `v1_10_1` assertions.
  (All three recorded in theflow.md Step 4 and the generated-ids ruling,
  @ 0593e28.)
- Promoted to an invariant at map init (maintainer, 2026-10-22).

## Where it will recur
If a test or tool compares SVG text after rewriting it, it is subject to this.
Whatever it erases needs its own assertion. A new selector needs a raw id
assertion through its public path, which `v1_7_0` still lacks.
