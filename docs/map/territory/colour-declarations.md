# colour-declarations

## What it is

How the rasterizer turns a colour-valued attribute — a `fill`, a `stroke`, a
`<stop>`'s `stop-color` — into paint. It owns the four-state reading of a
declaration (`readColourDeclaration`: absent / `none` / read / unreadable), the
`<color>` grammar behind "read" (hex, the 148 named colours, `transparent`,
`currentColor`, the legacy and Color 4 colour functions, the 42 system colours),
the Color 4 conversion maths, how each of the three properties answers each
state, how a translucent palette colour composes with shape coverage, the
straight-alpha gradient interpolation, and the Chrome measurement harness
`tool/colour4/` that the Color 4 and system-colour tables were taken with. The
palette itself is the caller's (`CLAUDE.md`, boundary rule); this territory is
what the raster path does with whatever string arrives. The SVG emitter passes
the same strings through untouched and a browser reads them — that path is
[svg-emission](svg-emission.md)'s, not this one.

## Governing decisions

- [ADR-0001 — what a colour declaration means](../../adr/0001-what-a-colour-declaration-means.md)
  (Accepted 2026-08-10, user ruling on #71). Two rules derive every cell of the
  (property × declaration state) grid: **R1** validity is the property's
  grammar (SVG 1.1 §11.2 `<paint>` for `fill`/`stroke`, §13.2.4 for
  `stop-color`, which admits neither `none` nor `<funciri>`); **R2** an invalid
  declaration is ignored (CSS 2.1 §4.2) and the slot takes the inherited value
  if the property inherits, else the initial value (§6.1.1). Conformance items:
  #69, #62, #63, #64, #95 — all complete.
  - **What the user was shown** (ADR-0001 "수락"): the two rules and the full
    grid; the behavioural consequence that an unreadable `stop-color` changes
    from a throw to black (#64); the one deliberate departure (dangling
    `url(#…)` throws); and the one known hole — the whole `fill` column hangs
    on the root `<svg fill="none">`, which the rasterizer does not read. Three
    options: accept as is / accept with a root guard as an AC on #62 / grill
    the record first. **They chose "accept as is"**, so the root guard was
    *not* built and stands as the record's validity condition — a defect seen
    and passed, not a silent one. Theirs to reverse.
  - **The one decision that is not a derivation:** a dangling `url(#…)` throws
    `UnsupportedSceneError` although derivation and Chrome (#43, `0,0,0,0`)
    both say "paint nothing" — for observability, because before #40 an unread
    paint silently blanked all of `sunset`. A better derivation does not
    overturn it; a person does.
- **Why the colour work is in `0.1.0` at all — user ruling, 2026-08-10.** It
  had no milestone; the agent proposed `0.3.0` beside the Chrome sweep. The
  user ruled the other way: *"0.1.0 도 사람들이 쓰는 릴리스"* — delay is
  acceptable, breaking `0.1.0`'s coherence is not. The test applied: colour
  parsing is not on the release axis (the upstream output state), since the
  palette is the caller's — nothing here creates a fourth output state or
  touches `v1_6_1`. The stronger argument recorded with it: without the work
  `0.1.0` carried two palette contracts (`boringAvatarSvg` passes any string;
  the widget threw on anything not `#RRGGBB`), and #64 was a one-way door —
  ruled after publish, one input would throw for `0.1.0` users and render for
  the next release's. #95 joined on the same criterion (user ruling
  2026-08-11, after #64's pass found the Color 4 remainder unlearned: *"learn
  them"*): publishing first would put a release that refuses valid colours in
  people's hands. What it did **not** license: #50 stays in `0.3.0` on its own
  merits. (Release table: [release-and-publishing](release-and-publishing.md).)
- Adjacent, not governing: [ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md)
  says so itself — it decides pixel placement, not colour meaning.
  `_readMask`'s `fill != '#FFFFFF'` guard is deliberately outside this
  vocabulary (ADR-0001, "이 기록이 정하지 않는 것"): it asks a byte-identity
  question, owned by [scene-reading](scene-reading.md) and the
  [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md)
  invariant.

## Design model

From ADR-0001 and the source (status: **record-governed**; the grid is in the
record, the code cites it at each call site).

**Four states, read once.** `readColourDeclaration` returns a sealed
`ColourDeclaration`: `AbsentColour` (attribute never written), `NoneColour`
(`none`, after ASCII lower-casing and CSS-whitespace trimming), `ParsedColour`,
`UnreadableColour`. `url(#…)` is not a state of this type: `resolvePaint`
branches on the `url(` prefix *before* reading the declaration, and the
`<rect stroke>` refusal keys on it the same way. Three of the states draw
nothing in a `fill`, by three different decisions that no picture can tell
apart — which is why #69 named them (hidden-state #31; war story:
[lessons.md, "An output-neutral change is invisible…"](../../agents/lessons.md)).

**The answers, per property** (re-verified in `scene_raster.dart` at HEAD):

| state | `fill` (`resolvePaint`) | `stroke` (`resolvePaint`; on `<rect>` only a non-painting stroke is read) | `stop-color` (`_readLinearGradient`) |
|---|---|---|---|
| absent | nothing — *because* root `fill="none"` is inherited | nothing — initial value `none` | **black** — not inherited, initial black |
| `none` | nothing (§11.2) | nothing | **black** — outside §13.2.4, R2(c) |
| `url(#…)` present | that paint server | that paint server (but `<rect stroke="url(…)">` throws: would paint an outline) | n/a |
| `url(#…)` dangling | **throws** (the one decision) | throws | n/a |
| read colour | the colour | the colour | the colour |
| unreadable | nothing (since #64) | nothing (since #64) | **black** (since #64; threw #69→#64) |

**The `fill` column's mechanism is not the browser's** (ADR-0001 discrepancy
②): we answer "unreadable → nothing" directly; a browser ignores the
declaration and inherits the root's `none`. Same answer while every variant's
root declares `fill="none"` — measured in all 600 fixture renders (#8, #17).
This is the [root-fill-none](../invariant/root-fill-none.md) invariant; the
day a root declares a colour, absent and unreadable fills silently paint it,
and nothing throws. `currentColor` is black for the same reason: measured
`0,0,0,255` in a document declaring no `color` (#63), valid while nothing this
package emits declares `color`. `inherit` is unmeasured and upstream never
writes it.

**Grammar, R1 not "what the parser reads".** `parseCssColour` dispatches:
`#` → `parseHexColour` (all four hex forms, short forms double every digit
*including alpha* — `#F008` alpha is 136, measured; a sign is rejected because
`int.tryParse('+12345', radix: 16)` succeeds); `transparent` →
`RasterColour(0,0,0,0)`; `currentcolor` → black; `namedColours`;
`systemColours`; else `_parseColourFunction` (rgb/rgba/hsl/hsla either
separator; hwb, lab/lch, oklab/oklch, color() with predefined spaces via
`colourFunctionSpaces`). Number tokens go through a CSS-shaped regex
(`_cssNumberToken`) because `double.tryParse` accepts forms CSS does not;
huge components clamp to the float range (`_clampCssFloat`). `#FF00` is a
valid `#RGBA` — yellow at alpha 0 — and so draws nothing by *painting*
nothing, not by being ignored; #62's own AC had filed it as invalid
(war story: [lessons.md, "A ticket's own acceptance criteria put a valid value
in the invalid cell"](../../agents/lessons.md)).

**Recorded scope, not accident:** `none` components, relative colour syntax
and `calc()` are valid CSS that Chrome draws; they land in `UnreadableColour`
deliberately (#95), pinned in `raster_colour4_test.dart`.

**Data files have provenance rules** (re-verified in their headers):
`named_colours.dart` is *generated* from CSS Color 4 §6.1 and cross-checked
against Chrome (148/148) — two independent sources, because generating from
Chrome and testing against Chrome is a tautology, and a hand-typed table is
wrong only for the palette that names the typo. `system_colours.dart` is
generated from a Chrome 151.0.7922.108 measurement on macOS light mode via
`getComputedStyle`, cross-checked against a rendered strip — for system
colours UA discretion makes **the measurement the specification**; packed
`0xAARRGGBB` because `highlight` carries alpha 153. `colour_spaces.dart`
derives its matrices from the primaries' chromaticities at load rather than
transcribing the spec's rationals; its gamut model is **per-channel clip**,
measured on Chrome 151 (`color(display-p3 1 0 0)` → exactly `255,0,0`), with
exactly one copy of the clip, at `_encodedToColour`, because a second copy was
unkillable by construction.

**Alpha.** A colour's alpha multiplies the shape's coverage rather than
replacing it (`RasterImage.blend`, and `_drawThroughLayerSteps`'s `put`):
`#FF000080` over white is `255,127,127` at full coverage and `255,191,191` at
half — both measured in Chrome (#62). A gradient interpolates alpha
**straight**, like any channel (`LinearGradientPaint._sample`): `#FF000000` →
`#0000FFFF` over white has midpoint `191,128,191` in Chrome where premultiplied
gives `127,127,255` — upstream never writes such a stop, so every golden would
have stayed green under the wrong model (war story: [lessons.md, "A model with
two candidates that no golden can distinguish…"](../../agents/lessons.md)).
Gradients mix in sRGB (SVG `color-interpolation` default), sampled at the pixel
centre.

**Two backends, one palette.** The widget refuses at its seam
(`_BoringAvatarState._checkPalette`, `ArgumentError` naming `colors`) any
entry `parseCssColour` returns `null` for, while `boringAvatarSvg` passes it
through. An empty palette is *not* refused there — it is S-2's territory
(`beam` throws, five render degraded).

**New properties** (`flood-color`, `lighting-color`, `color`): ADR-0001 says
derive them from R1 + R2 using three spec facts — grammar, inheritance,
initial value — rather than add a row.

**Outside input:** palette strings come from the caller and nothing bounds
their length or count; the variants index into the list, so only the entries
a name selects are ever parsed by the scene, while `_checkPalette` parses
every entry on every build.

## Code

- `lib/src/raster/raster.dart` — `RasterColour`, `ColourDeclaration`,
  `AbsentColour`, `NoneColour`, `ParsedColour`, `UnreadableColour`,
  `readColourDeclaration`, `parseHexColour`, `parseCssColour`,
  `_cssNormalise`, `_isCssSpace`, `_cssNumberToken`, `_cssNumber`,
  `_clampCssFloat`, `_parseColourFunction`, `_cssComponent`, `_cssHue`,
  `_cssAlpha`, `_hslToRgb`, `_encodedToColour`, `RasterImage::blend`,
  `SolidPaint`, `SolidPaint::hex` (test shorthand — folds `none` and
  unreadable into `null`; not the scene's route), `LinearGradientPaint`,
  `LinearGradientPaint::_sample`, `_drawThroughLayerSteps` (its `put` closure
  multiplies colour alpha by coverage).
- `lib/src/raster/named_colours.dart` — `namedColours` (generated).
- `lib/src/raster/system_colours.dart` — `systemColours` (generated).
- `lib/src/raster/colour_spaces.dart` — `ColourSpace`,
  `colourFunctionSpaces`, `hwbToEncoded`, `labToEncoded`, `oklabToEncoded`,
  `lchToAb`,
  `encodeLinearSrgb`, `_rgbToXyz`, `_adapt` (Bradford), `_srgbEncode`.
- `lib/src/raster/scene_raster.dart` — `_shapesOf::resolvePaint` (fill and
  stroke), the `<rect>` arm's `declaredStroke` refusal,
  `_readLinearGradient` (stop-color switch).
- `lib/src/widget/boring_avatar.dart` — `_BoringAvatarState::_checkPalette`.
- `tool/colour4/` — `gen.mjs` + `read.mjs` (swatch strip through
  `tool/calibrate/render.mjs`'s headless Chrome, read back per pixel; the
  probe SVG has *no* root `fill="none"`, so a refusal shows as inherited black
  and `zzz` is the baseline control), `sys.mjs` (system colours via
  `getComputedStyle`, run from `tool/crosscheck` which owns playwright-core).
  A tool, not a gate: `flutter test` reads the committed tables and never runs
  Node. Reference run: Chrome 151.0.7922.108, macOS, light, 2026-08-11.
- Tests: `test/raster_colour_test.dart` (the states told apart, per
  property), `test/raster_alpha_test.dart` (#62: hex forms, alpha × coverage,
  straight gradient alpha), `test/raster_css_colour_test.dart` (#63: 148
  names, keywords, rgb/hsl), `test/raster_colour4_test.dart` (#95: every byte
  a Chrome measurement; out-of-scope forms pinned), `test/widget_test.dart`
  group "the palette this surface accepts is narrower, and it says so".
  Mutation cases: `tool/mutate/cases/64-invalid-colours.json`.

## Reference behaviour

- SVG 1.1 §11.2–11.4 and §13.2.4; CSS 2.1 §4.2 and §6.1.1; CSS Color 4 §5.2
  (hex), §6.1 (named), §6.2 (system, `transparent`), §8 onwards (functions) —
  cited and applied in [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md).
- Chrome, end to end: `tool/calibrate` cases `bauhaus-invalid` /
  `sunset-invalid` (#64: mixed valid/invalid palette, interior-exact),
  `-named`, `bauhaus-colour4` / `sunset-colour4` (#95: interior-exact), and
  the translucent stacked-variant case (interior ≤1/255) — see
  [calibration](calibration.md).
- Chrome, per value: #64's table (`zzz`, `""`, `none`, `transparent` × fill /
  stop-color) checks ADR-0001's derivation row for row; #63's 148/148 name
  cross-check and `currentColor` = black; #95's swatch strip + computed-style
  read (`tool/colour4`). Empty palette → `sunset` black disc confirmed in
  Chrome before it was implemented (hidden-state #39).

## Cross-cutting invariants

- [root-fill-none](../invariant/root-fill-none.md) — the `fill` column's
  absent and unreadable answers are only correct because every root declares
  `fill="none"`; `resolvePaint` never reads the root.
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md) —
  `_readMask`'s literal `#FFFFFF` is the one colour-looking string this
  vocabulary deliberately does not read.
- [libm-transcendentals](../invariant/libm-transcendentals.md) —
  `colour_spaces.dart` calls `math.pow` (every transfer function) and
  `math.cos`/`math.sin` (lch/oklch hue), so a Color 4 palette's bytes ride
  platform libm too.
- [frozen-selector-output](../invariant/frozen-selector-output.md) — not by
  location (this is `lib/src/raster/`, not the sacred surface) but by effect:
  changing a `RasterColour` any upstream palette reaches would move goldens.

## Blast radius

- [sunset](sunset.md) — the only variant whose empty or invalid palette is a
  *picture* (black stops); any change to the `stop-color` column redraws it.
- [beam](beam.md) — the only variant that writes `fill="none"` (44 of 80
  renders) and `stroke="none"` (160); `NoneColour` handling is what keeps it
  from throwing or painting.
- [pixel](pixel.md), [bauhaus](bauhaus.md), [ring](ring.md),
  [marble](marble.md) — their unfilled shapes rely on "absent fill paints
  nothing", which is true only through root-fill-none.
- [scene-reading](scene-reading.md) — the `url(` branch and the `<rect stroke>`
  refusal sit outside `readColourDeclaration`; a new paint form has to be
  taught in both places or the vocabulary and the refusal disagree (#64's
  "third reader", [lessons.md](../../agents/lessons.md)).
- [widget-lifecycle](widget-lifecycle.md) — `_checkPalette` refuses exactly
  what `parseCssColour` returns `null` for; widening or narrowing the grammar
  moves the widget's public contract with it.
- [compositing-and-masks](compositing-and-masks.md) — alpha × coverage is
  applied inside the blend; a premultiplied change there would alter every
  translucent palette's result.
- [calibration](calibration.md) — the `-invalid` / `-named` / `-colour4` /
  translucent cases are where a colour change is checked against Chrome.
- [svg-emission](svg-emission.md) — emits the palette strings unread; the two
  backends agree only while this grammar reads what a browser reads.

## Known holes / open

- **Root guard not built** (ADR-0001 validity condition, user chose to accept
  without it): a variant root declaring a `fill` colour would silently flip
  the `fill` column. Signal: any variant root writing a colour `fill`.
- **The widget's refusal rationale has aged and is unruled.** Hidden-state #20
  recorded that `_checkPalette`'s stated reason ("the raster path cannot read
  it") was aged by #64 — the raster now *does* answer an unreadable entry, as
  a browser would — and that this was **flagged to the user rather than
  edited**. No ruling is recorded. `docs/colors.md` now gives a different
  reason ("so a typo fails loudly instead of as a missing shape"); the
  doc-comment on `_checkPalette` still says "cannot read".
- **System colours are frozen to one platform** (Chrome 151, macOS, light);
  forced-colors, dark mode and accents are not modelled — by design, but a
  caller on another OS gets values their browser would not.
- `inherit` is unmeasured; upstream never writes it.
- **Small factual drift between surfaces:** `tool/colour4/README.md` says the
  strip is 86 swatches; `raster_colour4_test.dart`'s header says 73. Not
  settled by the code.
- If a future Chrome adopts §13's chroma-reduction gamut mapping, the
  out-of-gamut swatches in `raster_colour4_test.dart` disagree first; the
  frozen tables would then be "matches Chrome 151", not "matches Chrome".
