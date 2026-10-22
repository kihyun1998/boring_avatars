# path-geometry

## What it is
`path.dart` turns everything curved or stroked into closed polygons for the
coverage integrators: SVG path data (`parsePath` for fills,
`parsePathSubpaths` for strokes), circles, cubics, elliptical arcs, §9.2's
rounded rectangle, and stroke outlines — all at one stated flattening
tolerance. It is pure geometry in user units; the matrix that maps the result
to device space is [transforms](transforms.md)'.

## Governing decisions
**None.** The rules come from the SVG 1.1 specification text (F.6.5, F.6.6,
§8.3, §9.2, §11.4), from reading the source, and from dated measurements
recorded in theflow.md. [ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md)
is adjacent (widget placement), not governing.

## Design model
**The flattening tolerance is a constant, not a heuristic.** `defaultFlatness`
is 1/4096 user units: the largest distance a chord may sit inside its curve.
Segment counts follow from radius, swept angle and that number
(`_segmentsFor`: `2·acos(1 − ε/r)` per chord), so `ring`'s widest arc — a
semicircle of radius 38 — becomes 440 segments. Two orders below the ≤1/255
coverage bar. [scene-reading](scene-reading.md) passes `defaultFlatness / s`
at device scale `s`, which keeps device error constant and changes nothing at
1:1 (#58). The stroke discs got the same pre-division only in #58's
completeness pass: until then their segment count was constant in the scale,
so device error grew linearly and crossed the 1/255 bar at about 25x — a
900-pixel `beam`. The bar is ruled in [calibration](calibration.md).

**Cubics are flattened uniformly in the parameter, and that is what makes them
deterministic** (`_appendCubic`). `n = ceil(sqrt(M / 8ε))`, where `M` is the
exact maximum of the cubic's linear second derivative; an adaptive subdivision
branches on a float comparison and two platforms disagreeing in the last ulp
would produce different vertex *counts*. `beam`'s open mouth `c2 1 4 1 6 0`
gives `M = 6`, `n = 56`. Relative cubic control points are all relative to the
*current point* (§8.3.6), not chained.

**Arc flags are single characters (hidden-state #25).** `ring` writes
`a32 32 0 10-64 0` — `10` is two flags, large-arc 1 and sweep 0, and `-64` is
the endpoint. A tokeniser that scans numbers uniformly reads ten and takes
`-64` as the sweep flag: a plausible wrong picture, nothing thrown. Upstream
writes this form in four of `ring`'s six arcs. `_Scanner.flag` reads exactly
one `0`/`1`.

**Arcs follow F.6.5 and F.6.6 from the spec text (`_appendArc`).**
- *F.6.6 out-of-range radii (hidden-state #10).* Radii too small for the chord
  scale up by `sqrt(λ)` until the ellipse fits. Implemented in #36/#37 for
  `ring` — where every arc has λ exactly 1, so the branch was dead for two
  tickets — and first fired by `beam` in #38: its closed mouth `a1,0.75 … 10,0`
  has λ = 25, both radii scale ×5 to rx 5 / ry 3.75, and the half-ellipse is
  **29.45** where an uncorrected one would be **1.18** — a factor of 25, so no
  tolerance can confuse them (`beam_raster_test.dart`, "a closed mouth adds the
  arc F.6.6 had to correct").
- *F.6.5's square root is clamped at zero (hidden-state #28).* For an *angled*
  chord equal to the diameter, λ can compute as exactly 1.0 (so F.6.6 does not
  fire) while the radicand lands at −1.3e-16 (measured at r = 1/7); unclamped,
  every vertex is NaN and the render dies in `ceil()`. Inert for every variant:
  `ring` and `beam` (re-checked in #38, after F.6.6 scales the radii) have only
  horizontal chords, where the radicand is exactly zero; `marble` has no arcs at
  all (its two `d` strings use `M L H v h l z`, checked in #41 across the 18
  distinct `d` strings of 600 renders). Only a constructed case exercises it —
  found by searching arc parameters after a mutation removing the clamp
  survived the suite.
- *`largeArc` is dead-valued across the whole corpus (hidden-state #36).* Every
  upstream arc's chord equals its corrected diameter, so the centre offset is
  zero and `sign = largeArc != sweep` multiplies a zero; two mutants on the sign
  rule survived the suite. The case is constructed — chord 20 on radius 15 —
  with Chrome confirming which of the four shapes each flag pair draws.
- *Zero radius* degenerates to a straight line (F.6.6 step 1); radii are taken
  as absolute values.

**`z` ends a subpath (hidden-state #34).** What follows starts a new one from
the same origin; `M0 0h10v10H0zh10v10` is two squares, not one 75-unit contour.
Inert at v1.6.1 — across the 18 distinct `d` strings in all 600 renders `z` is
always last — and valid **as long as that stays true**. A number directly
after `z` throws rather than spinning forever.

**Fills and strokes read the same parse differently.** `parsePath` closes every
subpath and drops ones with fewer than three vertices (a fill closes
implicitly). `parsePathSubpaths` keeps both facts, because for a stroke a
two-point subpath is a line and `z` decides join versus caps.

**A rounded rect is §9.2's equivalent path, not a fifth primitive
(`roundedRectContour`, hidden-states #9, #21).** It is built from the same
`_appendArc` the arc commands use, so its corners inherit F.6.5/F.6.6 and the
tolerance. The radius resolution is three steps and the middle one is the one
that gets skipped: one given radius fills **both** slots, then `rx` clamps to
width/2 and `ry` to height/2 **independently** — not Flutter `RRect`'s
proportional scaling, not `min(w,h)/2` for both. Live since #38: `beam`'s eye
is 1.5 × 2 with `rx="1"` → rx 0.75, ry 1, zero-length straight edges, a full
ellipse. Two ellipses are **4.712** px² where two circles of 0.75 would be
3.534 and two plain rects 6.0, so arithmetic decides it. A negative radius
throws (§9.2 error). The *mask* half of #21 is
[compositing-and-masks](compositing-and-masks.md)'s.

**A stroke outline is a pile of pieces, not one polygon
(`strokePathOutline`).** A quad per segment (`strokeSegmentContour`) and a disc
per joint, unioned by the nonzero rule — no offset-curve arithmetic, no
self-intersection. Every piece must wind the same way or nonzero subtracts and
each joint becomes a hole: the quads are always negatively oriented
(direction-independent), `flattenCircle` is positive, so the discs are
reversed. Measured: without the reversal a straight round-capped stroke loses
exactly its two cap discs. Round joins are not an approximation of `miter`: a
browser strokes the *curve*, whose true offset is the Minkowski sum with a
disc; mitering the chords would reproduce a flattening artefact. The two differ
by `(w/2)(1/cos(θ/2) − 1)` — **1.7e-5 user units** at `beam`'s mouth, four
orders below the coverage bar. Valid **as long as every stroked path is a
flattened smooth curve**; a real corner wants a genuine miter. Duplicate-point
cleanup passes were written, mutation-tested by deletion, survived, and were
deleted as unreachable.

**§11.4's three "paint nothing" cases are three (hidden-state #47).** A single
moveto is never stroked; a zero-length subpath is not stroked under `butt` but
**is** under `round` (a disc); a zero width paints nothing. Normalising a zero
vector before checking the length puts NaN in every vertex, which the scanline
integrator carries silently. `bauhaus`'s line is always `(0,40)–(80,40)`, so
those cases are constructed (#39), and driven through `rasterizeScene` as well
as the helper — driving only the helper left the seam's branch untested, which
a mutation found. #38 added the round-cap half: §11.4's own example of a
zero-length subpath is `M 40,40 c 0,0 0,0 0,0`, a cubic, reachable from the
command `beam` introduced.

**Scope.** The six variants use nine commands — `M H h L l v z a`, and `c` in
`beam` alone — all implemented in both forms. `q`, `s`, `t` throw; so does
`stroke-linecap: square`.

**Input bound.** Path data comes only from the variant builders' constant `d`
strings and arithmetic; segment counts are bounded by radius / tolerance and,
after #58, by the device scale.

## Code
- `lib/src/raster/path.dart — defaultFlatness`
- `lib/src/raster/path.dart — PathSubpath`
- `lib/src/raster/path.dart — parsePath`, `parsePathSubpaths`
- `lib/src/raster/path.dart — flattenCircle`, `rectangleContour`, `roundedRectContour`
- `lib/src/raster/path.dart — strokeSegmentContour`, `StrokeCap`, `strokePathOutline`
- `lib/src/raster/path.dart — _appendCubic`, `_segmentsFor`, `_appendArc`
- `lib/src/raster/path.dart — _Scanner` (`flag`, `number`, `peekCommand`)
- `lib/src/raster/raster.dart — PathContour`
- Tests: `test/raster_path_test.dart` groups "arc flags are characters, not numbers", "the three ring radii come out as the half-discs upstream drew" (incl. "a chord that rounds *past* the diameter still parses"), "straight-line commands" ("a subpath after z is its own contour…"), "the large-arc flag chooses which of the two arcs is drawn", "out-of-range radii are corrected, not rejected (SVG F.6.6)", "cubics…", "a stroked path…", "a rounded rect clamps rx and ry independently (SVG 9.2)", "the flattening tolerance is a stated number, not a feeling"; `test/beam_raster_test.dart` group "beam rasterises to shapes whose areas are arithmetic"; `test/bauhaus_raster_test.dart` group "the stroked line"; `test/raster_scale_test.dart` "a stroked cap keeps its tolerance when the device scale grows".

## Reference behaviour
- Large-arc / sweep flag pairs: Chrome draws the same four shapes as the
  constructed chord-20-on-radius-15 case (hidden-state #36, recorded in
  `raster_path_test.dart`).
- SVG 1.1 F.6.5 / F.6.6, §9.2, §11.4 — implemented from the specification text;
  no external fact store exists in this repo.
- Chrome's own curves are inset from true circular geometry (hidden-state #27);
  that is a fact about the reference, held by [calibration](calibration.md),
  not a defect here.

## Cross-cutting invariants
- [libm-transcendentals](../invariant/libm-transcendentals.md) — sites here: `flattenCircle` (`cos`, `sin`), `_segmentsFor` (`acos`, then `ceil` — a vertex *count*), `_appendArc` (`cos`/`sin` of the axis rotation and of each sample angle, two `atan2`). `_appendCubic` uses only `sqrt` and is exempt.
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the tolerance and every segment-count rule are part of the shipped bytes.
- [construction-time-length-scaling](../invariant/construction-time-length-scaling.md) — the tolerance arrives pre-divided by the device scale.

## Blast radius
- [coverage](coverage.md) — the integrator assumes closed contours under nonzero; a stroke piece wound the other way turns joints into holes.
- [scene-reading](scene-reading.md) — the flatness it passes is pre-divided by the device scale; a change to the tolerance's meaning changes what that division buys.
- [transforms](transforms.md) — geometry is flattened in user space and then mapped; a scale multiplies the flattening error.
- [beam](beam.md), [ring](ring.md), [bauhaus](bauhaus.md), [marble](marble.md) — their arcs, cubics, strokes and rounded rects are what this file draws; packed flags and F.6.6 are live only for them.
- [compositing-and-masks](compositing-and-masks.md) — `RoundedRectMask` is a second §9.2 implementation that deliberately differs from `roundedRectContour`.
- [goldens](goldens.md) — any change to a segment count moves goldens.

## Known holes / open
- **A dead branch with a false comment in `strokePathOutline`.** In the
  `count == 1` arm the round-cap disc is guarded by `subpath.length > 1`, but
  `subpath.length` is `points.length ~/ 2`, i.e. `count` itself, so the
  condition is always false there. The comment's premise is also wrong:
  `M40 40c0 0 0 0 0 0` does not collapse to one point (`_appendCubic` appends
  one, giving two coincident points), so its round caps come from the ordinary
  open-subpath branch — which is why "a zero-length subpath is a circle under
  round" still passes. Confirmed by probing `parsePathSubpaths` at HEAD
  (`M40 40c0 0 0 0 0 0` → `[40, 40, 40, 40]`, `M40 40` → `[40, 40]`,
  2026-10-22). Relatedly, every `z` leaves a one-point open subpath behind
  (`M0 0h10v10z` → a closed triangle plus `[0, 0]`); harmless only because
  that dead guard never paints it.
- `strokeSegmentContour`'s doc still says no element in the six declares a cap
  other than `butt`, then that `beam`'s does — internally inconsistent.
- **The determinism claim at the top of `path.dart` ("two runs on two machines
  produce the same vertices") rests on libm.** `_segmentsFor` takes `ceil` of a
  quotient built on `acos`, so a 1-ulp platform difference can change a vertex
  *count*, not only a vertex position — the failure `_appendCubic`'s doc says
  uniform parameter stepping avoids. Unmeasured; see
  [libm-transcendentals](../invariant/libm-transcendentals.md).
- `z` being last in every `d` (#34) and every arc chord being horizontal (#28)
  are validity conditions on upstream data; a later upstream release can make
  either live.
