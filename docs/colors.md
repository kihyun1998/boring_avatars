# Which colours a palette may hold

`boringAvatarSvg` hands a colour to the document and a browser draws it, so
*any* CSS colour works there. `BoringAvatar` draws the colour itself, so its
palette is narrower — **but not by much any more.** The rasterizer reads:

* hex — `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`;
* the **148 CSS named colours**, plus `transparent` and `currentColor`;
* `rgb()` / `rgba()` / `hsl()` / `hsla()` — either separator, percentages or
  0–255, alpha as a number or a percentage, and a hue in `deg`, `grad`, `rad`
  or `turn`;
* the CSS Color 4 families — `hwb()`, `lab()` / `lch()`, `oklab()` /
  `oklch()`, and `color()` with every predefined space (`srgb`,
  `srgb-linear`, `display-p3`, `a98-rgb`, `prophoto-rgb`, `rec2020`, the
  `xyz` trio). A colour outside the sRGB gamut clips per channel, which is
  what Chrome was measured doing;
* the **42 system colours** (`Canvas`, `AccentColor`, the deprecated
  aliases…), frozen at the values Chrome resolves on macOS in light mode —
  the one place "the same as the browser" cannot be promised across
  machines, because system colours vary by OS and theme by design.

Keywords are ASCII case-insensitive and tolerate surrounding whitespace, as CSS
defines them.

## Something outside that grammar

The rasterizer answers as a browser answers an invalid declaration — the shape
is not painted, and a gradient stop falls back to black — but the widget rejects
the palette first and names the argument, so a typo fails loudly instead of as a
missing shape.

Three things are measured drawn by a browser and deliberately not read here:
`none` components, relative colour syntax, and `calc()`. That is recorded scope
rather than accident, and it is pinned by the test suite.

## Where the table came from

The name table is **generated from the CSS Color 4 specification**, not typed
out, and every one of the 148 was cross-checked against a real Chrome render —
a mistyped entry would be wrong only for the palette that names it, which no
test could catch.

## A palette colour may be translucent

`#RRGGBBAA`, `rgba(…)`, `hsla(…)` and `transparent` all carry their own alpha,
and it multiplies the shape's coverage — what a browser does with the same
document. Measured against Chrome on a stacked variant, every interior pixel
agrees to within 1/255.

## An empty palette is not always an error

Upstream degrades rather than validating, and it degrades *differently* per
variant. This package reproduces that instead of smoothing it over: with
`colors: []`, five variants render an avatar with colours missing, and `beam`
throws an `ArgumentError` — because upstream throws there too, and a `beam` that
degraded would be an image upstream has never produced.
