# transforms

## What it is
`transform.dart` reads a `transform` attribute string back into an affine
matrix — `translate`, `rotate` (one- and three-argument) and `scale` — and
holds `Affine`, the matrix every shape's vertices are mapped through. It is the
second half of a seam: the scene carries upstream's transform *string*, the SVG
backend emits it verbatim, and only the rasterizer turns it into geometry.

## Governing decisions
**None.** The rules are SVG 1.1 §7.4 / §7.5 read from the specification text,
the source, and dated measurements recorded in theflow.md.

## Design model
**The transform string is the seam, not a convenience.** Upstream builds the
attribute by concatenating numbers into a string, so the variant builders
produce that string (e.g. `marble.dart — _placement`, `beam.dart`'s wrapper and
face transforms), [svg-emission](svg-emission.md) writes it verbatim, and
`parseTransform` is the only place it becomes numbers. A rasterizer that read
`translateX`/`rotate` off the variant would be a second copy of the placement,
free to drift from the one the emitter ships.

**A list post-multiplies — the rightmost function applies first
(hidden-state #45).** §7.5: a list is "as if each transform had been specified
separately in the order provided", which the section shows as nested `<g>`. So
`translate(tx ty) rotate(a cx cy)` maps by `T · R`, and the rotation acts on
the shape's own coordinates. §7.4 adds that the transform applies **before**
the element's `x`/`y`/`width`/`height` are read, so the shape is built in its
own space and every vertex is then mapped (`Affine.apply`,
`Affine.transformContour`). Composing the other way is a plausible wrong place
with nothing thrown. `Affine.multiply(other)` is `this · other`, so `other`
applies first. Live for `bauhaus`, `beam` and `marble`, the only variants with
a transform (measured across all 600 renders). **#38 extended it one level
out:** an ancestor `<g>`'s matrix composes as `parent · own`, the ancestor
applying second — implemented in [scene-reading](scene-reading.md)'s
`_collectShapes`.

**`rotate(a cx cy)` is not a fourth primitive (hidden-state #46).** §7.4
defines it as exactly `translate(cx, cy) rotate(a) translate(-cx, -cy)` and
gives no closed form; `_build` composes the three. Its test asserts one
spelling against the other rather than against hardcoded numbers. Corollary:
`rotate(0 …)` **is** the identity exactly — `cos(0)` is 1 and `sin(0)` is 0
with no rounding — so the empty name, whose hash is 0, keeps the closed-form
rect integrator ([coverage](coverage.md)). `rotate(360 …)` is not, and upstream
cannot write it: `getUnit(n, 360)` tops out at 359.

**`scale`'s missing second argument copies the first; `translate`'s is zero.**
The two rules sit three lines apart in §7.4 and a shared defaulting helper
collapses them. `beam` writes the one-argument form on every render, so
borrowing `translate`'s rule would squash every wrapper flat. `scale(1)` is
exactly the identity (`beam`'s `wrapperScale` can be 1).

**`isTranslationOnly` is exact equality, on purpose.** It holds when
`a == 1 && b == 0 && c == 0 && d == 1`. That is what lets `rotate(0 …)` keep
the fast path, and what makes every rect a polygon at any device scale other
than 1 (since #58 the walk starts at `Affine.scaling(s, s)`).

**What is implemented.** `translate`, `rotate`, `scale` — the three the six
variants write (`bauhaus` the first two, `beam` and `marble` all three).
`matrix`, `skewX`, `skewY` throw; an empty or all-whitespace list is the
identity, not an error. A post-loop "nothing matched" check was written, could
not fire, and was deleted rather than tested.

**Input bound.** Transform strings come only from the variant builders.

## Code
- `lib/src/raster/transform.dart — Affine` (`identity`, `translation`, `scaling`, `rotation`, `multiply`, `apply`, `inverse`, `isTranslationOnly`, `transformContour`)
- `lib/src/raster/transform.dart — parseTransform`, `_build`, `_implemented`, `_function`
- Callers: `lib/src/raster/scene_raster.dart — _collectShapes`, `_shapesOf`, `SceneRaster`
- Tests: `test/bauhaus_raster_test.dart` groups "the transform list is composed the way SVG 1.1 says" and "a rigid transform preserves what a rigid transform must"; `test/beam_raster_test.dart` group "scale, which `beam` is the first of the six to write", and "a group transform composes with the element's, in that order" / "a group transform inside a group transform composes too".

## Reference behaviour
- SVG 1.1 §7.4 / §7.5, implemented from the text. The nested-group order is
  pinned in `beam_raster_test.dart` by a case where the two orders disagree
  **on canvas** — the obvious construction put the reversed order off the
  edge, where both paint nothing and the test cannot fail; choosing the
  rotation centre fixed that (#38).

## Cross-cutting invariants
- [libm-transcendentals](../invariant/libm-transcendentals.md) — site here: `Affine.rotation` (`cos`, `sin`). Since #39 that places every rotated rect and line, not only curve chopping; `rotate(0)` is exempt. Through `blurSigma`'s column norms the same `cos`/`sin` reach `marble`'s blur box size (see [filters](filters.md)).
- [frozen-selector-output](../invariant/frozen-selector-output.md) — composition order and argument defaults are shipped bytes.

## Blast radius
- [scene-reading](scene-reading.md) — it composes inherited and own matrices and decides `RasterRect` vs `RasterPolygon` by `isTranslationOnly`; both assume this file's multiply order.
- [coverage](coverage.md) — the fast path is reachable only while a zero rotation and a unit scale stay *exactly* the identity.
- [filters](filters.md) — sigma is read from this matrix's column norms and the region is mapped through it; a non-similarity breaks the isotropy assumption.
- [svg-emission](svg-emission.md) — emits the same string verbatim; if the two ever read different strings the backends diverge.
- [bauhaus](bauhaus.md), [beam](beam.md), [marble](marble.md) — the only variants whose placement is a transform.

## Known holes / open
- **`Affine.inverse` is dead code with a stale rationale.** Its doc says it is
  needed to test device pixels against the filter region by mapping them back;
  the region is now a quad covered by the scanline integrator
  (`scene_raster.dart — _shapesOf`'s `filterRegionQuad` → `transformContour`), and nothing in
  `lib/` or `test/` calls `inverse` (grep at HEAD).
- `parseTransform`'s error message still says "`scale` arrives with `beam`"
  although `scale` is implemented.
