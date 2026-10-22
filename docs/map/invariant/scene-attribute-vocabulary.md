# Scene attribute vocabulary

## The fact
Every element and attribute a variant builder writes into the scene must be one
that `lib/src/raster/scene_raster.dart` both allow-lists **and** implements.
That includes the mask's literal `fill="#FFFFFF"`. The allow-lists are
`_drawableAttributes`, `_containerAttributes`, `_defsAttributes`,
`_maskAttributes` and `_maskShapeAttributes`, checked by `_checkAttributes`.
Anything outside them throws `UnsupportedSceneError`.

## Why it is cross-cutting
The scene seam keeps **one** copy of the geometry so that the SVG emitter and
the rasterizer cannot derive it independently (`CLAUDE.md`, "Three layers,
declared seams"). The cost of that seam is a vocabulary shared by two sides
that never call each other:

- the writers are the six `build<Name>Scene` functions;
- the readers are `SceneRaster` / `_collectShapes`, `_readMask`,
  `_readPaintServers`, `_readFilters` and their allow-lists.

The emitter is not a party to this. It serialises whatever it is given, which
is why the SVG half of a vocabulary mismatch is always fine and the raster half
is where it shows.

Changing one side without the other is a bug in either direction:

- **A writer adds an attribute that the readers do not know.** The widget
  throws for that variant while `boringAvatarSvg` keeps working. That is loud,
  and it is the intended failure.
- **A reader allow-lists an attribute without implementing it.** The result is
  a silent wrong picture. #30 found exactly this: `<g transform>` had to be
  implemented and allow-listed **in the same edit**, because an allow-list
  entry for a transform nobody applied is the failure the list exists to
  prevent.

## Territories it holds in
- [scene-reading](../territory/scene-reading.md) — the allow-lists, `_checkAttributes`, `_readMask`'s `fill != '#FFFFFF'` guard
- [marble](../territory/marble.md), [beam](../territory/beam.md), [pixel](../territory/pixel.md), [sunset](../territory/sunset.md), [ring](../territory/ring.md), [bauhaus](../territory/bauhaus.md) — the attributes each builder writes
- [scene-model](../territory/scene-model.md) — `SvgElement`, the closed set of element kinds both sides name
- [compositing-and-masks](../territory/compositing-and-masks.md) — `mask-type` is alpha for `pixel` only, and luminance (undeclared) for the other five; they agree only because the fill is white (hidden-state #22)
- [colour-declarations](../territory/colour-declarations.md) — the mask's `#FFFFFF` is a byte comparison, deliberately outside the colour vocabulary
- [goldens](../territory/goldens.md), [calibration](../territory/calibration.md) — they catch a variant writing an attribute the rasterizer drops, but only for the inputs in their rosters
- [filters](../territory/filters.md) — the filter chain is validated whole, and a flood that paints or a blend not reading `SourceGraphic` throws

## What a violation looks like
Two cases. The first is a variant that renders in `boringAvatarSvg` and throws
`UnsupportedSceneError` in `BoringAvatar`. The second, worse one is a variant
that renders in both with nothing thrown and draws a different picture in the
widget. #38 measured the second before fixing it: `transform="scale(2)"` on the
mask's shape gave the untransformed coverage, and `opacity="0.5"` gave full
coverage, because `_readMask` read five geometry attributes and ignored the
rest.

## Discovery history
- #37's completeness pass found that containers were walked unchecked. Every
  element on the walk now carries an allow-list (hidden-state #30).
- #38 found the second half: `<mask>` was allow-listed but its child `<rect>`
  was not, because `_readMask` is a different reader of the same tree. The
  general lesson is that **an allow-list covers the walk it is on, and a second
  reader of the same tree needs its own** (hidden-state #30, theflow.md
  @ 0593e28).
- #38 also recorded that the Step 1 enumeration listed five missing
  capabilities and missed the `<g transform>`. The guard is what found it
  (`docs/agents/lessons.md`, "A guard can catch the capability the
  enumeration missed").

## Where it will recur
If a function reads attributes off a scene node, it needs an allow-list for the
node kinds it reads, separate from any other reader's. If a variant builder
gains an attribute, or a new upstream state changes what a builder writes, the
rasterizer must learn it or refuse it in the same change. The cheapest check:
render every variant through `rasterizeScene` at its design size, which the
golden suite already does.
