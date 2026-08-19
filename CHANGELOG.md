## 0.3.2

Stops claiming an **unfiltered draw** where one buffer pixel cannot cover one
device pixel (#117). No avatar's *values* change, and no avatar that was already
landing on the grid changes at all — the bytes there are identical to `0.3.1`.

* **`FilterQuality.none` is exact under one condition, and it was being asserted
  unconditionally.** The widget rasterises at the box's physical size and hands
  the buffer over with no filter, which is right while the drawing lands one
  buffer pixel per device pixel. `0.3.1` bought the origin and the extent for
  that (#110), and a *translation* is all a placement can fix.
* **Two ordinary situations are outside what any placement reaches**: an
  ancestor that **scales or rotates**, where this box's grid is not the device's
  grid at all; and a **buffer that is not the destination's size** — a parent
  squeezing the box, or a display-scale change that leaves the previous buffer
  up until the new one is drawn.
* **There, nearest neighbour is the worst available choice rather than the
  safest.** It cannot spend a fraction of a pixel, so it drops or duplicates
  whole columns. Measured under a 1.1 scale: **7** columns of the drawing came
  out byte-identical to their neighbour — a straight fold across `marble`'s
  gradient, which is the shape #117 reported.
* **So those draws are filtered now** — half a pixel of softness in place of a
  fold. A **fractional translation is deliberately not** one of them: the snap
  moves the drawing by the same fraction the ancestors moved it, so the pixels
  still land whole, and treating it as misaligned would put a filter under every
  ordinary padding.
* **This narrows the determinism guarantee's stated scope without spending any
  of it.** Where the avatar lands one pixel per pixel — the overwhelming
  majority — the bytes are unchanged. Where it does not, the output was already
  the backend's: which source column nearest neighbour keeps is the sampler's
  rounding, so Skia and Impeller were never obliged to agree there. The ruling
  (2026-08-18) chose between a fold whose position is the backend's and a
  softness whose position is the backend's.
* **What this does not reach, stated rather than implied.** The decision is made
  while painting, so a layer that moves *without* its child repainting — a
  scrolling `ListView` — is outside it exactly as it is outside `0.3.1`'s
  alignment (flutter/flutter#111302). It comes back the moment the row repaints.
* **The anti-aliased rounded clip named in the report is not the cause**, and
  that is measured rather than argued: on a real engine at 150% scaling, a
  clipped avatar is **byte-identical** to one with no ancestor at all.
* **And it fixes the case the report was actually hitting, by reversing what
  `0.3.1` decided about *which grid* to align to.** That release corrected
  against the screen position, on the reasoning that a layer carries its
  fraction to the engine unrounded. The engine rounds it. So inside any
  compositing ancestor — a scroll viewport, an `Opacity` or `FadeTransition`, a
  `RepaintBoundary` — the correction was applied twice and the drawing landed
  half a pixel off. The alignment is now done in the space the widget paints
  into, leaving the layer to the engine.
* **Measured on a real engine at 150% scaling**, against the same avatar with no
  ancestor, with the enclosing layer half a device pixel past an integer:
  `0.3.1` differs in **2921 of 4356** pixels by up to **196** levels; `0.3.2` is
  **byte-identical**. **Nothing changes where there is no layer** — the paint
  offset is then the screen position and both rules compute the same rectangle.
* **Why `0.3.1` could not have seen this.** Every measurement behind it went
  through `RenderRepaintBoundary.toImage`, which re-rasterises a subtree
  offscreen and never runs the engine's composite onto the window — the step
  where the rounding happens. The instrument that found it was a screen
  capture.
* **On web it is a non-regression rather than a fix, and that is measured too.**
  Chrome at a 1.5 device pixel ratio does not round the enclosing layer — a
  plain vector circle in the same frame comes out a device pixel wider at a
  fractional origin, and the surface itself is 1897.5 physical pixels, so the
  page is off the grid before any widget sees it. Neither placement lands whole
  there; the new one at least keeps the drawing's extent exact (66 device pixels
  against `0.3.1`'s 67). macOS, iOS and Android are unmeasured.

The rule and the ruling behind it are ADR-0002 (R5); the layer finding and its
limits are in the same record.

## 0.3.1

Fixes a **shaved edge** on `BoringAvatar` when the widget lands on fractional
device pixels (#110). No avatar's *values* change: every selector renders the
same bytes it did in `0.3.0`, and the fix is entirely about where those bytes
land on screen.

* **A whole pixel column was dropped or duplicated, and both read as a straight
  cut.** The buffer is rasterised at `(size * dpr).round()` physical pixels and
  used to be painted into a rectangle of `size * dpr` *unrounded* ones. A
  rectangle whose width is fractional has its two edges rounded independently,
  so where it starts decides how wide it ends up. Measured at `size: 45` — 150%
  scaling paints a 68-pixel buffer across 67.5 and **loses** a column; 125%
  paints 56 across 56.25 and **gains** one.
* **Both conditions are necessary and neither is enough.** A fractional origin
  under a whole ratio is absorbed, and so is a fractional size at a whole
  origin; only together do they cost a column. Both cases are in the suite, so
  the fix cannot be narrowed to one of them by accident.
* **Every non-`square` variant is exposed to it with nothing to hide it in.**
  The mask is a disc tangent to all four edges of its box with zero margin, and
  a disc's outline is *vertical* at its leftmost and rightmost points — so the
  lost column is a tall straight sliver rather than a nibbled corner. An icon
  with any interior padding would absorb the identical loss.
* **In a list it was worse, and less obvious.** `ListView` wraps every child in
  a `RepaintBoundary`, and `Opacity`, `FadeTransition` and `Hero` push layers of
  their own; a layer carries the fractional position itself and paints its child
  at a whole-looking offset, so an avatar inside one was on the wrong grid while
  reading as correct. The fix takes the widget's **screen** position rather than
  its offset within the enclosing layer, so it sees through all of them.
* **A *scrolling* list is the one case this does not reach, and it is stated
  rather than implied.** The alignment is computed while painting, and a layer
  can move without its child repainting — which is precisely what scrolling a
  `ListView` does. Measured: after a 7.3-logical scroll at ratio 1.5 the
  destination was **11.2 device pixels** stale because `paint` never re-ran. So
  an avatar sitting in a list is on the grid; one being scrolled past is not,
  until it repaints. No widget can close that from the inside — Flutter tracks
  it as flutter/flutter#111302, and its own text caret snaps with the same
  limitation.
* **The fix rounds the drawing onto the device pixel grid** and draws a whole
  number of device pixels. The avatar moves by at most half a physical pixel
  from where layout put it; a parent that squeezes the box below `size` still
  scales the drawing exactly as before. This is what README's determinism
  section now describes.
* **One case is narrowed rather than closed, and it is stated rather than left
  to be discovered.** Where `size × dpr` rounds *up*, the buffer is genuinely
  wider than the box — 45 logical at 150% is 67.5 physical pixels holding a
  68-pixel buffer — so an ancestor clipping to exactly the box takes the excess
  back off, which is this bug's symptom again. No placement avoids it; 68 does
  not fit inside 67.5. Measured across 105 combinations of ratio, inset and
  clip: **21 were wrong before, 6 are wrong now, and the 6 are among the 21** —
  narrowed, with nothing regressed. A clip even slightly larger than the avatar
  avoids it. Closing the rest would mean rasterising at `floor` rather than
  `round`, and that was weighed and **declined**: it closes only a third of the
  cases while narrowing the smallest `size` this widget accepts, and the variant
  that closes all of them stops the avatar touching the edges of its own box —
  which is what every non-`square` variant is. Should you need the guarantee, it
  will arrive as something you opt into rather than as a changed default.

## 0.3.0

Adds upstream `boring-avatars` **1.10.1, 1.10.2, 1.11.1, 1.11.2 and
2.0.0–2.0.4** as `BoringAvatarsVersion.v1_10_1` — upstream's newest release
included. **Purely additive** — `v1_6_1` and `v1_7_0` render the same bytes
they did in `0.2.0`, re-proven by regenerating both fixtures from the real npm
packages: not one render byte moved and the committed golden images are
untouched.

With this release the public API is settled: every upstream release worth
reproducing has a selector, and future work is keeping up with upstream's
future releases.

* **`pixel` draws differently from 1.10.1, and that is the whole change.**
  Upstream moved the variant's colour index — `getRandomColor(numFromName % i)`
  became `getRandomColor(numFromName % (i + 1))` — so every tile shifts one
  palette step and the first tile, which the old expression left unfilled
  (`hash % 0` is `NaN` in JavaScript), is now filled with `colors[0]`. The
  other five variants render byte-identically to `v1_7_0`, asserted across the
  full corpus.
* **Nine releases share the selector because a caller gets the same thing out
  of all nine — measured, not read off the diffs.** Each of the other eight is
  rendered and compared to 1.10.1 across 2,400 documents (variant × name ×
  palette × title × square): zero differ, per release. Their sources genuinely
  diverge — a props rework at 1.11.1/1.11.2, a TypeScript rewrite at 2.0.0 —
  and none of it reaches the document.
* **`1.11.0` is deliberately unsupported.** It spreads its own props onto the
  `<svg>` element (`colors="…" name="…"` arrive as markup), which no other
  release does; upstream fixed it in 1.11.1. Reproducing it would mean
  reproducing those attributes. It is the one hole in an otherwise contiguous
  range, documented on the enum and in the README.
* **`2.0.3` and `2.0.4` have no git tag** — upstream's tags stop at `v2.0.2`.
  They are covered from the npm packages themselves; npm records the commit
  each was published from, both commits resolve in upstream's history to one
  source tree (`master`'s), and that resolution is recorded in the committed
  fixture rather than asserted here.
* `BoringAvatarsVersion.latest` **has moved** from `v1_7_0` to `v1_10_1`. If
  you passed `latest` before, every `pixel` avatar you render redraws on
  upgrade — which is what passing `latest` means. Name a selector to pin an
  avatar.
* The whole range was put through a real browser, per selector: upstream's own
  React output and this package's, rendered in one Chrome — `v1_10_1` checked
  against **2.0.4**, the far end of its group. 1,200 renders per selector,
  zero unexplained pixel differences in any run (the only differing cases are
  the two divergences `0.1.0` shipped with: the repaired `sunset` blank and
  `beam`'s empty-palette throw, both documented in the README).

## 0.2.0

Adds upstream `boring-avatars` **1.7.0, 1.8.0, 1.9.0 and 1.10.0** as
`BoringAvatarsVersion.v1_7_0`. **Purely additive** — `v1_6_1` renders the same
bytes it did in `0.1.0`, so nothing you have already shipped changes.

* **`<title>` is optional from 1.7.0, and defaults to off** — upstream's own
  default. That is the entire difference between the two selectors: measured
  against the reference tree, the 1.6.3 → 1.7.0 source diff is 7 files and 14
  lines, of which 6 are the title and 6 are whitespace inside a JSX expression
  that reaches no output. With `title: true`, `v1_7_0` and `v1_6_1` render
  byte-identical documents for every variant.
* `boringAvatarSvg` takes a new `title` argument. It is `bool?` rather than
  `bool` because the two selectors disagree about the default, and either
  literal would be silently wrong for one of them. `title: false` with
  `v1_6_1` throws an `ArgumentError` naming the argument — 1.6.x has no such
  prop and cannot switch the element off, and upstream would ignore the
  request rather than tell you.
* `BoringAvatarsVersion.latest` **has moved** from `v1_6_1` to `v1_7_0`. If you
  passed `latest` in `0.1.0` and relied on `<title>`, you lose it here — which
  is what passing `latest` means. Name a selector to pin an avatar.
* `BoringAvatar`, the widget, is unchanged and takes no `title` argument:
  `<title>` is not drawn, so accepting the choice would be accepting a value
  nothing reads. Use `Semantics` to announce an avatar in Flutter.
* Four upstream releases share one selector, and each is measured rather than
  assumed. 1.10.0 is rendered and compared to 1.7.0 across 1,200 documents —
  **zero differ**. 1.8.0 and 1.9.0 shipped npm tarballs with no JavaScript in
  them at all, so nothing can render those; their evidence is that their
  `src/lib` git tree is 1.10.0's, byte for byte. Both records live in the
  committed fixture, not in prose.
* The one difference inside the group is the mask `id` — a literal at 1.7.0,
  React's `useId()` from 1.8.0. It names nothing a reader sees and depends on
  the component's position in the render tree, so this package emits the
  literal. The fixture records both, unnormalised, rather than leaving the
  exclusion implicit.

## 0.1.0

First release. Reproduces upstream `boring-avatars` **1.6.1, 1.6.2 and 1.6.3**
— the three releases that share one output — as `BoringAvatarsVersion.v1_6_1`.

* `boringAvatarSvg(...)` returns upstream's SVG document as a string, byte for
  byte, for all six variants: `marble`, `beam`, `pixel`, `sunset`, `ring` and
  `bauhaus`. Upstream's two deprecated names, `geometric` and `abstractStyle`,
  resolve exactly as upstream resolves them.
* `version` and `size` are **required**. A default `version` would make the
  avatars in your app change on a dependency upgrade, which is the one thing a
  frozen selector exists to prevent.
* Verified against the real npm package rendered through `react-dom/server`:
  600 documents (6 variants × 20 names × 5 palettes), plus square and size
  variations. Names include empty strings, Hangul, CJK, emoji ZWJ sequences,
  newlines and 200-character inputs.
* Two inputs deliberately do **not** reproduce upstream, both documented in the
  README: `sunset` with a name containing `'`, `"`, `(`, `)` or `\` (upstream
  paints a blank avatar; this package renders it), and a `size` that is neither
  a `num` nor a `String` (upstream drops the attributes; this package throws).

* `BoringAvatar` draws the same avatar as a widget, rasterised in software at
  the display's physical pixel size. Not through `flutter_svg` — measured, it
  does not clamp `rx` per SVG 1.1 §9.4, so the circular mask comes out square,
  and it has no `<filter>`, so `marble` loses its blur. Not through `Canvas`
  either, which would make the pixels depend on Skia-vs-Impeller, GPU, platform
  and Flutter version.
* The rasterizer reads the whole practical CSS `<color>` grammar: hex
  (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`), the **148 CSS named colours**,
  `transparent`, `currentColor`, `rgb()` / `rgba()` / `hsl()` / `hsla()`
  (either separator, percentages or 0–255, alpha as a number or a percentage,
  hue in `deg` / `grad` / `rad` / `turn`), the Color 4 families — `hwb()`,
  `lab()` / `lch()`, `oklab()` / `oklch()`, `color()` with every predefined
  space — and the 42 system colours, frozen at Chrome's macOS light-mode
  values. Out-of-gamut colours clip per channel, as Chrome was measured
  doing. Keywords are ASCII case-insensitive and tolerate surrounding
  whitespace. Not read, deliberately: `none` components, relative colour
  syntax, and `calc()`. Anything outside that grammar draws what a browser draws for an
  invalid declaration — the shape is not painted, and a gradient stop falls
  back to black; measured against Chrome. The widget still rejects such a
  palette up front, naming the argument, so a typo fails loudly.
* A palette colour may carry its own transparency, and its alpha multiplies the
  shape's coverage, as a browser does with the same document.
* The named-colour table is generated from the CSS Color 4 specification and
  cross-checked against a real Chrome render — 148 of 148 agree.
* **The drawing happens off the frame.** A background isolate on native; on the
  web, where Flutter has no isolate to offer, the rasterizer yields the thread
  between bands instead. Your app stays responsive while an avatar draws, and
  the box is its final size from the first frame, so nothing reflows when the
  picture arrives — but it arrives a beat later rather than immediately. Web is
  about four times slower than native for the same drawing; the README carries
  the measured numbers.
* **One physical size per variant is markedly cheaper than its neighbours.**
  Each variant has a design size — 80 for `marble`, `pixel`, `sunset` and
  `bauhaus`, 90 for `ring`, 36 for `beam` — and asking for exactly that many
  physical pixels is the one case where an axis-aligned rectangle keeps an exact
  closed-form coverage instead of going through the polygon integrator. Same
  picture; measured, `pixel` is 6.5x cheaper at 80 than at 81. Worth knowing if
  you draw many avatars and can choose `size × devicePixelRatio`.
* Only one raster runs at a time per widget. A burst of changing sizes draws
  once, at the size that survived, rather than once per frame.
* Changing `name`, `colors`, `variant`, `version` or `square` clears the avatar
  while the new one draws, because the old pixels are a picture of somebody
  else. Changing `size` alone keeps the current one on screen until the sharper
  version is ready.
* `size` must be finite and positive, and must survive the device pixel ratio.
  Each failure throws an `ArgumentError` naming `size` and saying which of the
  two it was.
* A raster that fails reports through Flutter's error machinery instead of
  vanishing, and the widget clears rather than leaving a stale avatar up.
