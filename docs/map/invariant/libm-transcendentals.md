# libm transcendentals

## The fact
`CLAUDE.md` invariant 4 promises the same bytes on every platform. The
rasterizer, however, calls `dart:math`'s `cos`, `sin`, `atan2`, `acos` and
`pow` with non-integer arguments, and IEEE-754 does not require those to be
correctly rounded (only `sqrt` and `+ − × ÷` are). On the VM they go to the
platform libm (UCRT, glibc or Apple's); on web they go to JS `Math.*` (V8's
fdlibm port). Two platforms may differ by an ulp. **No divergence has been
observed, and nothing in the repo could observe one.**

## Why it is cross-cutting
The calls sit in separate files that share no primitive. There is no single
"trig" function to replace:

- `path.dart` — `flattenCircle` (`cos`, `sin`), `_appendArc` (`atan2`, `cos`,
  `sin`), and `_segmentsFor`, the flattening step count (`acos`);
- `transform.dart` — `Affine.rotation` (`cos`, `sin`). Since #39 this places
  every rotated rect and line, not only how finely a curve is chopped;
- `colour_spaces.dart` — the five transfer functions (`pow`) and `lchToAb`
  (`cos`, `sin`). Since #95 a 1-ulp difference can flip a **palette** byte,
  not only a coverage byte.

**Exempt**, and why:
- `jsGetDigit`'s `math.pow(10, ntn)` in `utilities.dart` takes two integers and
  is exact.
- `sqrt` is correctly rounded by IEEE-754.
- The colour matrices are derived using only `+ − × ÷`.
- `rotate(0)` uses `cos(0)` and `sin(0)`, which are exact everywhere.

A fix at one site would leave the others, so the question is the package's, not
any one territory's.

**Two sites can change a count, not only a byte value** (read from the code
at 0593e28, 2026-10-22):
- `_segmentsFor` takes the `ceil` of a value built on `acos`, so a vertex count
  can differ between platforms.
- `gaussianBoxSize` takes the `floor` of a sigma whose scale is
  `sqrt(a² + b²)` of a matrix built from `cos`/`sin` (marble's rotation, read
  in `scene_raster.dart`). A one-ulp difference near a boundary changes the
  blur box size by one.

These are more severe than the coverage case below, because a changed count
moves many pixels at once.

## Territories it holds in
- [path-geometry](../territory/path-geometry.md) — `flattenCircle`, `_appendArc`
- [transforms](../territory/transforms.md) — `Affine.rotation`
- [filters](../territory/filters.md) — `gaussianBoxSize` floors a sigma derived from a rotated matrix
- [colour-declarations](../territory/colour-declarations.md) — `colour_spaces.dart` transfer functions, `lchToAb`
- [goldens](../territory/goldens.md) — generated and compared on one machine
- [calibration](../territory/calibration.md) — every recorded Chrome comparison was taken on one platform's libm
- the variants, by what each draws through these calls: [bauhaus](../territory/bauhaus.md) (`Affine.rotation` places every rect and line), [beam](../territory/beam.md) (two rotations, the mouth arc, round caps), [marble](../territory/marble.md) (a nonzero rotation and the mask's arcs), [ring](../territory/ring.md) (six arcs and a circle), [pixel](../territory/pixel.md) (the rounded mask only), [sunset](../territory/sunset.md) (the rounded mask, plus Color 4 palette conversions)
- [gates](../territory/gates.md) — no CI by policy, so no second platform ever runs the goldens

## What a violation looks like
A 1-ulp difference moves a vertex by about 1e-14, coverage by about 1e-14, and
the ×255 product by about 2.5e-12. That flips a byte only where the exact
product sits that close to a rounding boundary. The case that does is
**coverage of exactly 0.5**: `127.5` rounds to 128 in Dart, and
`0.49999999999999994` rounds to 127. The visible symptom would be a golden
that fails on one OS and passes on another, which today would fail nothing,
because the goldens are only ever run on the machine of the day.

## Discovery history
- Hidden-state #48. It has existed since #37 (`flattenCircle`, `_appendArc`).
  #39 widened it to placement via `Affine.rotation`, and #95 widened it to
  colour values. Not measured (theflow.md @ 0593e28).
- The machine itself alternates between Windows and macOS across sessions
  ([gates](../territory/gates.md)). The goldens have therefore been compared on
  both OSes at different times, but never as a deliberate cross-platform run,
  and a pass on each says nothing about values near a boundary.

## Where it will recur
Any new use of a `dart:math` transcendental with a non-integer argument
anywhere on the byte path is subject to this. The validity condition is that
**nobody compares this package's bytes across two platforms**. The day someone
does, the answers on record are to:
1. narrow invariant 4's wording,
2. implement the transcendentals in-package from a fixed polynomial, or
3. add a second-platform golden run.
