# pixel

## What it is

The `pixel` variant: an 8×8 mosaic of 10-unit tiles on an 80-unit canvas, each
tile filled from the palette by a hash-derived index, under the only
`mask-type="alpha"` mask in the package. It was the tracer bullet that built the
rasterizer core (2026-07-28). It is also **the one variant whose drawing differs
between selectors**: upstream 1.10.1 changed the per-tile colour index, which
makes `pixel` the entire content of release `0.3.0` / selector `v1_10_1`.

## Governing decisions

**None.** No ADR and no ledger ruling governs `pixel`.

Adjacent:

- `CLAUDE.md`'s release table is where the "one release per output state"
  rule puts `pixel`'s colour index as the one thing `v1_10_1` changes. That
  table is identity, not a decision about this file
  ([version-selectors](version-selectors.md),
  [selector-coverage-copies](../invariant/selector-coverage-copies.md)).
- [ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md) decides
  where the buffer lands on the device grid ([pixel-placement](pixel-placement.md)),
  not what `pixel` draws.
- The hidden-state #24 ruling in #83 ("live, and the reproduction is correct")
  was measured mostly on `pixel`, but it rules on the compositor
  ([compositing-and-masks](compositing-and-masks.md)), not on this builder.

## Design model

From the source and its doc-comments, plus dated measurements.

- **Two drawing eras, one file.** The second drawing state arrived in #45
  (2026-08-14) and did **not** split the layout. `pixel.dart` carries both
  colour-index eras behind a required `PixelColourIndex` parameter, and
  `avatar.dart`'s `_Drawing` switch decides which era a selector gets
  (`v1_6_1`/`v1_7_0` → `loopIndex`; `v1_10_1` → `loopIndexPlusOne`). A state
  that redrew a variant's *geometry* is what would still split a file. The enum
  names say what the divisor is, because "old/new" would invert the day
  upstream changes it again. The parameter is **required with no default**, for
  the same reason as `title`: two shipped selectors answer it differently, so a
  builder shared by both may not prefer one. Dispatch side:
  [variant-dispatch](variant-dispatch.md).

  | Era | Upstream | Expression | Tile 0 |
  |---|---|---|---|
  | `PixelColourIndex.loopIndex` | 1.6.1 – 1.10.0 | `getRandomColor(numFromName % i, …)` | **never filled**: `hash % 0` is `NaN` |
  | `PixelColourIndex.loopIndexPlusOne` | 1.10.1 – 2.0.4 | `getRandomColor(numFromName % (i + 1), …)` | `colors[0]` (`hash % 1 == 0`) |

  The expression change was re-read in the pinned tree (`avatar-pixel.js:12` at
  v1.6.1 and v1.10.0 vs v1.10.1).

- **Hidden-state #17: in the pre-1.10.1 drawing, the first tile is never
  filled.** `i == 0` makes the divisor zero, so `colors[NaN]` is `undefined`, and
  the first `<rect>` ships **with no `fill` attribute at all**. This happens for
  every name and every palette, defaults included. It is a degenerate *loop
  index*, distinct from #8's degenerate *palette*, and it needs no unusual input
  to fire. Applying either era's rule to the other era is wrong on **100% of
  pixel renders**. Re-verified on the committed fixtures: `v1_6_1/svg.json` has
  a bare first tile on 100 of 100 `pixel` renders, and `v1_10_1/svg.json` on 20
  of 100 (exactly the 20 empty-palette renders, where only #8's route remains).
  `pixel_parity_test.dart` pins both eras: "the first tile has no fill" and
  "the second colour index — upstream 1.10.1 onward". The second uses lists
  measured from upstream at tag v1.10.1 (#45), not lists derived here.
- **Hidden-state #2b, `pixel`'s half.** `hash % i` at `i == 0` is one of the two
  ways the package reaches a zero divisor (the other is an empty palette).
  `jsMod` deliberately rejects zero, so the `loopIndex` arm calls `jsModOrNull`,
  which returns `null`, the Dart shape of `NaN`. The `loopIndexPlusOne` arm
  calls `jsMod`, because its divisor starts at 1.
- **The tiles are not emitted in reading order.** The DOM order is `x = 0, 20, 40,
  60, 10, 30, 50, 70` across the top row, then column by column. `_tiles` is
  extracted from the component (64 entries, indices 0–63 each exactly once) and
  is load-bearing for byte parity while being invisible on screen. Pinned by
  "tiles are emitted in upstream order, not reading order".
- **`x`/`y` are absent when zero, not `="0"`.** The omissions coincide exactly
  with zero (verified against the component).
- **Only `pixel` declares `mask-type="alpha"`** (hidden-state #22). The other
  five declare nothing, which means luminance. The difference is inert because
  every mask is filled `#FFFFFF`. The rasterizer throws on a non-white
  luminance mask rather than assuming. Mechanism:
  [compositing-and-masks](compositing-and-masks.md).
- **`rx` on the mask is 160 on an 80 side**, clamped by §9.2 to 40, which makes
  the mask a disc (hidden-state #9; "a radius larger than half the side is
  clamped, not scaled").
- **Empty palette:** every one of the 64 tiles is unfilled in both eras, and
  nothing throws. Upstream measured 64 `undefined`s.

Hidden-state rows, variant half only:

| Row | What `pixel` writes | Live / inert here | How it was established |
|---|---|---|---|
| #8 empty palette | 64 `<rect>` with no `fill` | live: transparent | 20 names, v1.6.1 |
| #17 tile 0 | era-dependent | live: 100% of renders | fixtures, re-verified |
| #22 `mask-type` | `alpha` | inert (white mask) | source |
| #23 rounding per shape | tiles never overlap | inert | #37 |
| #24 abutting shapes | integer-aligned tiles meeting edge to edge | **inert at 1:1, live at any scale whose tile edges fall mid-pixel.** Measured on the #58 branch (2026-08-09), counting interior pixels below 255: 80→0, 84→452, 100→556, 101→1025, **210→1944**, 128→0, worst gap **80/255**. 210 is the 2.625 device pixel ratio a widget actually asks for. **Ruled in #83: the reproduction is correct**, because Chrome conflates abutting edges the same way. A square `pixel` at 100 gives **784** partial pixels on both sides, zero where Chrome is opaque and we are not, worst edge delta **3/255**; 210 agrees the same way. | `raster_scale_test.dart`, [compositing-and-masks](compositing-and-masks.md) |
| #33 mask per group | at most one shape reaches any mask-edge pixel | inert. The #37 fix moved 8 pixels of `pixel`'s goldens, all fully transparent and straight-RGB-only (#29). | #37 |
| #45 transform | none | inert: `pixel` writes no transform | 600 renders |

## Code

- `lib/src/variants/pixel.dart`: `PixelColourIndex` (`loopIndex`,
  `loopIndexPlusOne`), `pixelColors`, `buildPixelScene`, `_tiles`, `_size` (80)
- `lib/src/avatar.dart`: `_Drawing`, and the `pixelColourIndex` switch inside
  `buildAvatarScene` (the only per-drawing knob in the dispatch)
- `lib/src/js/js_number.dart`: `jsModOrNull`, used by the `loopIndex` arm
- `test/pixel_parity_test.dart`: the byte sweep, "the two traps this variant
  carries", "the second colour index — upstream 1.10.1 onward", square, size
- `test/pixel_raster_test.dart`: geometry independent of goldens, rx clamping,
  seam refusals, colour parsing, mechanisms pinned directly, goldens
- `test/v1_10_1_parity_test.dart`: the byte sweep for the new era through the
  dispatch, plus the cross-selector proof that the other five are unchanged
- `test/support/golden_cases.dart`: `pixel-clara-default`, `pixel-alice-pair`,
  `pixel-clara-square` (added in #80), `pixel-empty-name`,
  `pixel-clara-second-index` (the only golden drawn with `loopIndexPlusOne`)
- `tool/mutate/cases/45-pixel-index.json`: mutation patterns typed against
  the colour-index text

## Reference behaviour

- Pinned upstream: `../.refs/boring-avatars` `src/lib/components/avatar-pixel.js`
  @ v1.6.1 and v1.10.1 (the one-expression diff), and `.tsx` @ v2.0.x.
- Fixtures: [`test/fixtures/v1_6_1/svg.json`](../../../test/fixtures/v1_6_1/svg.json)
  and [`test/fixtures/v1_10_1/svg.json`](../../../test/fixtures/v1_10_1/svg.json),
  `pixel|upstream-default|upstream-default`. The first has the bare `<rect>`, the
  second has it filled.
- [calibration](calibration.md): the square `pixel` at 100 and 210 is the only
  curve-free case in that harness, and it is the #24 ruling's evidence.

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md): both eras are shipped. `loopIndex` is frozen for `v1_6_1`/`v1_7_0`, and `loopIndexPlusOne` for `v1_10_1`.
- [variant-design-size](../invariant/variant-design-size.md): 80
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md): `mask-type="alpha"`, the literal `#FFFFFF` mask fill
- [root-fill-none](../invariant/root-fill-none.md): the bare tile 0 and the empty palette's 64 bare tiles
- [selector-coverage-copies](../invariant/selector-coverage-copies.md): "pixel's colour index" is the stated difference of `v1_10_1` in every copy
- [libm-transcendentals](../invariant/libm-transcendentals.md): only through the rounded mask's arcs

## Blast radius

- [variant-dispatch](variant-dispatch.md): `_Drawing` → `PixelColourIndex` is the
  one per-drawing knob. A new enum value here breaks that switch, by design.
- [version-selectors](version-selectors.md): a selector's covered-versions claim
  rests on which era it draws. Moving a boundary would re-colour 100% of
  `pixel` avatars for the moved versions.
- [version-grouping](version-grouping.md): the grouping measurement is what found
  that `pixel` is the only drawing change between 1.6.1 and 2.0.4.
- [coverage](coverage.md): `pixel`'s tiles are axis-aligned, so at 1:1 they take
  the closed-form rect integrator. At any other scale they go through the
  scanline path.
- [compositing-and-masks](compositing-and-masks.md): abutting tiles are the #24
  case. A change in how coverage of neighbouring shapes combines shows up here
  first.
- [goldens](goldens.md): five committed images, one per era-relevant case.
- [mutation-harness](mutation-harness.md): `45-pixel-index.json` matches this
  file's text.
- [readme-gallery](readme-gallery.md): the gallery draws through this builder.

## Known holes / open

- **The interior-edge residues in the #83 run.** `pixel` at 100 *rounded* left
  1 px. These residues sit on a mask curve, which is hidden-state #27, a
  separate question still unruled. See [compositing-and-masks](compositing-and-masks.md)
  and [calibration](calibration.md).
- **A third era would need a third enum value.** The file layout survives
  that. A change to the tile geometry would not.
