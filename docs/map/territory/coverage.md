# coverage

## What it is
The integrators in `raster.dart` that turn a shape into per-pixel coverage in
0–1: a closed-form box overlap for axis-aligned `RasterRect`s, and a scanline
integrator under the **nonzero** winding rule for every `RasterPolygon`. It
also covers the choice between them — the `isTranslationOnly` fast path, which
is reachable only at a device scale of exactly 1 and is the largest single
cost lever in the rasterizer.

## Governing decisions
**None.** The design is from reading the source and from dated measurements
recorded in theflow.md. [ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md)
decides how the widget sizes the buffer — and so whether the scale is 1 — but
not how coverage is computed.

## Design model
**Two integrators, tied together by a test.**
- *`RasterRect` — closed form (`_fillRectSteps`, `_overlap`).* Coverage is the
  product of a row overlap and a column overlap; nothing is approximated.
- *`RasterPolygon` — scanline, nonzero (`polygonCoverageSteps`, `_addSpan`,
  `_Edge`, `_Crossing`).* Each pixel row is integrated over `_slicesPerRow`
  (256) horizontal slices; at each slice centre the active edges' crossings are
  sorted, winding numbers accumulated, and every span with non-zero winding is
  clipped to pixel columns in closed form. So coverage is **exact in x and
  quantised in y**: the only error is which side of a slice centre a
  horizontal edge falls, bounded by `1/(2·256)` — about 0.5/255 — and only for
  an edge exactly horizontal inside a row. Horizontal edges are dropped (they
  cross no scanline). `ring`'s two path rectangles (`M0 0h90v45H0z`) are still
  exact, because 0, 45 and 90 land on pixel boundaries.

**Rects keep their own integrator on purpose.** The polygon path quantises the
vertical direction and a horizontal edge is exactly where that is worst; a box
overlap has nothing to approximate. A second "fill a shape" is a divergence
seed unless tied: `raster_path_test.dart` renders the same fractional rectangle
both ways and requires ≤1 byte apart ("a rect drawn as a polygon matches the
closed-form rect").

**The nonzero rule is load-bearing beyond SVG's default.** Stroke outlines are
unions of overlapping same-wound pieces ([path-geometry](path-geometry.md));
an even-odd integrator would punch every overlap.

**#58 made the closed form unreachable at every scale but 1:1, and the
rationale is now conditional.** [scene-reading](scene-reading.md) sends a rect
to `RasterRect` only when its matrix `isTranslationOnly` (exact `a == 1, b ==
0, c == 0, d == 1`), and the walk starts at `Affine.scaling(s, s)`, so at any
`s != 1` every rect is a polygon. Accuracy does not change — measured against
exact analytic box coverage at `s` of 1.0, 1.25, 1.5 and 2.5, the scanline
result is **0.0/255** off at every pixel (#58) — so it is a reachability and
cost question, not a wrong picture. The closed form stays because 1:1 is the
golden path and the reference the other integrator is checked against; a
widget at a fractional device pixel ratio never reaches it.

**Cost is discontinuous at the design size (measured 2026-08-10).** Swept one
pixel either way, twice, ratios measured back to back:

| | at the viewBox side | one pixel off |
|---|---|---|
| `pixel` (all axis-aligned rects) | 2.8 ms | **6.5x** |
| `bauhaus` (some rects rotated) | 7.3 ms | 1.9x |
| `ring` (no axis-aligned rects) | 27.7 ms | flat |

`ring` is the control that makes it an attribution: the effect is present
exactly where the mechanism predicts and absent where it predicts nothing. It
is robust to this machine's load because it is a ratio between neighbours
measured seconds apart; absolute numbers moved up to 7x between runs and are
not a spec. User-facing statement: [docs/performance.md](../../performance.md),
"One size per variant is much cheaper than its neighbours".

**It was undefended, and is now pinned structurally.** With
`isTranslationOnly` forced false, **758 of 760 tests stayed green** — every
golden included, because the two integrators agree and that agreement is the
point of the pair. `test/raster_fast_path_test.dart` asserts on
`SceneRaster.shapes` — rects stay `RasterRect` at the design size, none do one
pixel off, `ring` is flat — rather than on timing, which would be flaky here.

**Abutting vs stacked shapes (hidden-state #24) is a coverage-meets-compositing
question** and lives in [compositing-and-masks](compositing-and-masks.md): an
exact integrator gives each of two half-covering abutting shapes 0.5, and
per-shape compositing turns that into 192, not 255.

**`polygonCoverage` is exposed** because it is the one place a coverage
*number* can be checked against an independent one — a flattened disc must sum
to πr² — which the 1/255-rounded bytes cannot show.

The mask has a third integrator of the same "exact in x, sliced in y" shape —
`RoundedRectMask.coverageAt`, 64 slices — kept in
[compositing-and-masks](compositing-and-masks.md).

**Input bound.** Work is O(target area × 256 slices × active edges) per
polygon; the target size is the caller's and nothing here bounds it. Banding
it into yieldable steps is [banded-rasterisation](banded-rasterisation.md)'s.

## Code
- `lib/src/raster/raster.dart — RasterShape`, `RasterRect`, `RasterPolygon`
- `lib/src/raster/raster.dart — _fillRectSteps`, `_overlap`
- `lib/src/raster/raster.dart — _fillPolygonSteps`, `polygonCoverage`, `polygonCoverageSteps`, `_slicesPerRow`, `_addSpan`, `_Edge`, `_Crossing`
- `lib/src/raster/transform.dart — Affine.isTranslationOnly`
- `lib/src/raster/scene_raster.dart — _shapesOf` (the `<rect>` arm's fast-path branch), `SceneRaster.shapes`
- Tests: `test/raster_fast_path_test.dart` (all); `test/raster_path_test.dart` groups "the fill rule is nonzero, which is what SVG defaults to", "the two coverage paths agree with each other", "a disc comes out at pi r squared"; `test/raster_scale_test.dart` group "the scale moves nothing but the resolution"; `test/bauhaus_raster_test.dart` "a zero hash lands every edge on a pixel boundary", "a rotated bar antialiases where an unrotated one does not".

## Reference behaviour
- **Exact analytic coverage, not Chrome, is the reference for straight edges
  (#39).** Against Sutherland–Hodgman clip + shoelace (which quantises
  nothing), our integrator is within **0.03/255** on every shape `bauhaus`
  draws; Chrome overstates a 4°-from-horizontal edge by **30.6/255** and a 22°
  one by 19, and is exact at 0°. `bauhaus-empty-name` (hash 0, every transform
  the identity) has **zero** disagreement with Chrome outside its two curves;
  the rotated cases disagree only on shallow straight edges. Ours is the
  correct one. Chrome's own error on curves and shallow edges is hidden-state
  #27, and the bar re-scoping it forced is [calibration](calibration.md)'s
  (settled 2026-08-11).
- Exact box coverage at s ∈ {1.0, 1.25, 1.5, 2.5}: scanline 0.0/255 off (#58).

## Cross-cutting invariants
- [variant-design-size](../invariant/variant-design-size.md) — the fast path holds at exactly one target per variant: its viewBox side.
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the slice count and the rect/polygon split are part of the shipped bytes.
- [construction-time-length-scaling](../invariant/construction-time-length-scaling.md) — every scaled length lands on these integrators.

## Blast radius
- [scene-reading](scene-reading.md) — decides which integrator each rect gets; a change to that branch is invisible to every golden and visible only in cost.
- [transforms](transforms.md) — `isTranslationOnly`'s exactness is what makes `rotate(0)` and `scale(1)` keep the fast path.
- [path-geometry](path-geometry.md) — stroke pieces rely on nonzero union; contours rely on implied closing edges.
- [compositing-and-masks](compositing-and-masks.md) — coverage becomes source alpha in `blend`; abutting-edge seams (#24) come from the two together.
- [filters](filters.md) — a filtered shape's coverage and its region's both run through `polygonCoverageSteps`.
- [banded-rasterisation](banded-rasterisation.md) — the integrators are the generators it slices; a step is one scanline.
- [pixel](pixel.md), [bauhaus](bauhaus.md) — the variants whose cost the fast path decides.

## Known holes / open
- Why `pixel`'s discount is 6.5x and `bauhaus`'s only 1.9x is read from the code
  (`bauhaus` rotates some rects, so only part of its work takes the fast path),
  not measured per shape. Nothing depends on it.
- The web cost fix was left unchosen when the discontinuity was measured; it is
  [banded-rasterisation](banded-rasterisation.md)'s history.
- `raster_fast_path_test.dart`'s header and theflow both state the fast-path
  condition as `a == 1 && d == 1`; the code also requires `b == 0 && c == 0`.
