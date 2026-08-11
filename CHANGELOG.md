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
