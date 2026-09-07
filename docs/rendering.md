# How the widget puts pixels on screen

`BoringAvatar` draws through this package's own rasterizer, at the display's
physical pixel size. **It does not use `flutter_svg`, and it does not draw on a
`Canvas`.** Measured: `flutter_svg` does not clamp `rx` the way SVG 1.1 §9.4
requires, so the circular mask every variant relies on comes out square, and it
has no `<filter>` at all, so `marble` loses its blur. A `Canvas` would make the
output depend on Skia-vs-Impeller, GPU, platform and Flutter version — which is
the whole reason this package rasterises in software.

So the determinism guarantee — the same bytes on every platform, GPU, Flutter
version and rendering backend — covers the widget as well as the SVG string.
That guarantee is about the image the widget **produces**: it is rasterised at
the box's physical pixel size, painted onto **whole** device pixels, and handed
over with `FilterQuality.none`, so nothing resamples it. That is the ordinary
case; where an ancestor puts it out of reach, see
[Where one pixel cannot cover one pixel](#where-one-pixel-cannot-cover-one-pixel).

## Whole device pixels

Whole device pixels is the part that has to be arranged rather than assumed. A
45-logical box at 150% display scaling is 67.5 physical pixels, and no buffer is
67.5 pixels wide — so the widget rounds the drawing onto the pixel grid instead
of letting the mismatch reach the sampler. It moves the avatar by at most half a
physical pixel and it is what keeps `FilterQuality.none` honest: before `0.3.1`
a fractional box on a fractional origin cost a whole pixel column, which on a
disc that touches all four edges of its box reads as a flat, shaved edge.

One case is narrowed rather than closed. Where `size × dpr` rounds *up*, the
buffer is a hair wider than the box — 45 logical at 150% is 67.5 physical pixels
holding a 68-pixel buffer — so an ancestor that clips to exactly the box takes
that hair back off. Nothing can place a 68-pixel square inside 67.5. It is
strictly better than before (21 of 105 measured combinations were wrong, now 6,
and the 6 are among the 21), and a clip even a fraction larger than the avatar
avoids it entirely.

The grid it rounds to is the one of **the space the widget paints into**, and
the enclosing layer is left to the engine, which rounds it as it composites.
`0.3.1` did the opposite and corrected against the screen, which double-counted
that fraction; see [Inside a list, a fade or any other layer](#inside-a-list-a-fade-or-any-other-layer)
for the measurement that reversed it.

While a list is actually *scrolling*, though, the alignment goes stale — the
position is computed when the avatar paints, and scrolling moves the layer
without repainting what is inside it. It comes back the moment the row
repaints. This is a Flutter-level limitation rather than one this package can
close (flutter/flutter#111302); Flutter's own text caret snaps to physical
pixels the same way and inherits the same gap.

## Where one pixel cannot cover one pixel

Everything above arranges for one buffer pixel to cover one device pixel, and
`FilterQuality.none` is exact exactly while that holds. Two ordinary situations
put it out of reach, and no placement fixes either: an ancestor that **scales or
rotates**, where this box's grid is not the device's grid at all, and a
**buffer that is not the destination's size** — a parent squeezing the box, or a
display-scale change that leaves the previous buffer up until the new one is
drawn.

There, `FilterQuality.none` is the *worst* available choice rather than the
safest. Nearest neighbour cannot spend a fraction of a pixel, so it drops or
duplicates whole columns — on a smooth `marble` gradient that reads as a fold
straight across the avatar. So the widget draws those with a filter instead:
half a pixel of softness in place of a fold.

This narrows the determinism guarantee's stated scope without spending any of
it. Where the avatar lands one pixel per pixel — the overwhelming majority — the
bytes are exactly what they have always been. Where it does not, the output was
already the backend's: which column nearest neighbour keeps is the sampler's
rounding, so Skia and Impeller were never obliged to agree there either.

Layout that then squeezes the box smaller than the size you asked for is outside
the package, and Flutter's sampler runs there like it would for any image — a
filtered one, now that the drawing is knowingly a scaled copy.

## Inside a list, a fade or any other layer

An ancestor that composites — a scroll viewport, an `Opacity` or
`FadeTransition`, a `RepaintBoundary` — draws the avatar into a layer, and the
engine puts that layer on screen afterwards, **rounding it onto the device grid
as it goes**. So the alignment above is done in the space the widget paints
into and the layer's own fraction is left to the engine; correcting for it here
as well would apply it twice, which is what `0.3.1` did.

Measured on real engines against the same avatar with no ancestor at all, with
the enclosing layer half a device pixel past an integer:

| | `0.3.1` | `0.3.2` |
|---|---|---|
| Windows, 150% | 2921 of 4356 pixels differ, up to 196 levels | **byte-identical** |
| macOS, 200% | 1289 of 7744 differ, up to 136 levels | **byte-identical** |
| web (CanvasKit), 150% | drawing spread over 67 device pixels | 66, its own width — neither lands whole |

An avatar in a `ListView` row, inside a page transition, or in a scrolling panel
is the ordinary case, and it is the case that got quieter. **Web is a
non-regression rather than a fix**: Chrome does not round the enclosing layer —
a plain vector circle in the same frame comes out a device pixel wider at a
fractional origin, and the surface itself is a fractional number of physical
pixels — so nothing there lands whole whatever this package does. iOS and
Android are unmeasured.

## The avatar arrives a beat after the widget does

Drawing happens off the frame — in a background isolate on native, and in
interruptible slices on web, where Flutter has no isolate to offer. **Your app
stays responsive while it draws**, and the box is its final size from the very
first frame, so nothing reflows when the picture lands. But the picture is not
there on frame one. See [performance.md](performance.md) for what it costs.

**If the inputs change, the widget blanks rather than showing the old avatar** —
a new `name`, palette, `variant`, `version` or `square` is a different person's
face, and showing the previous one under the new name would be a small lie. A
change to `size` alone is the *same* avatar at a new resolution, so that one
keeps drawing until the sharper version is ready and never flashes.

**A raster that fails reports through Flutter's error machinery** rather than
disappearing, and the widget clears rather than leaving a stale avatar behind.
