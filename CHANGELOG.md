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
  reads `#RRGGBB` and nothing else yet, and rather than draw a blank for a
  colour it cannot read, the widget throws and names the argument.
