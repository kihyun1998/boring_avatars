# sunset

## What it is

The `sunset` variant: two stacked vertical linear gradients (top half and bottom
half), painted by reference from a `<defs>` that sits *outside* the masked group.
It is the only variant whose paint is a paint server, the only one that puts the
caller's name inside an `id`, and the only one where an empty palette produces a
picture (a black disc) rather than an absence. It also carries the package's
**one deliberate byte divergence from upstream**, ruling S-1.

## Governing decisions

**S-1: repair the url reference, do not reproduce the blank** (maintainer,
2026-07-29). It is recorded here as an event and listed in the
[upstream-divergences](../aggregate/upstream-divergences.md) ledger.

- **Upstream:** `avatar-sunset.js:20,36,41` @ v1.6.1 (`name.replace(/\s/g, '')`,
  the `fill={'url(#gradient_paint0_linear_' + name + ')'}` reference, the
  `id={'gradient_paint0_linear_' + name}`; the second gradient at 37 and 52).
  Re-read in the pinned tree: the same construction stands at
  `avatar-sunset.tsx:21,39–40,44,55` @ v2.0.0, v2.0.2 and `master`, so all three
  selectors carry the repair.
- **What it does:** builds a gradient id from the caller's name and references it
  as `url(#…)`. For a name containing `'`, `"`, `(`, `)`, `\` or a control
  character, the reference is not a valid CSS url token, so **the browser paints
  nothing** and the avatar is blank. Reproduced in Chrome: `O'Brien-Smith, Jr.`
  gives every pixel `0,0,0,0`, while `Clara Barton` gives the gradient. The
  corpus name `punctuation` is exactly this case, and an apostrophe in a name is
  common.
- **What the user was shown (2026-07-29):** the reference upstream emits
  (`url(#gradient_paint0_linear_O&#x27;Brien-Smith,Jr.)`), a Chrome render of it
  (every pixel `0,0,0,0`, the whole avatar blank) beside the same name rendering
  correctly once repaired, the count of affected corpus names (**1 of 20**), and
  four candidate repairs, each measured in Chrome:

  | repair | works | bytes that move |
  |---|---|---|
  | leave it (reproduce upstream) | **no — blank** | none |
  | percent-encode the **reference** only | **yes** | the two `fill` attributes |
  | quote the reference | yes | the two `fill` attributes |
  | strip the characters from the id | yes | the two ids **and** the two references |
  | percent-encode the id as well | **no — blank** | — |

- **What they chose:** repair it: *"버그는 수정하자."* Percent-encoding the
  reference is the implementation, because it is the only working repair that
  leaves `<linearGradient id="…">` byte-identical to upstream.
- **It is theirs to reverse.** This is a product judgement: it trades "the same
  bytes as upstream" for "an avatar the user can see". A later argument that the
  port should be faithful above all does **not** reopen it. Only the user does.
- **What it costs.** `sunset` is no longer byte-identical for a name containing
  `'`, `"`, `(`, `)`, `\`, `%` or a control character, which is one corpus name
  today. `sunset_parity_test.dart` lists those names explicitly
  (`const repaired = {'punctuation'}`) and asserts that the difference is
  *exactly* a percent-encoding, so the divergence cannot widen without someone
  editing that list. Every other name stays byte-identical, and so does every
  id, for every name. **The other five variants are unaffected**: `sunset` is
  the only one that puts the caller's name inside an id.
- **Why S-3 went the other way:** see [marble](marble.md). S-1 repaired a
  blank, a defect the user could see. S-3 declined to repair a slip whose two
  outcomes are both good avatars.

Adjacent: [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md) governs
what an absent or unreadable `stop-color` paints (black, per R2). This builder
only decides *that* the attribute is absent on an empty palette. ADR-0001's one
deliberate departure, throwing on a dangling `url(#…)`, exists because of the
`sunset` blank #40 found (see Design model).

## Design model

From the source and its doc-comments, plus dated measurements.

- **Four colours from one consecutive walk.** `getRandomColor(hash + i, …)` for
  `i` in 0–3 (the same walk `ring` uses): two stops for each of two gradients.
- **The ids carry the name with whitespace stripped**
  (`sunsetIdName` = `name.replaceAll(RegExp(r'\s'), '')`). Dart's `\s` matches
  exactly JavaScript's 25 code points, U+0009 through U+FEFF (measured; pinned
  by "the whitespace class is JavaScript's, not just ASCII", which checks U+00A0,
  U+3000, U+2028 and U+FEFF). This holds **as long as both stay on that
  definition**. A Dart release that widened `\s` would silently rename every
  gradient. The `<title>` carries the **raw** name.
- **React escapes the attribute, so `O'Brien` is `O&#x27;Brien` in the id and in
  the reference alike** (hidden-state #38). Keeping the raw name, or stripping a
  different whitespace class, makes the two sites drift. The reference then
  names nothing, and a browser paints nothing (measured `0,0,0,0`, hidden-state
  #43; theflow's #38 row said "black", which #43 corrected). **This is invisible
  to the byte sweep**: `normalise` erases `id="…"` and `url(#…)` on both sides,
  so any port that named its gradients anything at all would pass all 100
  renders. The harness therefore records the identifiers unnormalised
  (`derivedIdentifiers`, per name), and `sunset_parity_test.dart` ("the gradient
  ids the byte sweep cannot see") asserts the ids per name against them.
- **The repair (S-1) is `sunsetUrlReference`**. It percent-encodes, as UTF-8
  bytes, every rune that `_breaksUrlToken` flags: ≤ U+0020, U+007F, `"`, `%`,
  `'`, `(`, `)`, `\`. Korean and emoji resolve as they stand and are not encoded
  (measured in Chrome; pinned by "the repair fires only where a browser needs
  it"). `%` is included because a raw `%27` in the id would be decoded into a
  different id ("Measured: unencoded, blank", in the same test).
- **`<defs>` sits after the masked group and holds the paint** (hidden-state
  #40). A reader that skipped it the way it skips the mask's own shape drew
  every `sunset` render blank, silently. Fixed in #40 (2026-07-29) by reading
  `<defs>` into paint servers before collecting shapes. Mechanism:
  [scene-reading](scene-reading.md).
- **`fill="url(#…)"` is not "a colour that failed to parse"** (hidden-state #31).
  Before that was separated, every `sunset` render rasterised to a blank square,
  and a golden made from one would have frozen the blank as correct. Mechanism:
  [colour-declarations](colour-declarations.md).
- **The first `<stop>` carries no `offset`.** Upstream omits it, and SVG's
  initial value is 0. The second stop writes `offset="1"`.
- **Empty palette: a solid black disc** (hidden-state #39). The `<stop>`s lose
  `stop-color` (upstream emits `<stop></stop>`), and SVG's initial `stop-color` is
  **black**, where a missing `fill` paints nothing. The `fill="url(#…)"`
  references stay. Confirmed in Chrome before it was implemented. This is the
  only variant whose empty-palette answer is a picture. Pinned by
  `sunset_parity_test.dart` ("the stops lose their colour rather than the shapes
  losing fill") and `sunset_raster_test.dart` ("an empty palette paints black,
  not nothing"), and frozen as the `sunset-empty-palette` golden. A black disc is
  not a blank, so freezing it is not the #40 failure.
- **An invalid palette entry no longer throws here** (hidden-state #44,
  resolved in #64). An unreadable `stop-color` is black, by the same ADR-0001
  derivation that makes an unreadable `fill` paint nothing. Measured end-to-end
  against Chrome by `tool/calibrate`'s `sunset-invalid` and `sunset-colour4`
  cases ([calibration](calibration.md)).

Hidden-state rows, variant half only:

| Row | What `sunset` writes | Live / inert here | How it was established |
|---|---|---|---|
| #8 / #39 empty palette | `<stop>` with no `stop-color` | live: black disc | 20 names at v1.6.1, Chrome |
| #31 three no-paint states | `fill="url(#…)"` on both paths | live | #40, #69 |
| #38 name inside an id | `gradient_paint{0,1}_linear_<name sans \s>` | live: every render | `derivedIdentifiers`, re-verified |
| #40 `<defs>` holds paint | `<defs>` after `<g mask>` | live | #40 (2026-07-29) |
| #41 gradient dithering | two linear gradients | Chrome's gradient lies within 0.987 of the exact sRGB interpolation, so an exact one rounded to nearest is ≤ 1/255 across 4,548 pixels (58.6% exact) | Chrome |
| #42 calibration interior | gradients: every pixel is an edge | vacuous: the interior is empty, so "interior 0" means nothing | [calibration](calibration.md) |
| #43 dangling reference | `url(#…)` | a dangling one paints nothing in Chrome. The rasterizer throws anyway, for observability (ADR-0001's departure) | Chrome, #43 |

## Code

- `lib/src/variants/sunset.dart`: `sunsetColors`, `sunsetIdName`,
  `_breaksUrlToken`, `sunsetUrlReference`, `buildSunsetScene`, `_topHalf` /
  `_bottomHalf`, `_size` (80), `_elements` (4)
- `lib/src/avatar.dart`: `buildAvatarScene` dispatches `sunset` with no
  per-drawing knob. `boringAvatarSvg`'s doc-comment states the S-1 exception to
  callers.
- `test/sunset_parity_test.dart`: the byte sweep, "the gradient ids the byte
  sweep cannot see" (the S-1 list and the percent-encoding assertion), "what an
  empty palette does here"
- `test/sunset_raster_test.dart`: gradients against the formula, the black empty
  palette, refusals (undeclared gradient, `objectBoundingBox`, no stops, unknown
  attributes), goldens
- `test/support/golden_cases.dart`: `sunset-clara-default`,
  `sunset-empty-palette`, `sunset-hangul`, `sunset-clara-square`

## Reference behaviour

- Pinned upstream: `../.refs/boring-avatars` @ v1.6.1
  `src/lib/components/avatar-sunset.js`, and @ v2.0.x `avatar-sunset.tsx`.
- Fixtures: [`test/fixtures/v1_6_1/svg.json`](../../../test/fixtures/v1_6_1/svg.json)
  `renders` and `derivedIdentifiers.sunset`.
- [`docs/fidelity.md`](../../fidelity.md), "The three things that are not
  reproduced", item 1: the user-facing statement of S-1.
- [crosscheck](crosscheck.md): the 10 `sunset` blanks per selector run (upstream
  blank, port drawn) are S-1, and are the only `sunset` differences.

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md): `sunset.dart` is sacred surface, and the S-1 repair is part of every selector's output
- [variant-design-size](../invariant/variant-design-size.md): 80
- [scene-attribute-vocabulary](../invariant/scene-attribute-vocabulary.md): `linearGradient`, `stop`, `stop-color`, `offset`, `gradientUnits`
- [root-fill-none](../invariant/root-fill-none.md): the root's `fill="none"` is written here too, though `sunset`'s own empty-palette answer comes from `stop-color`, which does not inherit
- [libm-transcendentals](../invariant/libm-transcendentals.md): only through the rounded mask's arcs, and through Color 4 palette conversions
- [byte-gates-erase-ids](../invariant/byte-gates-erase-ids.md) — name-derived gradient ids are pinned only by `derivedIdentifiers`.
- [sunset-url-character-list](../invariant/sunset-url-character-list.md) — `_breaksUrlToken` is the source of the list.

## Blast radius

- [scene-reading](scene-reading.md): `<defs>` is read into paint servers before
  shapes are collected. A new child or attribute there is refused, and a
  reference to an undeclared gradient throws rather than painting nothing.
- [colour-declarations](colour-declarations.md): `stop-color`'s absent/unreadable
  answer (black) is what this variant's empty and invalid palettes look like.
  Changing that rule moves this picture.
- [svg-emission](svg-emission.md): the `&#x27;` escaping must stay identical on
  the id and the reference, or they stop naming each other.
- [parity-harness](parity-harness.md): the byte sweep cannot see the ids, so the
  `derivedIdentifiers` record is the only layer-2 evidence for them.
- [crosscheck](crosscheck.md): a widening of `_breaksUrlToken` would move bytes
  for names Chrome already resolves. The crosscheck's ruled count is the only
  place that would show it in pixels.
- [goldens](goldens.md): four committed images, including the black empty-palette
  disc.
- [calibration](calibration.md): its interior statistic is vacuous on a gradient.
  The gradient bar there is the ≤ 1/255 row #41 measured.
- [public-svg-surface](public-svg-surface.md): `boringAvatarSvg`'s doc-comment
  states the S-1 exception, and its character list must track
  `_breaksUrlToken`.
- [readme-gallery](readme-gallery.md): the gallery draws through this builder.

## Known holes / open

- **The character list that S-1 repairs is stated in four places, and they
  disagree on `%`.** `_breaksUrlToken` (the truth) includes `%`, and so does
  this note's cost line. theflow's S-1 row, `docs/fidelity.md` item 1, and
  `boringAvatarSvg`'s doc-comment list `'`, `"`, `(`, `)`, `\` and control
  characters only. Upstream's raw `%XX` in a name also blanks (measured, per
  the test comment), so `%` is a real member that is missing from the
  user-facing statements.
- **`sunset.dart`'s doc-comment on `sunsetUrlReference` points at "the divergence
  ledger in `docs/agents/theflow.md`"**. That pointer dangles once theflow.md is
  deleted. The ledger is now
  [upstream-divergences](../aggregate/upstream-divergences.md).
- **The `\s` equivalence is measured, not guaranteed.** It holds while Dart's
  `RegExp` and ECMAScript share the WhiteSpace + LineTerminator definition.
