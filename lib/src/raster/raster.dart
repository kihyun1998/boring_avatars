/// The deterministic software rasterizer.
///
/// It writes straight into a `Uint8List` and never touches `Canvas`. That is
/// the whole reason it exists: delegating to Flutter's canvas would make the
/// output depend on Skia-vs-Impeller, the GPU, the platform and the Flutter
/// version, and the package could then make no claim about its own bytes.
///
/// Everything here is integer or double arithmetic with no platform surface,
/// so the same scene produces the same bytes everywhere.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// An RGBA buffer, four bytes a pixel, row-major, **straight (not
/// premultiplied) alpha**.
///
/// Straight is the deliberate choice, and it is the calibration that decides
/// it: a browser hands back straight bytes from `getImageData` and from a PNG,
/// so a premultiplied buffer would differ from Chrome on **every** antialiased
/// pixel — by far more than the one level the bar allows — for a reason that
/// has nothing to do with coverage accuracy. Premultiplying is one multiply at
/// the Flutter hand-off; un-premultiplying a rounded byte is lossy.
class RasterImage {
  RasterImage(this.width, this.height) : bytes = Uint8List(width * height * 4);

  final int width;
  final int height;
  final Uint8List bytes;

  /// Composites [colour] at (x, y) with [coverage] as its alpha, source-over.
  ///
  /// Within one call the channels are accumulated in floating point and
  /// rounded once. **Across calls they are not** — each blend reads back the
  /// byte the last one wrote, so `k` shapes stacked in a pixel round `k`
  /// times. That is deliberate rather than tolerated: a browser draws each
  /// shape of a plain display list straight onto an 8-bit surface and rounds
  /// exactly as often, so accumulating in float across shapes would move us
  /// *away* from the reference.
  ///
  /// Measured over 1.2M random stacks of 2–9 opaque shapes, the worst drift
  /// against a single float accumulation is **2/255 premultiplied** — and
  /// straight, at very low alpha, it reaches 16, which is hidden-state #29
  /// rather than a real difference.
  ///
  /// Valid **as long as every shape composites directly onto the destination**.
  /// A group opacity or a filter introduces an offscreen layer with its own
  /// rounding; `marble` has one, and the scene seam throws on it today.
  void blend(int x, int y, RasterColour colour, double coverage) {
    if (coverage <= 0) return;
    final i = (y * width + x) * 4;
    final sa = coverage.clamp(0.0, 1.0);
    final da = bytes[i + 3] / 255;

    final outA = sa + da * (1 - sa);
    if (outA <= 0) return;

    // Source-over on straight alpha: the destination contributes in proportion
    // to what the source does not cover, and the result is divided back out.
    double channel(int offset, int src) =>
        (src * sa + bytes[i + offset] * da * (1 - sa)) / outA;

    bytes[i] = channel(0, colour.r).round().clamp(0, 255);
    bytes[i + 1] = channel(1, colour.g).round().clamp(0, 255);
    bytes[i + 2] = channel(2, colour.b).round().clamp(0, 255);
    bytes[i + 3] = (outA * 255).round().clamp(0, 255);
  }
}

/// A straight RGB triple.
class RasterColour {
  const RasterColour(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
}

/// What a colour-valued attribute declared, before any call site decides what
/// to do about it.
///
/// Four states, and three of them paint nothing today — so a picture cannot
/// tell them apart and neither could the code, until this existed. Splitting
/// them changes no output; it makes the *reason* inspectable, which is what
/// lets `fill` and `stop-color` answer the same declaration differently on
/// purpose rather than by accident.
///
/// The split matters because the two properties really do have different
/// grammars. `fill` and `stroke` take `<paint>`, whose first alternative is
/// `none` — "Indicates that no paint is applied" (SVG 1.1, 11.2). `stop-color`
/// takes `currentColor | <color> <icccolor> | inherit` (13.2.4), which does
/// **not** include `none`. A vocabulary that folded `none` into "unreadable"
/// would make `beam`'s 204 `none` declarations right by coincidence, and a
/// golden would freeze the coincidence.
sealed class ColourDeclaration {
  const ColourDeclaration();
}

/// The attribute was not written at all.
///
/// Upstream's own idiom for "no paint" — it omits `fill` rather than writing
/// `none` when a palette entry is `undefined` (#17), which is why 100% of
/// `pixel` renders lead with an unfilled tile. What each property makes of an
/// absence is its own initial value's business: `fill` is black, `stroke` is
/// `none`, `stop-color` is black.
final class AbsentColour extends ColourDeclaration {
  const AbsentColour();
}

/// The attribute said `none`.
///
/// A value that was read, not one that failed to parse. In `<paint>` it means
/// no paint is applied; in `stop-color` it is outside the grammar entirely.
final class NoneColour extends ColourDeclaration {
  const NoneColour();
}

/// A colour this rasterizer read.
final class ParsedColour extends ColourDeclaration {
  const ParsedColour(this.colour);
  final RasterColour colour;
}

/// A value in a notation this rasterizer has not learned.
///
/// `red`, `#F00`, `rgb(…)`, `#RRGGBBAA` — all of which a browser draws. The
/// palette is consumer policy and upstream validates none of it, so these
/// reach here and the SVG backend passes them through intact while this one
/// cannot draw them (hidden-state #20). [text] is kept so the seam can say
/// what it could not read.
final class UnreadableColour extends ColourDeclaration {
  const UnreadableColour(this.text);
  final String text;
}

/// Reads [declared] into one of the four [ColourDeclaration] states.
///
/// This is the *reading*; the answer is the call site's. `fill` and
/// `stop-color` share this and diverge afterwards, which is the only way the
/// divergence can be argued about.
///
/// The keyword is matched exactly. CSS keywords are ASCII case-insensitive and
/// tolerate surrounding whitespace, so `NONE` and ` none ` are `none` to a
/// browser and are `unreadable` here — which costs nothing today, since both
/// answers are "draw nothing" and upstream writes exactly `none`, lower case
/// and unpadded, everywhere it writes it: 204 times on a drawn element (all of
/// them `beam`'s) and once on the root `<svg>` of every render. Valid **as long
/// as the only writer of these scenes is this package's own emitter**. #63 has
/// to settle case folding for 148 named colours and is where a loose match
/// belongs if one is ever wanted.
///
/// The enumeration behind that is closed rather than sampled. Across every
/// rendered section of the fixture, `fill`, `stroke` and `stop-color` take
/// exactly four shapes and no fifth: absent (1880 elements), `none`,
/// `url(#…)` — on a `fill` only — and an upper-case six-digit `#RRGGBB`.
ColourDeclaration readColourDeclaration(String? declared) {
  if (declared == null) return const AbsentColour();
  if (declared == 'none') return const NoneColour();
  final colour = parseHexColour(declared);
  return colour == null ? UnreadableColour(declared) : ParsedColour(colour);
}

/// Parses the `#RRGGBB` form upstream's default palette uses.
///
/// Returns `null` for anything else, **including forms a browser would
/// accept** — `#F00`, `red`, `rgb(…)`, `#RRGGBBAA`. The palette is consumer
/// policy and upstream validates none of it, so those reach here; the SVG
/// backend passes them through intact while this one cannot draw them. That
/// divergence is recorded rather than papered over: see hidden-state #20.
///
/// It is a **hex parser**, not the vocabulary: `none` fails here the way `red`
/// does, four characters that are not six. Anything deciding what a
/// declaration *means* goes through [readColourDeclaration], which reads the
/// keyword before it reaches this.
///
/// A sign is rejected. `int.tryParse('+12345', radix: 16)` succeeds, which
/// would turn punctuation into a plausible colour.
RasterColour? parseHexColour(String? hex) {
  if (hex == null) return null;
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length != 6) return null;
  for (final unit in h.codeUnits) {
    final isHex =
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x46) ||
        (unit >= 0x61 && unit <= 0x66);
    if (!isHex) return null;
  }
  final v = int.parse(h, radix: 16);
  return RasterColour((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

/// Per-pixel coverage of a rounded rectangle, in the range 0–1.
///
/// Coverage is **exact in x and integrated in y**: for each of [_slices]
/// horizontal strips through the pixel, the shape's left and right edges are
/// solved in closed form and the covered width taken directly. Only the
/// vertical direction is discretised, so the error falls as 1/slices² instead
/// of the 1/samples a 2-D grid gives.
///
/// That matters because the calibration bar is one level out of 255. A 16×16
/// grid measured **4/255** against a 512× reference — it could not have met the
/// bar, and theflow forbids moving a threshold to clear a red run.
class RoundedRectMask {
  RoundedRectMask({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required double rx,
  }) : // SVG clamps a corner radius to half the side. `pixel` asks for 160 on
       // an 80-wide rect, which is how upstream turns a rect into a circle.
       //
       // SVG 1.1 clamps rx and ry *independently*, giving elliptical corners on
       // a non-square rect. Every mask in the six variants is square, so one
       // radius suffices — recorded with its condition in hidden-state #21.
       //
       // **This is now the second §9.2 implementation in the package and the
       // two deliberately differ.** `roundedRectContour` in `path.dart` clamps
       // the two radii separately, because `beam`'s eye is 1.5 × 2 and needs
       // the ellipse; this one takes a single `min` because a *mask* is square
       // in all six and a shared elliptical path would cost the closed-form
       // coverage that keeps the mask exact in x. The divergence is safe only
       // while that stays true — **a non-square mask would silently take the
       // joint clamp and draw circular corners where SVG says elliptical.**
       // The day one appears, this class is what has to move.
       radius = math.min(rx, math.min(width / 2, height / 2));

  final double x;
  final double y;
  final double width;
  final double height;

  /// The radius after SVG's clamp.
  final double radius;

  static const int _slices = 64;

  /// Half-width of the shape at height [py], measured from the vertical centre.
  ///
  /// Returns `null` when the row lies outside the shape entirely.
  double? _halfWidthAt(double py) {
    if (py < y || py > y + height) return null;
    final top = y + radius;
    final bottom = y + height - radius;
    if (py >= top && py <= bottom) return width / 2; // the straight-sided band

    final dy = py < top ? top - py : py - bottom;
    if (dy > radius) return null;
    final inset = radius - math.sqrt(radius * radius - dy * dy);
    return width / 2 - inset;
  }

  /// Coverage of the pixel whose top-left corner is (px, py).
  double coverageAt(int px, int py) {
    final cx = x + width / 2;
    var area = 0.0;
    for (var s = 0; s < _slices; s++) {
      final sy = py + (s + 0.5) / _slices;
      final half = _halfWidthAt(sy);
      if (half == null) continue;
      final left = math.max(px.toDouble(), cx - half);
      final right = math.min(px + 1.0, cx + half);
      if (right > left) area += right - left;
    }
    return area / _slices;
  }
}

/// Thrown when a scene needs a capability this rasterizer does not have yet.
///
/// The alternative is worse than a crash. An unhandled `<path>` renders as
/// blank and an ignored `transform` puts a rect somewhere plausible but wrong —
/// both are *pictures*, and a golden would freeze either one as correct. This
/// is the seam that stops the next variant from shipping a silently wrong
/// image, so every unimplemented capability throws rather than degrading.
class UnsupportedSceneError extends Error {
  UnsupportedSceneError(this.message);
  final String message;

  @override
  String toString() => 'UnsupportedSceneError: $message';
}

/// One closed contour, as a flat `[x0, y0, x1, y1, …]` list.
///
/// The closing edge back to the first point is implied, so a triangle is three
/// points and not four. Curves reach this form through
/// `path.dart`'s flattener, which states its own tolerance.
class PathContour {
  const PathContour(this.points);

  /// Alternating x and y, so `points.length` is always even.
  final List<double> points;

  int get length => points.length ~/ 2;
  double x(int i) => points[i * 2];
  double y(int i) => points[i * 2 + 1];
}

/// What a shape is painted with.
///
/// A `fill` is not always a colour: `sunset` paints both its halves with
/// gradients declared in a `<defs>`, so the paint varies across the shape and
/// has to be asked per pixel rather than resolved once.
sealed class RasterPaint {
  const RasterPaint();

  /// The colour at the centre of the pixel whose top-left corner is (px, py).
  RasterColour colourAt(int px, int py);
}

/// One colour everywhere.
class SolidPaint extends RasterPaint {
  const SolidPaint(this.colour);

  /// `#RRGGBB` only, and `null` for anything else — see [parseHexColour].
  ///
  /// A shorthand for building a paint from a literal, which is what the tests
  /// do. It is **not** the route a scene's `fill` takes: that goes through
  /// [readColourDeclaration], which tells `none` apart from a notation this
  /// rasterizer cannot read, where this one folds both into `null`.
  static SolidPaint? hex(String? value) {
    final colour = parseHexColour(value);
    return colour == null ? null : SolidPaint(colour);
  }

  final RasterColour colour;

  @override
  RasterColour colourAt(int px, int py) => colour;
}

/// A linear gradient in user space, interpolated component-wise in sRGB.
///
/// **sRGB, not linear light.** SVG's `color-interpolation` defaults to `sRGB`,
/// so the channels are mixed as stored. **Sampled at the pixel centre** and
/// rounded to nearest — measured against Chrome, whose own gradient dithers
/// within 0.987 of the exact value, so an exact interpolation lands within one
/// level of it everywhere.
class LinearGradientPaint extends RasterPaint {
  const LinearGradientPaint({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.stops,
  });

  final double x1, y1, x2, y2;

  /// `(offset, colour)`, in the order declared. Upstream writes two.
  final List<(double, RasterColour)> stops;

  @override
  RasterColour colourAt(int px, int py) {
    if (stops.isEmpty) return const RasterColour(0, 0, 0);
    final dx = x2 - x1, dy = y2 - y1;
    final lengthSquared = dx * dx + dy * dy;
    // A zero-length axis paints the last stop everywhere, per SVG 1.1.
    if (lengthSquared == 0) return stops.last.$2;

    final t = (((px + 0.5) - x1) * dx + ((py + 0.5) - y1) * dy) / lengthSquared;
    return _sample(t);
  }

  /// The colour at gradient coordinate [t], with `spreadMethod="pad"` — the
  /// default, and what upstream relies on since its stops span exactly 0 to 1.
  RasterColour _sample(double t) {
    // `spreadMethod="pad"` — the default, and what upstream relies on — needs
    // no branch of its own. Below the first stop the interpolation factor goes
    // negative and `mix`'s clamp returns that stop's colour; above the last,
    // the loop runs out and the final `return` does the same. Two explicit
    // clamps used to sit here and **no mutation could kill them**, because they
    // never changed an answer.
    for (var i = 1; i < stops.length; i++) {
      final (offset, colour) = stops[i];
      if (t > offset) continue;
      final (previousOffset, previousColour) = stops[i - 1];
      final span = offset - previousOffset;
      final f = span == 0 ? 1.0 : (t - previousOffset) / span;
      int mix(int a, int b) => (a + (b - a) * f).round().clamp(0, 255);
      return RasterColour(
        mix(previousColour.r, colour.r),
        mix(previousColour.g, colour.g),
        mix(previousColour.b, colour.b),
      );
    }
    return stops.last.$2;
  }
}

/// Something to fill, and what to fill it with.
sealed class RasterShape {
  const RasterShape();

  /// `null` where upstream omitted the attribute — nothing is drawn.
  RasterPaint? get fill;
}

/// An axis-aligned rectangle.
///
/// Kept as its own case rather than folded into [RasterPolygon] because its
/// coverage is available in **closed form**: the overlap of two axis-aligned
/// boxes is a product of two interval overlaps, with nothing to approximate. A
/// polygon integrator has to quantise the vertical direction, and a horizontal
/// edge is exactly where that quantisation is worst.
class RasterRect extends RasterShape {
  const RasterRect(this.x, this.y, this.width, this.height, this.fill);
  final double x;
  final double y;
  final double width;
  final double height;

  @override
  final RasterPaint? fill;
}

/// A filled path, as one or more closed contours under the **nonzero** winding
/// rule — SVG's default, which none of the six variants overrides.
class RasterPolygon extends RasterShape {
  const RasterPolygon(this.contours, this.fill);
  final List<PathContour> contours;

  @override
  final RasterPaint? fill;
}

/// Rasterises [shapes] through [mask], in the order given.
///
/// Compositing is per shape, source-over, exactly as a browser draws a display
/// list — which matters for `ring`, where nine shapes stack and the smaller
/// discs are painted over the larger ones.
///
/// **The mask is applied once, to the finished group — not to each shape.**
/// SVG composites a `<g mask="…">`'s children first and multiplies the result's
/// alpha by the mask afterwards, and the difference is not subtle: two opaque
/// shapes stacked on a pixel a mask half-covers must come out at alpha 128,
/// exactly as one of them would. Folding the mask into every shape's coverage
/// gives **192** instead, because the mask is then applied twice. Inert for
/// `pixel` and `ring`, whose mask-edge pixels are reached by at most one shape;
/// live for `marble`, `bauhaus` and `beam`, which each lay a background rect
/// under a second shape that crosses the mask edge.
RasterImage rasterizeMaskedShapes({
  required int width,
  required int height,
  required List<RasterShape> shapes,
  required RoundedRectMask mask,
}) {
  final image = RasterImage(width, height);

  for (final shape in shapes) {
    final paint = shape.fill;
    if (paint == null) continue; // no fill attribute — nothing is drawn

    switch (shape) {
      case RasterRect():
        _fillRect(image, shape, paint);
      case RasterPolygon():
        _fillPolygon(image, shape, paint);
    }
  }

  // Straight alpha makes this a single multiply: masking scales how much of
  // the group shows through and leaves its colour alone.
  //
  // It rounds a second time, and that is faithful rather than sloppy — a
  // browser renders a masked group into an offscreen 8-bit layer and then
  // multiplies by the mask, so it rounds in the same two places.
  for (var py = 0; py < height; py++) {
    for (var px = 0; px < width; px++) {
      final i = (py * width + px) * 4;
      if (image.bytes[i + 3] == 0) continue;
      final alpha = (image.bytes[i + 3] * mask.coverageAt(px, py))
          .round()
          .clamp(0, 255);
      if (alpha == 0) {
        // Straight alpha leaves a fully transparent pixel's colour undefined.
        // Chrome writes zero, and a byte-compared golden needs one answer, so
        // the whole pixel is cleared rather than left carrying a colour
        // nothing can see.
        image.bytes[i] = 0;
        image.bytes[i + 1] = 0;
        image.bytes[i + 2] = 0;
      }
      image.bytes[i + 3] = alpha;
    }
  }

  return image;
}

void _fillRect(RasterImage image, RasterRect rect, RasterPaint paint) {
  final width = image.width;
  final height = image.height;
  final x0 = rect.x.floor().clamp(0, width);
  final x1 = (rect.x + rect.width).ceil().clamp(0, width);
  final y0 = rect.y.floor().clamp(0, height);
  final y1 = (rect.y + rect.height).ceil().clamp(0, height);

  for (var py = y0; py < y1; py++) {
    final rowOverlap = _overlap(
      py.toDouble(),
      py + 1.0,
      rect.y,
      rect.y + rect.height,
    );
    if (rowOverlap <= 0) continue;
    for (var px = x0; px < x1; px++) {
      final colOverlap = _overlap(
        px.toDouble(),
        px + 1.0,
        rect.x,
        rect.x + rect.width,
      );
      if (colOverlap <= 0) continue;
      image.blend(px, py, paint.colourAt(px, py), rowOverlap * colOverlap);
    }
  }
}

/// How many horizontal slices a pixel row is integrated over.
///
/// Coverage is **exact in x and quantised in y**: each slice's covered spans
/// are clipped to pixel columns in closed form, so the only error is which side
/// of a slice centre a horizontal edge falls on. That bounds the error at
/// `1/(2·slices)` — 1/512 of a level, or about 0.5/255 — and only for an edge
/// that is *exactly* horizontal inside a row. For a curve the integrand is
/// continuous and the error is orders of magnitude smaller.
///
/// A `<rect>` *element* does not come through here — [RasterRect] integrates it
/// in closed form. A rectangle written as *path data* does, and `ring` has two
/// of them (`M0 0h90v45H0z`). Theirs are still exact, because 0, 45 and 90 are
/// integers and no slice centre can straddle an edge that lands on a pixel
/// boundary; a fractional one would take the 0.5-level worst case above.
const int _slicesPerRow = 256;

void _fillPolygon(RasterImage image, RasterPolygon polygon, RasterPaint paint) {
  final coverage = polygonCoverage(
    width: image.width,
    height: image.height,
    polygon: polygon,
  );
  for (var i = 0; i < coverage.length; i++) {
    if (coverage[i] <= 0) continue;
    final px = i % image.width, py = i ~/ image.width;
    image.blend(px, py, paint.colourAt(px, py), coverage[i]);
  }
}

/// Per-pixel coverage of [polygon], in the range 0–1.
///
/// Exposed because it is the only place a *number* can be checked against one
/// that is known independently: the area of a disc is πr², and summing this
/// grid over a flattened circle has to reproduce it. Reading coverage out of
/// the rendered bytes cannot — they are rounded to 1/255 a pixel, which is
/// coarser than the flattening error the sum is meant to measure.
Float64List polygonCoverage({
  required int width,
  required int height,
  required RasterPolygon polygon,
}) {
  final out = Float64List(width * height);
  final row = Float64List(width);

  final edges = <_Edge>[];
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final contour in polygon.contours) {
    final n = contour.length;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final ax = contour.x(i), ay = contour.y(i);
      final bx = contour.x(j), by = contour.y(j);
      if (ay == by) continue; // horizontal edges cross no scanline
      edges.add(_Edge(ax, ay, bx, by));
      minY = math.min(minY, math.min(ay, by));
      maxY = math.max(maxY, math.max(ay, by));
    }
  }
  if (edges.isEmpty) return out;

  edges.sort((a, b) => a.top.compareTo(b.top));

  final firstRow = math.max(0, minY.floor());
  final lastRow = math.min(height - 1, maxY.ceil());

  final active = <_Edge>[];
  var next = 0;
  // Skip edges that end above the first row we will visit.
  while (next < edges.length && edges[next].top < firstRow) {
    if (edges[next].bottom > firstRow) active.add(edges[next]);
    next++;
  }

  final crossings = <_Crossing>[];
  for (var py = firstRow; py <= lastRow; py++) {
    while (next < edges.length && edges[next].top < py + 1) {
      active.add(edges[next]);
      next++;
    }
    active.removeWhere((e) => e.bottom <= py);
    if (active.isEmpty) continue;

    row.fillRange(0, width, 0);
    for (var s = 0; s < _slicesPerRow; s++) {
      final y = py + (s + 0.5) / _slicesPerRow;
      crossings.clear();
      for (final edge in active) {
        if (y < edge.top || y >= edge.bottom) continue;
        crossings.add(_Crossing(edge.xAt(y), edge.winding));
      }
      if (crossings.length < 2) continue;
      crossings.sort((a, b) => a.x.compareTo(b.x));

      var winding = 0;
      for (var i = 0; i < crossings.length - 1; i++) {
        winding += crossings[i].winding;
        if (winding == 0) continue; // nonzero rule
        _addSpan(row, crossings[i].x, crossings[i + 1].x, width);
      }
    }

    for (var px = 0; px < width; px++) {
      if (row[px] > 0) out[py * width + px] = row[px] / _slicesPerRow;
    }
  }

  return out;
}

/// Adds the covered length of `[xa, xb)` to each pixel column it touches.
void _addSpan(Float64List row, double xa, double xb, int width) {
  final a = xa < 0 ? 0.0 : (xa > width ? width.toDouble() : xa);
  final b = xb < 0 ? 0.0 : (xb > width ? width.toDouble() : xb);
  if (b <= a) return;
  final first = a.floor();
  final last = math.min(width - 1, (b.ceil() - 1));
  for (var i = first; i <= last; i++) {
    final lo = a > i ? a : i.toDouble();
    final hi = b < i + 1 ? b : i + 1.0;
    if (hi > lo) row[i] += hi - lo;
  }
}

/// A non-horizontal polygon edge, normalised to run downwards.
class _Edge {
  _Edge(double ax, double ay, double bx, double by)
    : top = ay < by ? ay : by,
      bottom = ay < by ? by : ay,
      xTop = ay < by ? ax : bx,
      slope = (bx - ax) / (by - ay),
      winding = ay < by ? 1 : -1;

  final double top;
  final double bottom;
  final double xTop;

  /// dx/dy, which is finite because horizontal edges never become an [_Edge].
  final double slope;

  /// +1 where the contour runs downwards, −1 upwards — the nonzero rule's sign.
  final int winding;

  double xAt(double y) => xTop + (y - top) * slope;
}

class _Crossing {
  const _Crossing(this.x, this.winding);
  final double x;
  final int winding;
}

/// Length of the intersection of [a0, a1] and [b0, b1].
double _overlap(double a0, double a1, double b0, double b1) {
  final lo = a0 > b0 ? a0 : b0;
  final hi = a1 < b1 ? a1 : b1;
  return hi > lo ? hi - lo : 0;
}
