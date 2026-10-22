# filters

## What it is
`marble`'s layer path, the one thing in the package that does not composite
straight onto the destination. `_readFilters` validates upstream's
`<filter>` chain and reduces it to a blur sigma and a region;
`_shapesOf`'s `blurSigma` / `filterRegionQuad` / `blendMode` resolve them per
element in the element's own space; `_drawThroughLayerSteps` draws the shape
into a padded float layer, blurs it with SVG 1.1 §15.17's three-box algorithm,
clips the output to the region, and composites once — through
`RasterBlendMode` (`normal` or `overlay`).

## Governing decisions
**None.** The rules are SVG 1.1 §7.10, §15.7.2, §15.7.5, §15.17 and CSS
Compositing and Blending Level 1, read from the text, plus measurements
against Chrome recorded in theflow.md and in `docs/agents/lessons.md` ("A
filter's units are the element's, not the canvas's (#41)", "One sentence
governed two values and the port applied it to one (#41)").

## Design model
**The chain is validated as a whole, then reduced to one number
(`_readFilters`).** Upstream writes exactly
`feFlood flood-opacity="0"` + `feBlend in="SourceGraphic" in2=<flood>` +
`feGaussianBlur stdDeviation="7"` — a blur and nothing else, but only because
the first two are *checked* to be the no-ops they look like. A flood that
paints, a blend reading anything but `SourceGraphic` over the flood's result,
a blend `mode` other than `normal`, or a blur whose `in` is not the blend's
result throws. So do: a chain of any other shape, `filterUnits` other than
`userSpaceOnUse`, `color-interpolation-filters` other than `sRGB` (the SVG
default is linearRGB and would need a gamma pass), a missing or negative
`stdDeviation`, and a `filter="url(#…)"` naming no filter (a browser would
render the element *unfiltered* — a sharp blob where upstream draws a blurred
one). A `<path>` with fill, stroke and filter throws, because SVG blurs the
composited element.

**Sigma is in the element's user space, which includes its own `transform`
(`blurSigma`).** §15.7.2's "user coordinate system in place when the filter is
referenced" is the transformed one, so `stdDeviation="7"` under `scale(1.2)`
is **8.4** device pixels (times the device scale since #58). Taking 7
literally measured **27/255** against Chrome; scaling took the same comparison
to **1/255**. Swept against Chrome's render of the same blob, the error bottoms
out at 8.4–8.5 (sigma 7.0 worst 27; 8.0 worst 15; 8.5 worst 12, mean 0.76;
9.0 worst 10, mean 1.00). The scale is read as the matrix's column norms; they
must agree to 1e-9, because a Gaussian is isotropic only under a similarity —
a non-uniform transform would need an elliptical kernel and is refused rather
than averaged. This is also why [scene-reading](scene-reading.md) refuses a
non-uniform target.

**The filter region (hidden-state #11).** With no `x/y/width/height` the
region defaults to **-10% / -10% / 120% / 120%**, and under `userSpaceOnUse`
those percentages resolve against the **viewport**, not the bounding box
(§7.10): `(-8, -8, 96, 96)` for `marble`'s 80 × 80 viewBox. Those numbers are
then coordinates in the **referencing element's** space (§15.7.2, the same
sentence that governs `stdDeviation`), so the element's transform moves,
scales and rotates the region — under a rotation its device image is a quad
(`filterRegionQuad`, handed over as a contour). It clips the **output only**
(§15.7.5): content outside still blurs in; it just cannot be seen out. The
region is resolved from the viewBox, not the device size, because the matrix
already carries the device scale.

The row's history is the lesson. **It said "of the bbox" from #1 to #41 and
nothing could catch it** — `marble` was the only filtered variant and was
unported. Measured in Chrome when #41 opened it: a 10 × 10 rect at (35, 35)
blurred with no region renders identically to one given
`x="-8" y="-8" width="96" height="96"`, ink 18.25…61.75, unlike the bbox
reading's hard cut at 34…46; a bar spanning x = −40…20 in a region starting at
x = 6 is cut to nothing below 6 and identical to an unclipped render at every
x ≥ 6. **And it was wrong twice:** the #41 completeness pass found the port
applying §15.7.2 to the sigma and not to the region. Reproduced in Chrome with
a control both readings must agree on: `region x=0 w=20` renders ink 0..19
untransformed, 0..39 under `scale(2)` and 40..59 under `translate(40 0)` — the
transformed reading, twice. On the variant, Chrome clips
`marble-clara-square` by 23 pixels where the port clipped none. **Live only
for `square: true`**: with the disc mask the region cuts nothing the mask has
not already cut (pinned by "and marble's own region does not cut anything").

**The region clip is antialiased.** It is covered by the same scanline
integrator as every shape ([coverage](coverage.md)) — one implementation, not
two. A binary pixel-centre test measured **11/255** at the boundary where
Chrome shades it; the antialiased one left 9.

**The layer is bigger than the canvas (`_drawThroughLayerSteps`).** `marble`'s
second blob reaches x ≈ 89 on an 80-wide target once its scale applies, and a
blur pulls that back into view; rasterising only `[0, width)` drops it and the
edge is quietly wrong. The layer is padded by `blurReach(d)` =
`3d/2 + 1` on every side (support of three boxes is `3d − 2`, rounded up with
a pixel to spare) — 25 px at sigma 8.4 (d = 16). It is **premultiplied float**
RGBA: no byte round-trip between draw and blur, so the layer rounds once, at
the composite (the counterpart of [compositing-and-masks](compositing-and-masks.md)'s
per-shape rounding, hidden-state #23). Blurring premultiplied keeps a flat fill
its colour exactly; an sRGB and a linearRGB blur of one flat colour agree
because only alpha varies. A translucent colour is translucent before it is
blurred (`put` multiplies colour alpha by coverage); shapes within one layer
would source-over each other, though every filtered element upstream writes is
one path. A filtered `<rect>` is unreachable (`filter`/`style` are on `<path>`'s
allow-list only) and its branch throws — the #41 refuting lens replaced a
32-line routine with a throw and the suite stayed green.

**The blur is §15.17's algorithm, not an approximation of it.**
`gaussianBoxSize` is `floor(s · 3·sqrt(2π)/4 + 0.5)`. An odd `d` is three boxes
of `d` centred; an even one is two of `d` on the pixel boundaries and one of
`d + 1` centred, so an even box does not shift the image. `_boxPassSteps` runs
horizontal then vertical, as running sums (O(n) per pass), with transparent
black outside the buffer. `marble`'s `scale(1.2)` gives d = 16, so the even
branch is exercised and mutating its widths dies. **The even branch's two
half-pixel boxes can be swapped and nothing can tell** — box convolutions
commute, so clear of the buffer edge the two orders agree to 0.0 exactly and
diverge (up to 3.75/255) only when mass is pushed off index 0, which the
padding makes unreachable. Recorded rather than tested (#41 refuting lens): a
test that cannot distinguish two implementations is an unfalsifiable
distinction, not a weak test.

**Blend modes (`RasterBlendMode`, `blendMode`).** `marble`'s second blob
declares `style="mix-blend-mode:overlay"` — CSS Compositing, not SVG. The
`style` attribute is matched whole, not searched: nothing else in the six
writes a `style`, and a substring match would let a second declaration through
unread. Overlay is HardLight with swapped arguments; verified against Chrome:
`overlay(#808080, #3399CC)` = (52, 153, 204). `RasterImage.blendSource`
applies CSS's general formula, so where the backdrop is transparent the source
passes through unchanged and where it is opaque the blend function decides —
which is why the overlay blob looks plain against transparent corners and
tints only over the background. An opaque white backdrop returns white for
every source. A shape with a blend mode but no filter takes the layer path
with d = 0 and no padding.

**Input bound.** One filter per variant, two filtered paths. The layer is
`(w + 2·pad) × (h + 2·pad) × 4` doubles — about 86 bytes per output pixel —
allocated before the first yield; that unbanded allocation is
[banded-rasterisation](banded-rasterisation.md)'s. Nothing bounds sigma beyond
`stdDeviation ≥ 0`; pad grows linearly with it.

## Code
- `lib/src/raster/scene_raster.dart — _readFilters`, `_Filter` (`sigma`, `region`)
- `lib/src/raster/scene_raster.dart — _shapesOf` (`blurSigma`, `filterRegionQuad`, `blendMode`; the fill + stroke + filter refusal)
- `lib/src/raster/scene_raster.dart — _defsAttributes` (filter and primitive entries)
- `lib/src/raster/raster.dart — RasterShape` (`blurSigma`, `blendMode`, `filterRegion`, `needsLayer`)
- `lib/src/raster/raster.dart — RasterBlendMode` (`apply`), `RasterImage.blendSource`
- `lib/src/raster/raster.dart — gaussianBoxSize`, `blurReach`, `_boxPassSteps`, `_drawThroughLayerSteps`, `_coverPolygonSteps`
- Tests: `test/marble_raster_test.dart` groups "the three-box approximation is the spec's, not an approximation of it", "the blur is measured in the element's own space", "the offscreen layer is bigger than the canvas", "overlay blends against the group, and only the group", "the filter region", "the scene seam still refuses what it cannot draw"; `test/raster_scale_test.dart` "the default filter region reads the viewBox the right way round".

## Reference behaviour
- **The blur is the one mechanism here that can meet the ≤1/255 bar.** §15.17
  specifies the algorithm, so both sides compute the same convolution: on a
  step edge our kernel and Chrome's agree to **0–1/255** for every sigma 3–12.
  Above about 12 Chrome stops following it — **31/255 at sigma 20, 65 at sigma
  30** (Skia downsamples large radii). `marble`'s sigma at 1:1 is inside that
  range (theflow said 8.4–9.1; by code it is 7 × {1.2, 1.3, 1.4, 1.5} =
  8.4–10.5).
- Sigma in element space: 27/255 → 1/255 against Chrome (#41).
- Region: viewport percentages, element space, output-only — three Chrome
  constructions plus `marble-clara-square`'s 23-pixel clip (#41).
- `marble-clara-square`'s worst edge is **9/255** against 71 on five other rows
  at the same pixel (71, 15) — that 71 is the mask's own curve (#27), and
  dropping the corner radius removes it. **It read 5/255 before the region was
  corrected, and that smaller number was the feature being absent** — the clip
  was not happening. A calibration number going *down* is not evidence until
  the capability is known to be running.
- For a blurred variant the calibration's interior statistic is structurally
  vacuous (every pixel is "edge"); `marble`'s only interior mismatches, 2–5 of
  6400 at exactly 1/255, sit where overlay saturates flat. That reading is
  [calibration](calibration.md)'s (hidden-state #42).

## Cross-cutting invariants
- [libm-transcendentals](../invariant/libm-transcendentals.md) — `blurSigma` takes `sqrt` of matrix entries that are `cos`/`sin` of `marble`'s rotation, and `gaussianBoxSize` then **floors** it: a 1-ulp platform difference near a boundary changes the box size `d` by one, not a coverage byte.
- [frozen-selector-output](../invariant/frozen-selector-output.md) — box sizes, pass order and the layer's single rounding are shipped bytes.
- [variant-design-size](../invariant/variant-design-size.md) — the default region is resolved from the viewBox side.
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md) — the filter chain marble writes is validated whole; a primitive or attribute outside it throws.
- [construction-time-length-scaling](../invariant/construction-time-length-scaling.md) — the region rides the matrix and must stay unscaled.

## Blast radius
- [marble](marble.md) — the only filtered and blended variant; its `scale`, `rotate` and `square` decide sigma, d's parity and whether the region clips.
- [scene-reading](scene-reading.md) — refuses non-uniform targets because of this territory's isotropy assumption; resolves region and sigma per element.
- [transforms](transforms.md) — sigma and region are read through the element's matrix; a skew or non-uniform scale breaks both.
- [compositing-and-masks](compositing-and-masks.md) — the layer composites via `blendSource`, then the mask applies to the whole group including the blurred blobs.
- [coverage](coverage.md) — the shape and the region both use `polygonCoverageSteps`.
- [banded-rasterisation](banded-rasterisation.md) — the layer allocation and box passes are its biggest unbanded and banded costs.
- [calibration](calibration.md) — the blur is the one place the bar is met; changing the kernel changes what that row means.

## Known holes / open
- **Two recorded Chrome measurements disagree.** `gaussianBoxSize`'s doc says
  "measured against Chrome at sigma 56 device px (d = 105): **0/255** across
  eleven samples of a step edge"; theflow records Chrome departing from §15.17
  above sigma ≈ 12 (31/255 at 20, 65 at 30). Not reconciled by the code; one of
  the two constructions differs in a way nobody wrote down.
- **At a device scale above 1 the blur leaves the range where Chrome follows
  the spec.** Sigma is multiplied by the device scale, so at a 2.625 device
  pixel ratio `marble`'s sigma is about 22–28 — past the ~12 where Chrome
  downsamples. Our output stays §15.17-exact and scale-consistent
  (`raster_scale_test.dart` box-filters marble back within 3/255), but agreement
  with Chrome there is unmeasured. Inferred from the two recorded measurements.
- `_drawThroughLayerSteps`' doc still says "a blur of sigma 7 pulls that back
  about 20 pixels" and "x ≈ 89 and y ≈ 100 once its `scale(1.3)`" — written
  before sigma was read in element space (8.4+ → reach 25+).
- `marble_raster_test.dart`'s "clips the output…" comment says the region is
  inert for `marble` because the mask has already cut everything outside it —
  true for the disc mask, false for `square: true` (23 pixels, above).
- Nothing bounds `stdDeviation`; the layer's padding and memory grow with it.
