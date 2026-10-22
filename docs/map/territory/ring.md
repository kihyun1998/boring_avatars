# ring

## What it is

The `ring` variant draws a target of nine concentric bands on a **90-unit**
canvas: two half-planes, three pairs of half-discs (radii 38, 32, 26) and a
centre circle of radius 23. Five palette draws are remapped onto nine slots.
`ring` was the variant that brought arc flattening and polygon fill into the
rasterizer (2026-07-28), and it is the variant whose arcs keep the hardest
branches of the arc code unreachable from real input.

## Governing decisions

**None.** No ADR or ledger ruling is about `ring`. The adjacent sacred-surface
rule in `CLAUDE.md` makes the file frozen, but it decides nothing specific to
`ring`.

## Design model

From the source and its doc-comments, plus dated measurements.

- **Nine slots are painted from five draws.** `generateColors` takes five
  consecutive colours (`getRandomColor(hash + i, …)` for `i` in 0–4, walking
  the palette by one each time rather than re-hashing). A fixed remap,
  `_slotSource = [0, 1, 1, 2, 2, 3, 3, 0, 4]`, assigns them to the nine slots, so
  four pairs of bands always share a colour. The remap *is* the specification.
  There is no rule behind it to re-derive. Pinned by "upstream's own output shows
  slots 1=2, 3=4, 5=6 and 0=7".
- **The `d` strings are literals upstream**, hardcoding 90 and 45 rather than
  deriving them from `SIZE`, so they are literals here too (`_paths`). Each one
  is a closed half-disc: an arc between the two ends of a horizontal diameter,
  then the chord back. They are painted largest first.
- **The drawing space is 90**, re-read from the pinned tree:
  `avatar-ring.js:4` @ v1.6.1, `const SIZE = 90`. `size` reaches only
  `width`/`height`. Before #58 (2026-08-09) the rasterizer refused any target
  other than 90×90. It scales now, so the goldens are 90×90 because that is
  `ring`'s 1:1 size, not because 90 is the only size it can draw at (hidden-state
  #26; pinned by "the 90-unit viewBox now draws at 80, which is why #58
  existed").
- **Attribute order is the call site's** (hidden-state #18). `ring`'s `<circle>`
  is `cx cy r fill`, and `bauhaus`'s is `cx cy fill r transform`. `ring`'s
  `<path>` is `d fill`, and `sunset`'s is `fill d`.
- **Empty palette:** `range == 0` makes every draw `hash % 0`, which is `NaN`
  upstream and `null` here. All nine slots come back unfilled, and nothing
  downstream dereferences them, so `ring` degrades rather than throwing
  (hidden-state #8). Pinned by "an empty palette leaves every slot unfilled, and
  does not throw" and the raster test "every pixel is transparent".

Hidden-state rows, variant half only (mechanisms in
[path-geometry](path-geometry.md) and [compositing-and-masks](compositing-and-masks.md)):

| Row | What `ring` writes | Live / inert here | How it was established |
|---|---|---|---|
| #10 F.6.6 radius correction | six arcs whose chord equals the diameter | inert: every arc has λ exactly 1, so the correction was dead code for two tickets until `beam` fired it | #36 |
| #23 rounding per shape | nine stacked shapes | live: `blend()` rounds once per shape, as a browser's 8-bit surface does | #37 |
| #24 abutting shapes | half-planes meeting along `y = 45` in four places | inert at 90×90 (a pixel boundary); **live at other scales**: 101 → 36 interior pixels, worst gap 63/255 (#58, 2026-08-09). Ruled correct in #83; the residue left at `ring` 101 (8 px) is on the mask curve (#27) | `raster_scale_test.dart` |
| #25 packed arc flags | `a32 32 0 10-64 0`: `10` is *two* flags, then `-64` | live in all six arcs: every flag pair is packed (`00-76`, `01-76`, `10-64`, `11-64`, `00-52`, `01-52`). theflow.md's row said "four of the six"; the `_paths` literals show six | `raster_path_test.dart`; `_paths`, re-read |
| #28 F.6.5 negative radicand | horizontal chords only | inert: the radicand is exactly zero every time, so a mutation removing the clamp survived until a case was constructed. Holds **as long as arcs stay axis-aligned** | #36 |
| #33 mask per group | at most one shape reaches any mask-edge pixel | inert | #37 |
| #36 `largeArc` dead-valued | chord = diameter on every arc | F.6.5's centre offset is exactly zero, so the sign rule multiplies zero. The case is constructed in `raster_path_test.dart` | #36 |
| #45 transform | none | inert | 600 renders |

## Code

- `lib/src/variants/ring.dart`: `ringColors`, `buildRingScene`, `_paths`,
  `_slotSource`, `_size` (90), `_draws` (5)
- `lib/src/avatar.dart`: `buildAvatarScene` dispatches `ring` with no
  per-drawing knob
- `test/ring_parity_test.dart`: the byte sweep, the slot remap, the consecutive
  draws, square, "the drawing space is 90 wide, whatever the display size"
- `test/ring_raster_test.dart`: band placement and concentricity, no seam at
  `y = 45`, empty palette, square, "a circle is read from its own attributes",
  container checks (group transform, opacity, mask units/region/reference),
  goldens
- `test/support/golden_cases.dart`: `ring-clara-default`, `ring-alice-pair`,
  `ring-clara-square`, all at 90

## Reference behaviour

- Pinned upstream: `../.refs/boring-avatars` @ v1.6.1
  `src/lib/components/avatar-ring.js`, and `.tsx` @ v2.0.x.
- Fixtures: [`test/fixtures/v1_6_1/svg.json`](../../../test/fixtures/v1_6_1/svg.json).
- [calibration](calibration.md): `ring` at 101 is one of the #24/#83 cases.

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md): `ring.dart` is sacred surface
- [variant-design-size](../invariant/variant-design-size.md): **90**
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md): `<circle cx cy r>`, arc path data
- [root-fill-none](../invariant/root-fill-none.md): the empty palette's nine bare slots
- [libm-transcendentals](../invariant/libm-transcendentals.md): six arcs (`atan2`/`acos` in `_appendArc`) and the circle (`cos`/`sin` in `flattenCircle`)

## Blast radius

- [path-geometry](path-geometry.md): arc flattening and the packed-flag tokeniser
  were built for these six `d` strings. Their chords being horizontal is what
  keeps #28 and #36 inert, and a non-axis-aligned arc makes both live.
- [compositing-and-masks](compositing-and-masks.md): nine stacked shapes round
  nine times. The `y = 45` abutment is a #24 case at non-integer scales.
- [goldens](goldens.md): three images at 90×90. A golden tool with one global size
  silently produces the wrong reference.
- [scene-reading](scene-reading.md): the container allow-lists (root `<svg>`,
  `<g>`, `<mask>`) were first exercised by `ring`'s tests.
- [readme-gallery](readme-gallery.md): the gallery draws through this builder.

## Known holes / open

- **Hidden-state #27's mask-curve residue at `ring` 101 (8 px) is unruled.**
  It is mirror-symmetric about the centre, at the circle's extremes. See
  [calibration](calibration.md).
