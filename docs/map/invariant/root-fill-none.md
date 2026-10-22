# Root fill is none

## The fact
Every variant's root element is `<svg … fill="none">` (`buildBauhausScene`,
`buildBeamScene`, `buildMarbleScene`, `buildPixelScene`, `buildRingScene`,
`buildSunsetScene`, each writing `SvgAttribute('fill', 'none')`). The
rasterizer **never reads the root's `fill`**. It answers an absent or unreadable
`fill` on a shape as "paint nothing" directly (`resolvePaint` in
`_shapesOf`, `scene_raster.dart`: `AbsentColour() => null`,
`UnreadableColour() => null`). A browser reaches the same answer by a different
route: it inherits the root's `none`. The two backends agree **only while every
root declares `none`**.

## Why it is cross-cutting
SVG's initial `fill` is **black**, not nothing. What makes a missing `fill` safe
in a browser is inheritance from the root. The rasterizer hard-codes the
inherited answer instead of computing it. Two independent sites carry one
assumption:

- six builders that each write the root attribute themselves (no shared helper);
- one reader that assumes what the writers wrote, without looking.

If a variant's root dropped `fill="none"`, or declared a colour, the browser
would paint every unfilled shape that colour (black by default), while the
widget would keep painting nothing. That is the two-backend divergence the
scene seam exists to prevent, and nothing in the rasterizer would notice.

`stroke` is safe for a different reason. Its initial value is already `none`,
so a missing one paints nothing on its own. `stop-color` is the opposite case:
its initial value is black and it is not inherited, so a missing one *is*
black.

## Territories it holds in
- [colour-declarations](../territory/colour-declarations.md) — the four-state answer per property; this is [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md)'s discrepancy ②
- [scene-model](../territory/scene-model.md) — the root node each builder constructs
- [scene-reading](../territory/scene-reading.md) — `resolvePaint`, and `_containerAttributes` allowing `fill` on the root without reading it
- [bauhaus](../territory/bauhaus.md), [beam](../territory/beam.md), [marble](../territory/marble.md), [pixel](../territory/pixel.md), [ring](../territory/ring.md), [sunset](../territory/sunset.md) — the root attribute; [aggregate/variants](../aggregate/variants.md) — the empty-palette table, where five variants rely on this

## What a violation looks like
An empty palette (`colors: []`) or `pixel`'s tile 0 before 1.10.1 produces a
shape with no `fill` (hidden-state #8 and #17). Under a root that is not
`none`, Chrome draws that shape black and the widget draws it transparent, and
the two disagree on exactly those pixels. Today it reproduces only by editing a
builder's root.

## Discovery history
- Hidden-state #8 (#38, #39) records why the two absences are safe for different
  reasons. theflow.md said the root `fill="none"` is present in all 600
  renders of the corpus. Re-read against the `v1_6_1` fixture, it is 580 of
  600: the other 20 are `beam`'s empty-palette throws, which produce no
  document at all.
- ADR-0001 names the mechanism difference as discrepancy ②. The answer is the
  same and the mechanism is not, and they part ways the day a root declares a
  colour. `scene_raster.dart`'s own doc-comment on `resolvePaint` says so.
- This note is the one place that says it holds at six sites, not one.

## Where it will recur
If a rasterizer branch answers a property as "inherited" without reading the
ancestor, it is subject to this. A new variant, or a new upstream state whose
root carries a different `fill`, `stroke` or `color`, makes it live. `color` is
behind `currentColor`, which is answered **black** because no document declares
one (hidden-state #20).
