# Construction-time length scaling

## The fact
`SceneRaster` composes the device scale into the transform matrix
(`inherited: Affine.scaling(scale, scale)`), so a shape's vertices reach device
pixels through the matrix. A length that does **not** travel through the
matrix must be multiplied by the device scale exactly once, when it is
constructed. A length that **does** travel through the matrix must not be.

## Why it is cross-cutting
The sites are separate functions in `lib/src/raster/scene_raster.dart` that do
not share a primitive. Each makes its own call on which side of the matrix its
number lives:
- `_readMask` scales `x`, `y`, `width`, `height` and `rx` at the end
  (`scale == 1 ? shape : … * scale`), because the mask is applied in device
  space;
- `_readLinearGradient` scales `x1`, `y1`, `x2` and `y2`, because
  `LinearGradientPaint.colourAt` projects the **device** pixel centre;
- `_readFilters` leaves the filter region in viewBox units, because it is
  carried by the referencing element's matrix (SVG §15.7.2). Scaling it here
  would scale it twice;
- `SceneRaster` divides the flattening tolerance, `defaultFlatness / view.scale`,
  the inverse case: a device-space error bound handed to user-space flattening.

Choosing the wrong side at any one site is invisible at scale 1, and scale 1 is
where every golden lives ([variant-design-size](variant-design-size.md)).

## Territories it holds in
- [scene-reading](../territory/scene-reading.md) — `_readMask`, `_readLinearGradient`, the flatness division
- [compositing-and-masks](../territory/compositing-and-masks.md) — `RoundedRectMask` and gradient sampling in device space
- [filters](../territory/filters.md) — the region, which must stay unscaled
- [path-geometry](../territory/path-geometry.md) — the tolerance the division protects
- [coverage](../territory/coverage.md) — every scaled length lands on these integrators

## What a violation looks like
At any device scale other than 1:
- an unscaled gradient axis crowds the whole ramp into the top-left `1/scale`
  of the image;
- an unscaled mask clips a fraction of the avatar;
- a doubly-scaled filter region clips the blur in the wrong place.

The first of these happened. When #58 introduced arbitrary scale, the gradient
axis was missed. It was measured on `sunset` at 2x, box-filtered back to 1:1:
**108/255** off across whole interior rows. The goldens were all at scale 1, so
none of them showed it (#58, recorded in theflow.md @ 0593e28 and
[scene-reading](../territory/scene-reading.md)).

## Discovery history
- #58: the gradient axis miss above.
- #41: the region's "viewBox, not the target" rule (`SceneRaster`'s own
  comment).
- Promoted to an invariant at map init (maintainer, 2026-10-22).

## Where it will recur
If a new reader in `scene_raster.dart` turns an attribute into a length, a
point or a radius, it is subject to this: a radial gradient, a pattern, a
clip path, a `stroke-width` read outside the matrix. Decide which side of the
matrix it lives on, and add a case at a non-unit scale. A golden cannot see it.
