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
  /// Channels are accumulated in floating point and rounded once, on write.
  /// Rounding per blend would drift wherever shapes overlap — `pixel`'s tiles
  /// never do, but marble, bauhaus and beam stack two to four.
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

/// Parses the `#RRGGBB` form upstream's default palette uses.
///
/// Returns `null` for anything else, **including forms a browser would
/// accept** — `#F00`, `red`, `rgb(…)`, `#RRGGBBAA`. The palette is consumer
/// policy and upstream validates none of it, so those reach here; the SVG
/// backend passes them through intact while this one cannot draw them. That
/// divergence is recorded rather than papered over: see hidden-state #20.
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

/// An axis-aligned rectangle to fill.
class RasterRect {
  const RasterRect(this.x, this.y, this.width, this.height, this.fill);
  final double x;
  final double y;
  final double width;
  final double height;

  /// `null` where upstream omitted the attribute — the tile stays transparent.
  final String? fill;
}

/// Rasterises axis-aligned rectangles through a mask.
///
/// This is all `pixel` needs; curves, strokes and filters arrive with the
/// variants that use them. Coverage for a rectangle is computed exactly rather
/// than sampled — the overlap of two axis-aligned boxes is a product of two
/// interval overlaps, so there is nothing to approximate.
RasterImage rasterizeMaskedRects({
  required int width,
  required int height,
  required List<RasterRect> rects,
  required RoundedRectMask mask,
}) {
  final image = RasterImage(width, height);

  // The mask is the same for every rect, so it is computed once.
  final maskCoverage = Float64List(width * height);
  for (var py = 0; py < height; py++) {
    for (var px = 0; px < width; px++) {
      maskCoverage[py * width + px] = mask.coverageAt(px, py);
    }
  }

  for (final rect in rects) {
    final colour = parseHexColour(rect.fill);
    if (colour == null) continue; // no fill attribute — nothing is drawn

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
        final coverage =
            rowOverlap * colOverlap * maskCoverage[py * width + px];
        image.blend(px, py, colour, coverage);
      }
    }
  }

  return image;
}

/// Length of the intersection of [a0, a1] and [b0, b1].
double _overlap(double a0, double a1, double b0, double b1) {
  final lo = a0 > b0 ? a0 : b0;
  final hi = a1 < b1 ? a1 : b1;
  return hi > lo ? hi - lo : 0;
}
