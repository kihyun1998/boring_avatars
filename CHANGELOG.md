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

This release ships the SVG document only. A deterministic rasterizer and a
`BoringAvatar` widget follow in a later release; until then, drawing the string
in Flutter needs a third-party SVG renderer and those pixels are that package's.
