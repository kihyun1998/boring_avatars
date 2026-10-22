# Variant design size

## The fact
Each variant draws in its own fixed viewBox: `ring` 90, `beam` **36**, and
`bauhaus`, `marble`, `pixel` and `sunset` 80 (`_size` in each
`lib/src/variants/<name>.dart`). That side length is what "1:1" means for the
variant. A golden, a calibration case, and the cheap rasterization path all
assume the target equals that side. `size` reaches only the `<svg>`'s
`width`/`height`, never the viewBox.

## Why it is cross-cutting
The number is written by hand in places that do not import it from each other:

- `_size` in each of the six builders (`buildRingScene`, `buildBeamScene`, …),
  which writes the viewBox;
- the target sizes in `test/support/golden_cases.dart` (80, 90 and 36, typed
  per case), which `tool/golden/generate.dart` and every variant raster test read;
- the target sizes in `tool/calibrate/compare.dart`'s cases.

The device scale itself is derived, not copied: `_resolveScale` in
`scene_raster.dart` divides the target by the viewBox. So the fast path that
depends on scale 1 (`Affine.isTranslationOnly`) follows the viewBox
automatically. The hand-typed copies do not. If a builder's `_size` changes, or
a new variant arrives with a new one, and the roster does not change with it,
every golden for that variant is silently rendered at a non-1:1 scale. The
goldens still compare equal to themselves, so nothing fails.

## Territories it holds in
- [ring](../territory/ring.md), [beam](../territory/beam.md), [bauhaus](../territory/bauhaus.md), [marble](../territory/marble.md), [pixel](../territory/pixel.md), [sunset](../territory/sunset.md) — `_size`
- [goldens](../territory/goldens.md) — `golden_cases.dart` target sizes
- [calibration](../territory/calibration.md) — `compare.dart` case targets
- [coverage](../territory/coverage.md) — the closed-form rect path is reachable only at scale 1, which is why cost is discontinuous at the design size (`docs/performance.md`)
- [scene-reading](../territory/scene-reading.md) — `_resolveScale` derives the device scale from the viewBox
- [compositing-and-masks](../territory/compositing-and-masks.md) — hidden-state #24's seams appear exactly when the target is not a whole multiple of the tile grid at the design size
- [filters](../territory/filters.md) — the default filter region is resolved from the viewBox side
- [public-svg-surface](../territory/public-svg-surface.md) — `size` reaches `width`/`height` only, never the viewBox
- [crosscheck](../territory/crosscheck.md) — both documents carry the same viewBox, so the comparison is at a common size regardless
- [pixel-placement](../territory/pixel-placement.md) — the buffer lands one pixel per pixel only at whole device pixels; the cheap path additionally needs the design size

## What a violation looks like
A golden generated at 80 for `beam` would be the beam drawing scaled by 80/36.
Its tile and abutting-edge behaviour then differs from the 1:1 reference, and
no test compares it against anything but itself.

Before #58 the rasterizer refused a target that did not match the viewBox, so a
wrong size surfaced as a throw. #58 made the rasterizer scale to any uniform
target, so it is now silent.

## Discovery history
- Hidden-state #26 said "the other five are 80" until #38 measured `beam`.
  The fact sat in `avatar-beam.js:4` (`const SIZE = 36`) and in all 80 of
  `beam`'s fixture renders, and nothing read either (measured #38,
  theflow.md @ 0593e28). The war story is in `docs/agents/lessons.md`,
  "A row nobody can act on yet is a row nobody checks".
- `golden_cases.dart`'s own header still says "`ring`'s is 90 where the
  others are 80", which is the same pre-#38 sentence. The per-case sizes below
  it are right (36 for `beam`). Read at HEAD 0593e28.

## Where it will recur
Anything that renders a variant "at its own size" is subject to this: a new
tool, a new golden case, a new calibration row, or a README gallery that wants
pixel-exact output. Read the number from the builder's viewBox, or from the
list above, never from "the package's size". A new upstream variant adds a
fourth value here.
