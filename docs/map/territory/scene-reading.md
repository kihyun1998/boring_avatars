# scene-reading

## What it is
The bridge from scene to pixels. `scene_raster.dart` walks the backend-neutral
scene tree **by attribute name**, checks every element it meets against an
allow-list, resolves the device scale, the one `<mask>`, the paint servers and
the filters, threads an inherited matrix down through `<g transform>`, and turns
each drawn element into `RasterShape`s for the integrators. Its refusal policy
is the territory's identity: anything the rasterizer cannot fully honour throws
`UnsupportedSceneError`, because the alternative is a plausible wrong picture
that a golden would freeze.

## Governing decisions
- [ADR-0001 — what a colour declaration means](../../adr/0001-what-a-colour-declaration-means.md)
  governs the answers `_shapesOf`'s `resolvePaint` and `_readLinearGradient`
  give for absent / `none` / unreadable declarations (nothing for `fill` and
  `stroke`, black for `stop-color`). The vocabulary itself is
  [colour-declarations](colour-declarations.md)'s.
- Adjacent, not governing: [ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md)
  decides where the widget places the buffer on the device grid; it does not
  decide how the scene is read into it.

The rest of the design model below comes from reading the source and from
dated measurements recorded in theflow.md; no record governs it.

## Design model
**Everything unimplemented throws.** Each element on the walk carries an
allow-list, and an attribute off it throws rather than being skipped
(`_checkAttributes`, `_collectShapes`). `fill-rule` is on no list on purpose:
it is a capability, and no in-scope version overrides nonzero. An allow-list
entry is added only in the change that *applies* the attribute — an entry for
an effect nobody honours is the silent wrong picture the list exists to stop
(hidden-state #30, found by the #37 completeness pass; `<g transform>` was
allow-listed and composed in one edit in #38).

**Containers are checked too (hidden-state #30).** `beam` wraps its face in
`<g transform="translate(4.5 4.5) rotate(-9 18 18)">`; an unchecked container
rendered it 4.5 units off and unrotated with nothing thrown. `#37`'s guard is
what found that — the #38 Step 1 enumeration had listed five missing
capabilities and not this one.

**A second reader of the same tree needs its own allow-list.** `<mask>` was
allow-listed in #37 but its child `<rect>` was not, because `_readMask` is a
different function from `_collectShapes`. Measured in #38 before the fix:
`transform="scale(2)"` on the mask's shape gave the untransformed coverage
where a browser doubles it, and `opacity="0.5"` gave full coverage where a
browser halves it. `_maskShapeAttributes` now closes it; `ry` is deliberately
absent from it (see [compositing-and-masks](compositing-and-masks.md)).

**The five allow-lists** (`scene_raster.dart`):
- `_drawableAttributes` — `<rect>`, `<path>`, `<circle>`, `<line>`. `stroke` is
  on `<rect>` only because `beam`'s eyes declare `stroke="none"`; a rect stroke
  that would paint (a read colour or a `url(…)`) throws in `_shapesOf`, and an
  unreadable one passes because it cannot paint (ADR-0001, #64). `filter` and
  `style` are on `<path>` only, so no rect can need a layer.
- `_containerAttributes` — `<svg>`, `<g>` (`mask`, `transform`), `<title>`.
- `_defsAttributes` — `<defs>`, `<linearGradient>`, `<stop>`, `<filter>`,
  `<feFlood>`, `<feBlend>`, `<feGaussianBlur>`.
- `_maskAttributes` — the `<mask>` element itself.
- `_maskShapeAttributes` — the mask's one `<rect>`.

**`<mask>` and `<defs>` are read elsewhere and skipped on the drawing walk —
but validated, not ignored (hidden-state #40).** `<defs>` sits outside
`<g mask>`, after it, and holds the paint the shapes reference; skipping it as
"not drawn, so not interesting" made every `sunset` render blank. Fixed in #40
by `_readPaintServers` running before `_collectShapes` and checking `<defs>`'
contents as strictly as a drawn element's. `<filter>` lives in `<defs>` too and
is skipped by `_readPaintServers` and validated by `_readFilters`
([filters](filters.md)).

**The device scale is derived, never passed (`_resolveScale`, #58).** The
scale is `width / viewWidth`, and it must equal `height / viewHeight`; a
non-uniform target throws, because `blurSigma` reads the matrix's column norms
and a Gaussian is isotropic only under a similarity. A non-positive target, an
unreadable viewBox, a non-zero viewBox origin and a viewBox with no extent all
throw. Before #58 the seam (then `_checkViewBox`) refused any target that was
not exactly 1:1. The walk starts at `Affine.scaling(s, s)`, and the flattening
tolerance passed down is `defaultFlatness / s`, so device error is held at the
constant the tolerance was chosen for and `s == 1` changes nothing
([path-geometry](path-geometry.md)). The variant's own `scale(…)` is
deliberately not divided out.

**Every length that does not ride the matrix must be scaled at construction.**
The mask is scaled at the end of `_readMask`; the gradient axis in
`_readLinearGradient`. The gradient one was missed when #58 first landed:
`LinearGradientPaint.colourAt` projects the *device* pixel centre, so a
user-unit axis put the whole ramp in the top-left `1/scale` of the image —
measured `sunset` at 2x, box-filtered back to 1:1, **108/255** off across whole
interior rows. The filter region is the opposite case: it is resolved in
viewBox units and carried by the matrix, so handing it the device size would
scale it twice.

**One mask, referenced by id (hidden-states #32, #35).** `_firstOfKind` takes
the first `<mask>`; a scene without one throws. A `<g mask="…">` must name
exactly `url(#<that id>)` — a dangling or foreign reference throws (SVG 1.1
renders nothing for a broken reference, SVG 2 renders unmasked; either way
treating it as *our* mask is a picture no browser draws). A drawable element
outside a masked group throws instead of being dropped — this **inverted an
assertion #36 had pinned the other way**; both readings agreed on every real
scene and only one agreed with SVG. Both inert across all six variants.

**Paint resolution (`_shapesOf` — `resolvePaint`).** A `url(#…)` must name a
declared paint server, or it throws. Chrome actually paints a dangling
reference as **nothing** (`0,0,0,0`, measured — hidden-state #43), so the
throw's justification is not "a browser renders it black" (the reason #40
first wrote, in `scene_raster.dart` and two tests) but "a blank is
indistinguishable from the paint never having been read", which is the bug
#40 fixed. Absent, `none` and unreadable paint nothing; a read colour paints.
That absent `fill` paints nothing relies on the root `<svg fill="none">` —
nothing here reads the root ([root-fill-none](../invariant/root-fill-none.md)).
Hidden-state #31's history (every `sunset` render blank before #40; `none`
accidentally right until #69) is [colour-declarations](colour-declarations.md)'s.

**One element can paint twice.** `_shapesOf` returns fill then stroke, in §11's
order; `beam`'s mouth is a `<path>` with either. A `<path>` with a fill, a
stroke *and* a filter throws, because SVG blurs the composited element and the
two polygons would be blurred separately.

**Defaults from §11.4.** `<path>` `stroke-width` defaults to 1 (`beam`'s open
mouth relies on it); `<line>` keeps *requiring* it, because `bauhaus` always
writes it and a default there would be arithmetic no test could reach.
`stroke-linecap` reads `butt` / `round` and throws on anything else.

**Input bound.** The scene is built only by this package's own variant
builders; no public entry point hands a caller's tree to this walk. Its size is
therefore bounded by the variants (a few dozen nodes), and the raster target by
the caller's `width × height` — nothing here bounds that product
([banded-rasterisation](banded-rasterisation.md) owns the cost side).

## Code
- `lib/src/raster/scene_raster.dart — rasterizeScene`
- `lib/src/raster/scene_raster.dart — SceneRaster` (factory: scale → mask → paints → filters → shapes; `shapes` getter for the fast-path assertion; `steps`)
- `lib/src/raster/scene_raster.dart — _resolveScale`
- `lib/src/raster/scene_raster.dart — _readMask`
- `lib/src/raster/scene_raster.dart — _collectShapes`
- `lib/src/raster/scene_raster.dart — _readPaintServers`, `_readLinearGradient`
- `lib/src/raster/scene_raster.dart — _readFilters`, `_Filter` (detail in [filters](filters.md))
- `lib/src/raster/scene_raster.dart — _shapesOf` (`resolvePaint`, `required`, `strokeWidth`, `blurSigma`, `filterRegionQuad`, `blendMode`, `strokeCap`)
- `lib/src/raster/scene_raster.dart — _drawableAttributes`, `_containerAttributes`, `_defsAttributes`, `_maskAttributes`, `_maskShapeAttributes`, `_checkAttributes`, `_firstOfKind`, `_num`
- `lib/src/raster/raster.dart — UnsupportedSceneError`
- Tests: `test/ring_raster_test.dart` group "the seam checks containers too, not only the shapes"; `test/beam_raster_test.dart` group "beam refuses what it still cannot draw" ("an attribute on the mask's own rect is refused, not read past", the rect-stroke cases); `test/pixel_raster_test.dart` group "the seam fails loudly instead of drawing something plausible" and "a shape outside the masked group is refused, not dropped"; `test/sunset_raster_test.dart` group "the scene seam still refuses what it cannot draw"; `test/raster_scale_test.dart` groups "what a scale cannot be" and "the lengths that no matrix carries".

## Reference behaviour
- Dangling paint reference: Chrome paints `0,0,0,0` with or without a root
  `fill` (measured, hidden-state #43) — the guard throws anyway, by the reason
  above.
- Gradient axis at 2x: 108/255 off before it was scaled (measured on #58's
  first landing, recorded in `_readLinearGradient`'s doc).
- `mask="url(#…)"` broken reference: SVG 1.1 renders nothing, SVG 2 renders
  unmasked (spec reading, hidden-state #35).

## Cross-cutting invariants
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md) — the allow-lists here are one side of it; the variant builders are the other.
- [root-fill-none](../invariant/root-fill-none.md) — `resolvePaint`'s "absent paints nothing" holds only because every root declares `fill="none"`.
- [variant-design-size](../invariant/variant-design-size.md) — `_resolveScale` is where the viewBox side becomes the device scale.
- [frozen-selector-output](../invariant/frozen-selector-output.md) — a change to what the walk accepts or composes moves shipped bytes.
- [construction-time-length-scaling](../invariant/construction-time-length-scaling.md) — `_readMask` and `_readLinearGradient` scale at construction; the flatness is divided.

## Blast radius
- [scene-model](scene-model.md) — the walk reads elements and attributes by the names the scene model defines; a renamed or added attribute is a throw here.
- [svg-emission](svg-emission.md) — the transform and paint strings are emitted verbatim there and parsed here; the two must keep reading the same string.
- The six variant notes ([pixel](pixel.md), [ring](ring.md), [sunset](sunset.md), [bauhaus](bauhaus.md), [beam](beam.md), [marble](marble.md)) — anything a builder writes that is off an allow-list throws for every caller.
- [transforms](transforms.md) — the inherited matrix composes `parent · own`; reversing it moves every nested shape.
- [path-geometry](path-geometry.md) — the flatness passed down is pre-divided by the device scale; changing that moves every curve at `s != 1`.
- [coverage](coverage.md) — whether a rect stays a `RasterRect` is decided here, by `isTranslationOnly`; that choice is the fast path's cost.
- [compositing-and-masks](compositing-and-masks.md) — `_readMask` is the only producer of `RoundedRectMask` and decides which masks are representable.
- [filters](filters.md) — sigma and region are resolved here in the element's own space.
- [colour-declarations](colour-declarations.md) — the four-state answer per property is applied here.
- [goldens](goldens.md) — every golden is drawn through this walk.

## Known holes / open
- **An alpha mask's fill is not checked.** `_readMask` checks `fill == '#FFFFFF'`
  only when `mask-type` is absent (luminance). Under `mask-type="alpha"` —
  `pixel`'s — any fill passes, and `RoundedRectMask` treats the shape as
  opaque. A translucent, `none` or absent fill (which would inherit the root's
  `none`) would give a browser a weaker or empty mask. Inert: `pixel` writes
  `#FFFFFF`. Read from code, not measured.
- **Only the first `<mask>` is read.** A second, unreferenced `<mask>` is
  skipped on the walk and never validated; harmless while unreferenced, since a
  reference to it throws.
- The library doc-comment at the top of `scene_raster.dart` still says it
  handles "`pixel`, `ring`, `sunset`, `bauhaus` and `beam`" and that "Filters …
  arrive with the variants that use them" — stale since #41 implemented them.
- `_shapesOf`'s circle-arm comment says "`beam`'s wrapper is the only scaled
  shape in the six and its largest is 1.2". `marble`'s blobs carry
  `scale(1.2…1.5)`; the headroom argument still holds at 1.5
  (1.5/4096 ≈ 0.00037 against 0.0039), but the sentence is wrong.
- Four doc references in `scene_raster.dart` (`rasterizeScene`, `SceneRaster`,
  `_resolveScale`) name `[_ShapeAttributes.blurSigma]` /
  `[_ShapeAttributes.filterRegionQuad]`; no `_ShapeAttributes` exists — both
  are local functions inside `_shapesOf`.
- Nothing bounds the caller's raster target size here.
