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
