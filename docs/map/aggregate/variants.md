# Aggregate — the six variants

**This note owns no detail.** These are six sibling scene builders behind one
dispatch. Each turns `(name, colors, size, square, title)` into a scene on its
own canvas, and none of them knows about the others.

| Concept | Note |
|---|---|
| Two blurred, blended blobs on a background; the default variant; carries ruling S-3 | [marble](../territory/marble.md) |
| A face on a rotated, scaled card, on a 36-unit canvas; throws on an empty palette (S-2) | [beam](../territory/beam.md) |
| An 8×8 tile mosaic; the only drawing that differs between selectors (`PixelColourIndex`) | [pixel](../territory/pixel.md) |
| Two gradients painted from `<defs>`; the name inside an id; carries ruling S-1 | [sunset](../territory/sunset.md) |
| Nine concentric bands from five draws, on a 90-unit canvas | [ring](../territory/ring.md) |
| A rotated bar, a disc, and a stroked rule | [bauhaus](../territory/bauhaus.md) |

## Why they sit together

`avatar.dart`'s `buildAvatarScene` picks exactly one of them per call, and
passes each the same arguments plus one per-drawing knob, which only `pixel`
takes ([variant-dispatch](../territory/variant-dispatch.md)). They share
upstream's utilities ([upstream-utilities](../territory/upstream-utilities.md))
and one scene vocabulary. They share no code with each other. What they do share
is a set of input conditions where the answers differ per variant, and you only
see that by looking at all six at once. The sharpest of these is the empty
palette.

## What each variant does with `colors: []`

Hidden-state #8, measured at v1.6.1 over all six variants × 20 names. Upstream
computes `% 0` → `NaN` → `colors[NaN]` → `undefined`. **What happens next splits
by variant, and by attribute.** "An empty palette degrades" is true per variant,
not as a general rule. A naive Dart port throws on `% 0` everywhere: it crashes
where JS degrades, *and* it succeeds silently where JS crashes.

| Variant | What upstream emits | What a browser draws | The port | Why it is safe (or not) | Pinned by |
|---|---|---|---|---|---|
| `marble` | three `fill`s dropped | nothing | same | an absent `fill` inherits the root's `fill="none"` | `marble_parity_test.dart` "an empty palette degrades"; `marble_raster_test.dart` "every pixel is fully transparent" |
| `beam` | **no document**: `getContrast(undefined).slice` → `TypeError` | — | `ArgumentError.value(colors, 'colors', …)` (**S-2**) | the face colour has no degraded value | `beam_parity_test.dart` "an empty palette fails, and only for beam" |
| `pixel` | 64 `fill`s dropped | nothing | same, in both colour-index eras | root `fill="none"` | `pixel_parity_test.dart` (both eras) |
| `sunset` | `<stop></stop>`: `stop-color` dropped, `fill="url(#…)"` kept | **a solid black disc** | same | `stop-color` is not inherited, and its initial value is **black** (hidden-state #39); ADR-0001 R2 | `sunset_parity_test.dart`, `sunset_raster_test.dart`, `sunset-empty-palette` golden |
| `ring` | nine `fill`s dropped | nothing | same | root `fill="none"` | `ring_parity_test.dart`, `ring_raster_test.dart` "an empty palette draws nothing at all" |
| `bauhaus` | three `fill`s **and the line's `stroke`** dropped | nothing | same | the fills through root `fill="none"`; the stroke on its own, because `stroke`'s initial value is `none` (#39) | `bauhaus_parity_test.dart` "an empty palette drops stroke"; `bauhaus_raster_test.dart` |

What the table rests on:

- **The fill rows hold only because of the root `fill="none"`.** That
  declaration is present in every rendered document: 580 of the v1.6.1 fixture's
  600 entries, the other 20 being `beam`'s throws (re-verified). `fill`'s initial
  value is **black**. A variant whose root dropped that declaration would paint
  every unfilled shape black, and nothing in the rasterizer reads the root to
  notice. See [root-fill-none](../invariant/root-fill-none.md) and
  [colour-declarations](../territory/colour-declarations.md).
- **Three variants are deliberately missing an empty-palette golden**:
  `marble`, `bauhaus` and `beam`. The first two would freeze a fully transparent
  image, which is the failure #40 found in `sunset`. `beam` has no image to
  freeze. Each asserts its answer as behaviour instead
  ([goldens](../territory/goldens.md)). `sunset`'s black disc is a picture, so it
  is frozen. `pixel` and `ring` have no empty-palette golden either, and assert
  their blank in tests.
- **The crosscheck sees this as 40 "both sides produce no document" cases per
  selector run.** Those are `beam`'s; the other five render
  ([crosscheck](../territory/crosscheck.md)).
- **It holds for all three selectors.** The `v1_7_0` and `v1_10_1` fixtures
  record the same 20 `beam` throws and no others (re-verified). `pixel`'s
  1.10.1 era loses tile 0's `NaN` route but keeps the empty-palette route,
  which gives the same 64 bare tiles.
