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
* The widget's `colors` is narrower than the SVG function's: the rasterizer
  reads **hex** — `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, in either case — and
  nothing else yet, and rather than draw a blank for a colour it cannot read,
  the widget throws and names the argument. A palette colour may carry its own
  transparency; its alpha multiplies the shape's coverage, as a browser does
  with the same document.
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
