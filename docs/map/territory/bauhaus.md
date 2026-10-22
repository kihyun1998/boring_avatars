# bauhaus

## What it is

The `bauhaus` variant draws four shapes on an 80-unit canvas: a full-canvas
background rect, a rotated bar (`<rect>`), a translated disc (`<circle>`) and a
rotated rule (`<line>`). It was the variant that brought rotation, the transform
list, and the first stroked element into the rasterizer (#39, 2026-07-29), and it
is the first variant whose colour arrives through `stroke`.

## Governing decisions

**None.** No ADR or ledger ruling is about `bauhaus`.

Adjacent: [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md) decides
what an absent `stroke` paints (nothing, because the initial value is `none`).
`bauhaus` is the variant that writes one on an empty palette. The ADR's
`bauhaus-invalid` / `bauhaus-colour4` calibration cases are its evidence, not its
subject.

## Design model

From the source and its doc-comments, plus dated measurements.

- **Four elements are generated and three are drawn.** `properties[0]`
  contributes a colour (the background) only. Its translation and rotation are
  computed and never read. They are computed here anyway, because upstream's
  loop is a single expression, and special-casing `i == 0` would invent a
  structure the reference does not have.
- **`isSquare` does not use the loop index.** `getBoolean(numFromName, 2)` sits
  inside the `Array.from` callback beside four fields that all use `i`. So all
  four elements carry the *same* flag, and only `properties[1]` reads it (bar
  height `SIZE` or `SIZE / 8`; re-read at `avatar-bauhaus.js:16,44` @ v1.6.1 and
  `.tsx:17,47` @ v2.0.2). A port that threaded `i` through it **survives the whole
  100-render byte sweep** (measured: 22 tests green). The reason: `getDigit(n, 2)`
  is the hundreds digit, so `hash + 1` moves element 1's flag only when
  `hash ≡ 99 (mod 100)`. That is about one name in a hundred, and none of the
  corpus's twenty. The blindness belongs to the **corpus**, not the port.
  `bauhaus_parity_test.dart` asserts on layer 1 directly and carries three
  constructed names ("and this pins the flag's shape, where the fixture pins its
  value"). War story: [`lessons.md` — "A tripwire's power can come from corpus membership rather than construction (#39)"](../../agents/lessons.md#a-tripwires-power-can-come-from-corpus-membership-rather-than-construction-39).
- **The translation range shrinks with the index.** `SIZE / 2 - (i + 17)` gives
  23, 22, 21 and 20. A port that hoisted the constant out of the loop would move
  three of the four elements.
- **The bar overhangs.** It is 80 wide at `x = 10`, so it extends 10 past the
  drawing space before any transform applies. The mask is what cuts it.
- **The disc is translated only**, with `cx cy fill r transform` in this call
  site's order (hidden-state #18; `ring`'s circle is `cx cy r fill`).
- **The rule is painted by `stroke`, never by `fill`.** `<line>` has no `fill` at
  any point, and the rasterizer refuses a `<line fill>`. `stroke-width="2"` is
  explicit, and an absent one is refused rather than defaulted.
- **Empty palette:** three `fill`s are dropped, **and the line's `stroke`**
  (hidden-state #8, the #39 addition). The two absences are safe for different
  reasons: `stroke`'s initial value is `none`, while an absent `fill` relies on
  the root `fill="none"`. Pinned by "an empty palette drops stroke, the way the
  others drop fill" and "an empty palette draws nothing and does not throw".
  There is deliberately no empty-palette golden, because freezing a blank is the
  failure #40 found in `sunset`.
- **The empty name hashes to 0, so every transform is the identity**
  (`translate(0 0) rotate(0 40 40)`). `rotate(0 …)` *is* the identity exactly,
  because `cos(0)` and `sin(0)` round to nothing (hidden-state #46). The empty
  name therefore keeps the closed-form rect integrator, and every edge lands on a
  pixel boundary ("a zero hash lands every edge on a pixel boundary"). Upstream
  cannot write `rotate(360 …)`, because `getUnit(n, 360)` tops out at 359.

Hidden-state rows, variant half only (mechanisms in [transforms](transforms.md),
[path-geometry](path-geometry.md), [coverage](coverage.md),
[compositing-and-masks](compositing-and-masks.md)):

| Row | What `bauhaus` writes | Live / inert here | How it was established |
|---|---|---|---|
| #8 empty palette | three bare `fill`s and a bare `stroke` | live: transparent | #39 |
| #24 abutting shapes | a background, then three shapes on top of it | **inert**, contrary to what the row said until #39. Every pair overlaps or is disjoint. The row had predicted "live" from fractional edges alone. | #39 |
| #27 Chrome's own edges | rotated rects and a rotated line | Chrome **overstates** a 4°-from-horizontal edge by 30.6/255 and a 22° one by 19, while 0° is exact. Ours is within 0.03/255 of exact coverage (Sutherland–Hodgman + shoelace) on every shape `bauhaus` draws. The calibration bar was re-scoped on 2026-08-11 because of this. | #39, [calibration](calibration.md) |
| #33 mask per group | the background and the bar both reach the mask edge | **live: the first variant to exercise it.** Measured at (14, 70) against a background-only render, so the expected value never comes from the mask's own coverage number. | "the mask scales the composited group, not each shape" |
| #42 calibration interior | a 2-unit stroked line | the interior statistic is **blind** to it: deleting the `<line>` outright leaves interior mismatches at 0 on all three cases, because a 2-unit stroke at 1 px/unit has no 3×3-uniform pixel. The edge delta moves 71 → 174–255, but the baseline is already 71 (#27). `flutter test` killed every wrong picture tried, and the Chrome run killed none. | #39, [calibration](calibration.md) |
| #45 transform order | `translate(tx ty) rotate(a cx cy)` on the bar and the rule; `translate` on the disc | live: one of three variants with a transform (all 100 non-empty renders carry one, re-verified). Pinned by an example where the two orders disagree, not by a golden. | "a list post-multiplies" |
| #46 `rotate(a cx cy)` | every rotation is about (40, 40) | built from §7.4's three-transform definition, and the test asserts one spelling against the other | "rotate(a cx cy) is its own three-transform expansion" |
| #47 stroke "paint nothing" cases | a line that is always `(0,40)–(80,40)` | unreachable from `bauhaus`. Both §11.4 cases are constructed, and driven through `rasterizeScene` as well as the helper (driving only the helper left the seam's branch untested, which a mutation found) | #39 |
| #48 libm | `Affine.rotation` places every rect and line | live: the scope of #48 widened here from curve chopping to placement | [libm-transcendentals](../invariant/libm-transcendentals.md) |

## Code

- `lib/src/variants/bauhaus.dart`: `BauhausElement`, `bauhausProperties`,
  `_translateRotate`, `buildBauhausScene`, `_size` (80), `_elements` (4)
- `lib/src/avatar.dart`: `buildAvatarScene` dispatches `bauhaus` with no
  per-drawing knob
- `test/bauhaus_parity_test.dart`: the byte sweep, "isSquare is one value shared
  by all four elements", "the line is painted by stroke, not by fill", square,
  size
- `test/bauhaus_raster_test.dart`: transform-list composition, rigid-transform
  preservation, the stroked line, "bauhaus itself", goldens
- `test/support/golden_cases.dart`: `bauhaus-clara-default` (`isSquare` true;
  bar 22°, rule 44°), `bauhaus-alice-pair` (false; 176°, 352°),
  `bauhaus-empty-name` (identity), `bauhaus-clara-square`

## Reference behaviour

- Pinned upstream: `../.refs/boring-avatars` @ v1.6.1
  `src/lib/components/avatar-bauhaus.js`, and `.tsx` @ v2.0.x.
- Fixtures: [`test/fixtures/v1_6_1/svg.json`](../../../test/fixtures/v1_6_1/svg.json).
- [calibration](calibration.md): `bauhaus-clara-default` and friends, plus the
  `bauhaus-invalid` and `bauhaus-colour4` palette cases measured against Chrome.

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md): `bauhaus.dart` is sacred surface
- [variant-design-size](../invariant/variant-design-size.md): 80
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md): `<line>`, `stroke`, `stroke-width`, `<circle transform>`
- [root-fill-none](../invariant/root-fill-none.md): the three dropped fills. The dropped stroke is safe without it.
- [libm-transcendentals](../invariant/libm-transcendentals.md): rotations place every rect and line

## Blast radius

- [transforms](transforms.md): the `translate … rotate(a cx cy)` list this builder
  writes is parsed back there. A function written in a different order or form
  lands on that parser.
- [coverage](coverage.md): a nonzero rotation sends every rect to the scanline
  integrator. Only the identity keeps the closed form.
- [path-geometry](path-geometry.md): the butt-capped stroke of the `<line>`, and
  the zero-length and single-moveto cases.
- [colour-declarations](colour-declarations.md): `stroke`'s absent/unreadable
  answer (nothing) is what this variant's empty and invalid palettes look like.
- [scene-reading](scene-reading.md): `<line fill>` and a missing `stroke-width` are
  refused there.
- [calibration](calibration.md): its interior statistic cannot see the rule, so
  a regression in the line passes there and fails only here.
- [goldens](goldens.md): four images.
- [readme-gallery](readme-gallery.md): the gallery draws through this builder.

## Known holes / open

- **The corpus cannot see a threaded `i` in `isSquare`.** Only layer-1
  assertions on constructed names catch it. Adding one corpus name with
  `hash ≡ 99 (mod 100)` would close it at layer 2, at the cost of regenerating
  every fixture.
- **The stale comment in "an absent stroke-width throws — the default arrives
  with beam"** is recorded in [beam](beam.md#known-holes--open).
