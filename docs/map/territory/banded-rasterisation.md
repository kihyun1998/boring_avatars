# banded-rasterisation

## What it is

How one drawing is driven two ways without two implementations of it. The
rasterizer's work is written once, as `sync*` generators that `yield` once per
band (an image row, a filter-layer row, a box-blur line); `rasterizeScene`
drains them on the calling thread, and `rasterizeSceneAsync` drains them while
handing the event loop back with a **macrotask** every `defaultRasterSlice`
(8 ms). It exists for the web, where Flutter's `compute` has no isolate and runs
the callback on the main thread; on native the same async rasteriser runs inside
`compute`'s isolate, where the yields cost no frame. It also owns the slice
constant shared with the widget's premultiply loop.

## Governing decisions

**None.** No ADR. Two user rulings in theflow (to be deleted) govern it; they
are recorded here with what was shown, chosen, and costs, and are theirs to
reverse.

- **The web half joins `0.1.0` — user ruling, 2026-08-10**, hours after the
  ruling that had deferred it ([widget-lifecycle](widget-lifecycle.md), "The
  widget's execution model").
  - *What they were shown:* the twelve-run browser table (`compute` moving
    nothing on web; a 320-logical avatar at ratio 1.5 freezing the tab ~2 s
    under dart2js and ~5 s under WasmGC; `--wasm` 2.2–2.6x *slower*), the two
    unchosen candidates (banded rasterisation; the browser's own SVG renderer
    via a platform view), and the option of shipping without a web fix since
    nothing gets worse.
  - *What they chose:* the web fix in `0.1.0`. The rejected option was cheaper
    and rejected on purpose — the same shape as the reversal that put the
    widget in `0.1.0`.
  - *Which candidate is **not** their call, recorded on purpose:* they were
    asked, and the question was withdrawn. The browser's SVG renderer is
    **foreclosed by invariant 4** ("the same bytes on every platform … and
    rendering backend") — the same sentence that forecloses `Canvas`, one
    level further out. Choosing it would first require ruling that the
    determinism guarantee does not cover web, a change to what the package
    *is*; it was never put in those terms. If it ever is, this paragraph is
    what has to be overturned.
  - So **banded rasterisation is a derivation**: it falls to a better
    derivation, not a re-vote. A general web-worker path was rejected outright
    (not deferred): Flutter web has no isolate equivalent, so it means
    compiling the rasteriser a second time — two copies of the geometry, the
    divergence seed `CLAUDE.md` names.
  - *What it costs (stated before starting):* a rasteriser restructure;
    `marble`'s Gaussian is whole-image and does not band without overlap; the
    `Float64` layer must stay alive across yields, so peak memory lasts longer;
    and `lib/src/raster/` buys a completeness pass (where #58's found the
    missed gradient axis and five mutation gaps).
  - *What it does not decide:* native keeping `compute` (settled, unaffected);
    band size, which is an internal constant like the flattening tolerance, not
    caller policy.
- **The 8 ms default — measured, not reasoned** (2026-08-10, the same ruling's
  verification). The shipped 4 ms ("comfortably inside a frame") was the worst
  value on the curve; see Design model. War story:
  [lessons.md, "A reasoned default was the worst value on the curve (#80)"](../../agents/lessons.md).

## Design model

From the source and the 2026-08-10 rulings (status: **ruling-governed, no
record**).

**One implementation, two drivers.** `SceneRaster` does all *resolution* —
scale, mask, paint servers, filters, shape collection — eagerly in its factory
(so it throws where it always threw), allocates the `RasterImage`, and exposes
the *drawing* as `steps()`, which is `rasterizeMaskedShapesSteps`.
`rasterizeScene` and `rasterizeMaskedShapes` drain the same generator, so the
synchronous and banded paths cannot draw different pictures: "a `yield` moves
control, not a number". Byte-identity is therefore structural; rows are
independent by construction (theflow, 2026-08-10).

**A step is a band, never a pixel**: one image row (`_fillRectSteps`,
`_fillPolygonSteps`/`polygonCoverageSteps`, the mask pass at the end of
`rasterizeMaskedShapesSteps`), one row of a filter layer
(`_coverPolygonSteps`, `_drawThroughLayerSteps`), or one line of a box pass
(`_boxPassSteps` — one pass per axis, each line running all three boxes before
its yield).

**The yield must be a macrotask.** `rasterizeSceneAsync` yields with
`Future<void>.delayed(Duration.zero)`. `await null` is a microtask, the
microtask queue drains before the browser paints, and a version written that
way passes every byte test and fixes nothing — which is exactly how Flutter's
web `compute` moves no work (`_isolates_web.dart`: `await null; return
callback(message);` — read at 3.41.9 in #80, re-read at 3.47.1 for this note).

**The slice is a time, not a band count** — the same row costs whatever the
device costs. The obvious tuning (yield every *n* rows) was considered and
**not taken**: at `marble` @210 a row is already ~1.1 ms, so even n = 8
overshoots a 4 ms slice, and coarsening hurts exactly where responsiveness
matters.

**Composes with `compute`.** `ComputeCallback` is `FutureOr<R> Function(M)`
(`isolates.dart`, re-verified at 3.47.1), so the async rasteriser is a legal
callback. Native: isolate runs it, yields are free. Web: main thread runs it,
yields are the point. One code path, no platform branch in `lib/`.

**Shared slice.** `defaultRasterSlice` is also read by the widget's
`_rasterBytes` premultiply loop, which slices itself the same way, because an
O(area) premultiply left as one pass would hand back the stall just after the
drawing. "Two constants that must agree are one that eventually will not."

**Internal knob.** Neither `rasterizeSceneAsync`'s `slice` parameter nor
`defaultRasterSlice` is exported from the barrel; the parameter exists so tests
can drive the loop hard (1 µs slice) and the sweep stays re-measurable.

**What is not banded.** The `RasterImage` allocation and the filter layer
(roughly 86 bytes of `Float64` per output pixel) happen before the first
`yield`: one uninterruptible allocate-and-zero. Measured up to 480 physical
pixels with no visible stall (17 ms worst gap); beyond that, read from the code
only.

**Outside input:** the target size (`width`/`height`, from the widget's
`size × dpr`) bounds the work and memory linearly in area; nothing bounds the
size itself (a decision — see [widget-lifecycle](widget-lifecycle.md)).

### Measurements (dated, one machine; absolute numbers move up to 7x under load)

- **Browser, before vs after banding** — worst single gap seen by a
  `setInterval` outside Dart, Chrome (2026-08-10): 120 px 213 → **17 ms**;
  240 px 731 → **17 ms**; 480 px 2362 → **17 ms**. Flat in size; Chrome's Long
  Tasks API showed long tasks in every blocking phase and **none** in banded
  ones.
- **Slice sweep**, `marble` @480 physical, against 2629 ms uninterrupted
  (also in `rasterizeSceneAsync`'s doc-comment): 4 ms 10130 ms / 28 ms stall;
  **8 ms 5450 / 23**; 16 ms 5144 / 32; 33 ms 3407 / 47; 100 ms 2310 / 110.
  8 ms strictly dominates 16 ms — the only such pair — so it is the default, at
  a **2.1x** web tax. Every web yield is a `setTimeout(0)` clamped to ~4 ms, so
  a slice at the clamp mostly waits. 33 ms would cost 1.3x and stay under the
  browser's 50 ms long-task line — recorded for whoever re-takes it.
- **Native tax, before vs after the restructure, back to back**: `pixel` @80
  3.5 → 4.1 ms; `marble` @80 25.8 → 32.6; @120 72.5 → 79.7; @210 205.6 →
  237.2. **10–26%**, paid everywhere, accepted because on native it is inside
  an isolate and costs no frame.
- **Banded vs sync in one revision, eight alternating JIT/AOT runs**: overhead
  0.71–1.25x centred on **1.00** across all forty cells, including inside the
  run whose absolute numbers were inflated tenfold — ratios measured back to
  back survive contention because the conditions divide out (the noise
  re-measure, 2026-08-10; war story [lessons.md, "A minimum over N repetitions
  is not a defence against a busy machine"](../../agents/lessons.md)).

## Code

- `lib/src/raster/scene_raster.dart` — `rasterizeScene`, `defaultRasterSlice`,
  `rasterizeSceneAsync`, `SceneRaster` (factory, `image`, `shapes`, `steps`).
- `lib/src/raster/raster.dart` — `rasterizeMaskedShapes`,
  `rasterizeMaskedShapesSteps`, `_drawThroughLayerSteps`, `_boxPassSteps`,
  `_coverPolygonSteps`, `_fillRectSteps`, `_fillPolygonSteps`,
  `polygonCoverageSteps` (and its draining wrapper above it).
- `lib/src/widget/boring_avatar.dart` — `_rasterBytes` (calls
  `rasterizeSceneAsync`; premultiply loop sliced on `defaultRasterSlice`),
  `rasterAvatarImage` (the `compute` call).
- Tests: `test/raster_banding_test.dart` — "the banded raster draws the same
  bytes" (every variant × sizes, deliberately weak: same generator), "it yields
  to the event loop, with a macrotask" (the discriminator: a `Timer.run`
  queued after the call must fire before the future completes; `await null`
  would fail it), "a generous slice still finishes…", "the step count grows
  with the work" (guards collapse to one step). The real proof the picture did
  not move is every golden in the suite, which runs through `rasterizeScene`
  and therefore through the steps.

## Reference behaviour

- Flutter SDK `foundation/_isolates_web.dart` (`compute` = `await null;
  return callback(message)`) and `_isolates_io.dart` (`Isolate.run`) — read
  at 3.41.9 (#80), re-read at 3.47.1; `foundation/isolates.dart`
  `ComputeCallback`.
- Browser behaviour (macrotask vs microtask, `setTimeout(0)` ~4 ms clamp, the
  50 ms long-task threshold) — measured in Chrome 151, 2026-08-10, not cited
  from a spec.

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md) — the
  restructure was admissible only because a yield moves control, not a number;
  any change to step order or to what runs between yields must keep every
  golden byte-identical.

## Blast radius

- [widget-lifecycle](widget-lifecycle.md) — the widget's "late, not stalled"
  promise and the no-ceiling `size` argument rest on the raster yielding; a
  driver that stops yielding (or yields a microtask) freezes the tab on web
  with every test but one green.
- [coverage](coverage.md) — the integrators are the generators; a new loop
  added without a `yield` per row reintroduces an uninterruptible stretch
  proportional to its size.
- [filters](filters.md) — the blur's layer is allocated before the first yield
  and held across all of them; peak memory and the one unbanded allocation
  live there.
- [compositing-and-masks](compositing-and-masks.md) — the mask pass is the last
  band loop; reordering it relative to shape drawing changes bytes.
- [goldens](goldens.md) — the only real proof that banding moved nothing; a
  golden path that bypassed `steps()` would stop proving it.

## Known holes / open

- **Allocation is not banded.** Past 480 physical pixels the up-front
  allocate-and-zero is unmeasured as a stall.
- **The two "tax" findings read differently on their surfaces.** The native
  before/after table gives 10–26% and the widget's `size` doc-comment says
  "2.1x there, 10–26% on native"; `docs/performance.md` says slicing "is not a
  tax … the interruptible drawing takes the same total time" (the 0.71–1.25x
  same-revision ratio). Both are theflow measurements of different
  comparisons (across revisions vs within one); the user-facing doc states
  only the second and omits the 2.1x web tax. Not reconciled.
- **WasmGC is 2.2–2.6x slower than dart2js** for this code and the cause was
  never investigated; "build for wasm" cannot be offered without re-measuring.
- Web stays ~4x slower than native at the same size, and the worst measured
  stall at the shipped slice (23 ms) drops at least one 60 Hz frame however
  small the avatar.
