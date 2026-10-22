# compositing-and-masks

## What it is
How coverage becomes bytes. `RasterImage` holds a straight-alpha RGBA buffer
and composites each shape onto it (`blend`, and `blendSource` for a layer
result under a blend mode); `rasterizeMaskedShapesSteps` paints the shapes in
document order and then applies the one `RoundedRectMask` to the finished
group; paints (`SolidPaint`, `LinearGradientPaint`) answer the colour per
pixel. This is where the rounding model, the mask model and the gradient
interpolation live.

## Governing decisions
**None.** The rounding and masking models come from reading the source and
from measurements against Chrome recorded in theflow.md, plus one ruling on
seams (#83, below). [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md)
decides which colour a declaration yields (black for an unreadable
`stop-color`), not how it is composited.

## Design model
**The buffer is straight alpha, decided by the calibration.** A browser hands
back straight bytes from `getImageData` and a PNG, so a premultiplied buffer
would differ from Chrome on every antialiased pixel. Premultiplying is one
multiply at the Flutter hand-off; un-premultiplying a rounded byte is lossy.
The cost is hidden-state #29 — straight RGB is meaningless at small alpha, so
comparisons must be premultiplied — which is [calibration](calibration.md)'s.

**A colour's alpha and a shape's coverage multiply** (`blend`, and the layer's
`put`) — the measurement and the rule are
[colour-declarations](colour-declarations.md)'s. Every colour upstream writes
is opaque `#RRGGBB`, so the factor is exactly 1 on real avatars.

**Rounding is once per shape (hidden-state #23, corrected in #37).** Within a
call the channels are accumulated in float and rounded once; across calls each
blend reads back the byte the last wrote, so `k` stacked shapes round `k`
times. That matches the reference: a browser draws each shape of a plain
display list onto an 8-bit surface and rounds as often. The row used to claim
the opposite of what the code does. Measured drift against a single float
accumulation over 1.2M stacks of 2–9 opaque shapes: **2/255 premultiplied**
(16/255 straight at negligible alpha — #29, not a real difference). `pixel`'s
tiles never overlap; `ring` stacks nine; `marble`, `bauhaus`, `beam` two to
four. **The offscreen-layer condition the row reserved was discharged by #41,
the other way:** a filtered shape is drawn into a padded float layer, blurred,
and composited once — the layer rounds *once*, right for the same reason,
because a browser composites a filter result as one image. Measured against
Chrome on the real variant: every remaining interior disagreement is exactly
**1/255**, on at most 5 pixels of 6400. The layer itself is
[filters](filters.md)'.

**Abutting vs stacked shapes (hidden-state #24).** Source-over is right for
shapes stacked on each other and wrong for shapes abutting inside one pixel:
two half-covering rects give **192**, where an exact single-pass rasteriser
gives 255. The row predicted "live" three times from fractional coordinates
alone — `bauhaus` (#39), `beam` (#38), `marble` (#41) — and each time the real
condition, two shapes meeting *edge to edge*, was absent (each lays a
full-canvas background and draws on top, so pairs overlap or are disjoint).
Both remaining inertness arguments named the old `_checkViewBox` 1:1 rule —
`pixel`'s tile edges integer-aligned at 1:1, `ring` abutting along y = 45 at
90×90 — and **#58 deleted that rule and made the row live for the first
time.** Measured on the branch, interior pixels clear of the mask rim with
alpha < 255: `pixel` 80→0, 84→452, 100→556, 101→1025, **210→1944**, 128→0;
`ring` 101→36; worst gap 80/255 (`pixel`), 63/255 (`ring`). `pixel`'s
10-unit tiles land mid-pixel whenever the target is not a multiple of 8, and
210 is the 2.625 device pixel ratio a widget asks for.
**Ruled in #83: live, and the reproduction is correct; the code does not
change.** A browser compositing a plain display list conflates the same way —
measured, not inferred: `tool/calibrate` grew a square `pixel` at 100, the
only case with no curve, and both sides produce **784** partial pixels with
**zero** where Chrome is opaque and we are not; worst edge delta 3/255.
`pixel` at 210 agrees the same way. The residues left in that run (`pixel`
100 rounded, 1 px; `ring` 101, 8 px) all sit on the mask curve, which is #27,
a separate question. Valid **as long as every drawn edge falls on a pixel
boundary**, and only where two shapes meet edge to edge.
`raster_scale_test.dart` carries the count and the agreement.

**The mask applies to the composited group, not to each shape
(hidden-state #33, fixed in #37).** SVG composites a `<g mask>`'s children,
then scales the result's alpha by the mask. Folding the mask into each shape's
coverage applies it once per shape: two opaque shapes on a pixel a mask
half-covers give **192** where one gives 128. `rasterizeMaskedShapesSteps`
multiplies alpha by `RoundedRectMask.coverageAt` once, after every shape — a
second rounding, faithful because a browser renders the masked group into an
8-bit layer and then multiplies. A pixel the mask takes to alpha 0 is cleared
to `0,0,0,0`, because Chrome writes zero and a byte golden needs one answer;
the fix moved 8 pixels of `pixel`'s goldens, all fully transparent and
straight-RGB-only. Inert for `pixel` and `ring` (mask-edge pixels reached by
at most one shape); **live for `marble`, `bauhaus` and `beam`**, which lay a
background under a shape crossing the mask edge. First exercised by `bauhaus`
in #39 (`bauhaus_raster_test.dart`, pixel (14, 70), against a
background-only render); confirmed live for `beam` in #38 — the crosscheck's
0-pixel bar over 160 `beam` cases would fail on the per-shape reading.

**Content outside the masked group (hidden-state #32)** is drawn unmasked by a
browser; the walk throws on it rather than dropping it — see
[scene-reading](scene-reading.md). Inert across all six.

**The mask element (hidden-states #22, #35).** `pixel` declares
`mask-type="alpha"`; the other five declare nothing, which in SVG is a
*luminance* mask. Inert while every mask shape is `#FFFFFF`, where luminance
and alpha both come to 1, so `_readMask` throws on any other mask-type and on a
luminance mask whose fill is not the literal `#FFFFFF` — a byte question, not a
colour one. `maskUnits` other than `userSpaceOnUse` throws (the other value
reinterprets every number as a bbox fraction); a mask region that would clip
its own shape throws; a `mask="url(#…)"` naming anything but the scene's mask
throws. All inert at v1.6.1 — one mask, `userSpaceOnUse`, region equal to the
shape. The checks live in [scene-reading](scene-reading.md)'s `_readMask`.

**`RoundedRectMask` is a second §9.2 implementation, and it deliberately
differs.** It clamps one radius jointly — `min(rx, w/2, h/2)` — where
`roundedRectContour` ([path-geometry](path-geometry.md)) clamps `rx` and `ry`
independently. Safe only while every mask is square (all six are), and it buys
closed-form coverage exact in x: 64 horizontal slices, each solved for its
left and right edge, error falling as 1/slices². A 16×16 grid measured
**4/255** against a 512× reference and could not have met the bar. A mask
declaring `ry` throws (`_maskShapeAttributes`), so the joint clamp cannot
silently take circular corners where §9.2 says elliptical. This is the mask
half of hidden-state #21, still inert. `pixel` asks for `rx` 160 on an 80-wide
rect — the clamp is how upstream turns a rect into a circle.

**Gradients (`LinearGradientPaint`; mechanism half of hidden-state #41).**
Sampled at the **device** pixel centre (`px + 0.5`) projected onto the
`x1,y1 → x2,y2` axis and rounded to nearest; the axis must already be in
device units, which is [scene-reading](scene-reading.md)'s job (#58's
108/255). `spreadMethod="pad"` is meant to need no branch — the code says the mix's
clamp and the loop's fall-through return the end stops, and two explicit
clamps were deleted in #40 because no mutation could kill them. **Only the
high side holds** (see Known holes). A zero-length axis paints the last
stop; two stops at one offset step rather than divide by zero. That the mix is
sRGB and that alpha mixes straight (measured `191,128,191`) is
[colour-declarations](colour-declarations.md)'s. Measured: Chrome's own
gradient dithers within **0.987** of the exact interpolation, and ours lands
**≤1/255** from Chrome across all 4548 gradient pixels (58.6% exact, 41.4% off
by one); what that means for the bar is [calibration](calibration.md)'s.

**Input bound.** Shapes and paints come from the variant builders; the buffer
is `width × height × 4` bytes for the caller's target.

## Code
- `lib/src/raster/raster.dart — RasterImage` (`blend`, `blendSource`)
- `lib/src/raster/raster.dart — RasterColour`
- `lib/src/raster/raster.dart — RoundedRectMask` (`radius`, `_halfWidthAt`, `coverageAt`, `_slices`)
- `lib/src/raster/raster.dart — RasterPaint`, `SolidPaint`, `LinearGradientPaint` (`colourAt`, `_sample`)
- `lib/src/raster/raster.dart — rasterizeMaskedShapes`, `rasterizeMaskedShapesSteps`
- `lib/src/raster/scene_raster.dart — _readMask` (producer of the mask)
- Tests: `test/raster_path_test.dart` groups "the mask applies to the composited group, not to each shape" and "a linear gradient projects onto its own axis"; `test/raster_alpha_test.dart` groups "a colour's alpha multiplies the shape's coverage" and "a gradient interpolates alpha the way Chrome does"; `test/raster_scale_test.dart` "abutting tiles seam at a fractional target — measured, not ruled" and "and Chrome seams identically, which is what settles #24"; `test/bauhaus_raster_test.dart` "the mask scales the composited group, not each shape"; `test/pixel_raster_test.dart` "a mask-type this rasterizer cannot honour is refused", "a luminance mask that is not white is refused", "the mask integrator totals the right area", "and every individual pixel agrees with the other integrator"; `test/sunset_raster_test.dart` "every row matches an exact sRGB interpolation of its two stops".

## Reference behaviour
- Per-shape rounding matches Chrome's plain display list; the filtered layer's
  single rounding leaves ≤5/6400 interior pixels at exactly 1/255 (#41).
- Seams at fractional targets: Chrome and ours both 784 partial pixels on
  square `pixel` at 100, zero opaque-vs-translucent (`tool/calibrate`, #83).
- Colour alpha × coverage and straight gradient alpha: measured in Chrome
  (#62) — recorded in [colour-declarations](colour-declarations.md).
- Gradient: ≤1/255 from Chrome over 4548 pixels; Chrome within 0.987 of exact
  (#40/#41 era, hidden-state #41).

## Cross-cutting invariants
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md) — the literal `#FFFFFF` mask fill is checked by this mask's producer, `_readMask`.
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the rounding points and the mask's slice count are shipped bytes.
- [variant-design-size](../invariant/variant-design-size.md) — #24's seams appear exactly when the target is not a whole multiple of the tile grid at the design size.
- [construction-time-length-scaling](../invariant/construction-time-length-scaling.md) — the mask and gradient sampling live in device space.

## Blast radius
- [coverage](coverage.md) — coverage arrives here as source alpha; the abutting-seam behaviour is the two together.
- [filters](filters.md) — the layer composites through `blendSource`; its single rounding is the counterpart of the per-shape model here.
- [scene-reading](scene-reading.md) — `_readMask` decides which masks reach `RoundedRectMask`; widening it (non-square, `ry`, non-white) breaks the joint clamp's validity.
- [path-geometry](path-geometry.md) — `roundedRectContour` is the other §9.2 reading; the two must not be "unified" without the mask's closed form.
- [colour-declarations](colour-declarations.md) — what colour a stop or fill yields; this file only mixes it.
- [calibration](calibration.md) — straight-alpha storage is why it compares premultiplied; the gradient's ≤1/255 is the one place the bar is met.
- [widget-lifecycle](widget-lifecycle.md) — receives the straight-alpha buffer and premultiplies at the hand-off.
- [pixel](pixel.md), [ring](ring.md), [bauhaus](bauhaus.md), [beam](beam.md), [marble](marble.md), [sunset](sunset.md) — #33 is live for `marble`/`bauhaus`/`beam`, #24 for `pixel`/`ring` at fractional targets, gradients for `sunset`.

## Known holes / open
- `RasterImage.blend`'s doc still says `marble`'s offscreen layer makes "the
  scene seam throw on it today" — stale since #41 implemented it.
- `RoundedRectMask` cannot represent a non-square mask or a separate `ry`; the
  day one appears, this class is what has to move (guarded by a throw).
- The #24 residues on a mask curve (`pixel` 100 rounded, `ring` 101) are #27's
  question, not ruled here.
- An alpha mask's fill is not checked (see [scene-reading](scene-reading.md)).
- **Below the first stop the gradient extrapolates instead of padding.**
  `LinearGradientPaint._sample`'s `mix` clamps the *channel* to 0–255, not the
  factor `f`, so for `t` below the first offset the colour runs past the first
  stop until a channel saturates. Probed at HEAD (2026-10-22): stops
  `(100,100,100)` → `(200,200,200)` on axis y 4→6 give 0 at row 0 and 75 at
  row 3, where pad gives 100; above the last stop the fall-through pads
  correctly (200). The pad test ("past either end the gradient pads…") cannot
  see it because its stops are red → blue, at channel extremes, where
  extrapolation and padding clamp to the same byte — the explicit clamps #40
  deleted as unkillable were unkillable for that reason. **Unreachable from
  `sunset` at any integer target**, as far as the reading goes: its bottom
  gradient starts at y = 40 of 80, which lands at N/2 device pixels for an
  N-pixel target — always a pixel boundary or a pixel centre, so no sampled
  centre has `t < 0`. A defect in this package, not upstream; not fixed here.
