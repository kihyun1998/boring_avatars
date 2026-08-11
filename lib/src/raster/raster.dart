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

import 'named_colours.dart';

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
    // **The colour's alpha and the shape's coverage multiply.** They are
    // independent quantities — one says how transparent the paint is, the other
    // how much of the pixel the shape reaches — and a source-over composite
    // takes their product as its source alpha. Measured against Chrome:
    // `#FF000080` at full coverage over opaque white gives 255,127,127, and at
    // half coverage 255,191,191. Letting coverage *replace* the colour's alpha
    // reproduces the first and not the second.
    final sa = (coverage * colour.a / 255).clamp(0.0, 1.0);
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

  /// Composites a source colour given as 0–1 channels, through [mode].
  ///
  /// The general CSS Compositing and Blending Level 1 formula, which reduces to
  /// [blend]'s source-over when [mode] is `normal`:
  ///
  /// ```
  /// ao = as + ab * (1 - as)
  /// Co = (1 - ab) * as * Cs  +  ab * as * B(Cb, Cs)  +  (1 - as) * ab * Cb
  /// ```
  ///
  /// The middle term is the whole difference: where the backdrop is opaque the
  /// blend function decides the colour, and where it is transparent the source
  /// passes through unchanged. That is why `marble`'s overlay blob looks like a
  /// plain blob against the transparent corners and tints only over the
  /// background rect.
  void blendSource(
    int x,
    int y,
    double r,
    double g,
    double b,
    double sa,
    RasterBlendMode mode,
  ) {
    if (sa <= 0) return;
    final i = (y * width + x) * 4;
    final ab = bytes[i + 3] / 255;
    final as = sa.clamp(0.0, 1.0);
    final outA = as + ab * (1 - as);
    if (outA <= 0) return;

    double channel(int offset, double cs) {
      final cb = bytes[i + offset] / 255;
      final blended = mode.apply(cb, cs);
      final premultiplied =
          (1 - ab) * as * cs + ab * as * blended + (1 - as) * ab * cb;
      return premultiplied / outA * 255;
    }

    bytes[i] = channel(0, r).round().clamp(0, 255);
    bytes[i + 1] = channel(1, g).round().clamp(0, 255);
    bytes[i + 2] = channel(2, b).round().clamp(0, 255);
    bytes[i + 3] = (outA * 255).round().clamp(0, 255);
  }
}

/// A straight RGBA quadruple — **straight**, never premultiplied.
///
/// [a] defaults to opaque, which is not only ergonomics: every colour upstream
/// writes is a six-digit `#RRGGBB` (hidden-state #31 closes that enumeration
/// over the whole fixture), so every colour reaching this class from a real
/// avatar has `a == 255` and the alpha factor added in #62 is exactly 1. That
/// is what makes "no golden can move" structural rather than hopeful.
///
/// Alpha lives on the **colour** and not only on the shape's coverage because
/// `#RRGGBBAA` puts it there. The two are independent and they multiply — see
/// [RasterImage.blend].
class RasterColour {
  const RasterColour(this.r, this.g, this.b, [this.a = 255]);
  final int r;
  final int g;
  final int b;

  /// 0–255, straight. A gradient interpolates this channel like any other —
  /// measured, see [LinearGradientPaint._sample].
  final int a;
}

/// What a colour-valued attribute declared, before any call site decides what
/// to do about it.
///
/// Four states. In a `fill` three of them paint nothing and in a `stop-color`
/// three of them paint black — so within one property a picture cannot tell
/// them apart, and neither could the code, until this existed. The split (#69)
/// is what made "unreadable" nameable, which is what let #64 change that
/// state's answer alone, and it keeps the *reason* inspectable now that the
/// answers coincide again.
///
/// The split matters because the two properties really do have different
/// grammars. `fill` and `stroke` take `<paint>`, whose first alternative is
/// `none` — "Indicates that no paint is applied" (SVG 1.1, 11.2). `stop-color`
/// takes `currentColor | <color> <icccolor> | inherit` (13.2.4), which does
/// **not** include `none` — there it is an invalid value, ignored, and the
/// slot takes the initial black (ADR-0001 R2). A vocabulary that folded
/// `none` into "unreadable" would make `beam`'s 204 `none` declarations right
/// by coincidence; since #64 the coincidence extends to every call site, so
/// only the type-level tests hold the two apart — deliberately, because the
/// day a property answers them differently again is the day the collapse
/// would ship a wrong picture.
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

/// A value outside every colour grammar this rasterizer knows.
///
/// `zzz`, `rgb(255,0)`, the empty string — the grammars #62/#63 implemented
/// reject these, and as of #64 every call site answers them the way a browser
/// answers an ignored declaration (ADR-0001 R2) instead of refusing. The
/// palette is consumer policy and upstream validates none of it, so they
/// reach here (hidden-state #20).
///
/// **"Lands here" is not the same as "invalid", and the gap is known.** CSS
/// Color 4 notations this parser has not learned — `hwb()`, `lab()`/`lch()`,
/// `oklab()`/`oklch()`, `color()`, the system colours — file here too, and a
/// browser draws them (measured: `hwb(120 0% 0%)` is 0,255,0 in Chrome, in a
/// `stop-color` as well). For those the #64 answer is wrong in the same
/// direction the pre-#62 blank was; the widget's palette guard is what keeps
/// them off the public surface. Surfaced in #64's completeness pass and ruled
/// by the user: **learn them — #95**, after which this paragraph comes out.
/// [text] is kept so a seam that still refuses — that guard — can say what it
/// could not read.
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
/// **The keyword is matched loosely as of #63, and that was measured before it
/// was changed.** CSS keywords are ASCII case-insensitive and tolerate
/// surrounding whitespace; this row previously matched `none` exactly and
/// recorded the looseness as a validity condition, naming #63 as the place a
/// loose match belongs "if one is ever wanted". It is: rendered in Chrome,
/// `NONE`, `None` and ` none ` all paint nothing, exactly as `none` does — so
/// the strict match was a divergence waiting for a caller to write one.
///
/// It costs nothing to have been strict until now, because upstream writes
/// exactly `none`, lower case and unpadded, everywhere it writes it: 204 times
/// on a drawn element (all of them `beam`'s) and once on the root `<svg>` of
/// every render.
///
/// The enumeration behind that is closed rather than sampled. Across every
/// rendered section of the fixture, `fill`, `stroke` and `stop-color` take
/// exactly four shapes and no fifth: absent (1880 elements), `none`,
/// `url(#…)` — on a `fill` only — and an upper-case six-digit `#RRGGBB`.
ColourDeclaration readColourDeclaration(String? declared) {
  if (declared == null) return const AbsentColour();
  if (_cssNormalise(declared) == 'none') return const NoneColour();
  final colour = parseCssColour(declared);
  return colour == null ? UnreadableColour(declared) : ParsedColour(colour);
}

/// Parses every hex notation CSS Color 4 §5.2 defines: `#RGB`, `#RGBA`,
/// `#RRGGBB`, `#RRGGBBAA`, in either case.
///
/// **Four lengths, not one, because the grammar says four** — ADR-0001's R1:
/// what is a valid `<color>` is decided by the property's grammar and not by
/// what this parser happens to read. Until #62 only the six-digit form was
/// read, so `#F00` fell into "unreadable" beside `red` and `zzz`; a browser
/// draws it, which made the rasterizer's blank the divergence hidden-state #20
/// described as intended and #62 measured was not.
///
/// The short forms **double each digit**, alpha included — `#F008` is
/// `#FF000088`, alpha 136 and not 128. Measured in Chrome; a parser that
/// doubled the colour digits and left the alpha alone would be 8/255 out on
/// that one value and exact everywhere else.
///
/// Returns `null` for anything the grammar does not admit, and what that
/// draws is the call sites' answer, not this function's — #64 ruled it
/// (nothing in a `fill`, black in a `stop-color`), and a length of five or
/// seven staying `null` here is what keeps "invalid" meaning something. A
/// sign is rejected for the same reason it always was:
/// `int.tryParse('+12345', radix: 16)` succeeds and would turn punctuation into
/// a plausible colour.
///
/// It is a **hex parser**, not the vocabulary: `none` fails here the way `red`
/// does. Anything deciding what a declaration *means* goes through
/// [readColourDeclaration], which reads the keyword before it reaches this.
RasterColour? parseHexColour(String? hex) {
  if (hex == null) return null;
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length != 3 && h.length != 4 && h.length != 6 && h.length != 8) {
    return null;
  }
  for (final unit in h.codeUnits) {
    final isHex =
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x46) ||
        (unit >= 0x61 && unit <= 0x66);
    if (!isHex) return null;
  }
  // The short forms are expanded rather than parsed separately, so there is one
  // arithmetic path and the doubling is visible instead of implied.
  final long = h.length <= 4 ? h.split('').map((d) => '$d$d').join() : h;
  final v = int.parse(long, radix: 16);
  if (long.length == 6) {
    return RasterColour((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
  }
  return RasterColour(
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  );
}

/// CSS whitespace — the five ASCII characters, and **not** Dart's `trim()`.
///
/// `trim()` also removes U+00A0 and the Unicode space separators, which CSS
/// does not: trimming them would make this parser *accept* strings a browser
/// rejects, which is the direction that produces a picture the reference does
/// not. Erring the other way only produces a refusal.
bool _isCssSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0C ||
    unit == 0x0D;

/// Trimmed and lower-cased **in ASCII only**, which is what CSS means by
/// case-insensitive.
///
/// `String.toLowerCase` is Unicode-aware, and that is a divergence rather than
/// a bonus: U+212A KELVIN SIGN lower-cases to `k`, so `blac\u{212A}` would
/// match `black` here and match nothing in a browser.
String _cssNormalise(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && _isCssSpace(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isCssSpace(value.codeUnitAt(end - 1))) {
    end--;
  }
  final out = StringBuffer();
  for (var i = start; i < end; i++) {
    final unit = value.codeUnitAt(i);
    out.writeCharCode(unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit);
  }
  return out.toString();
}

/// Every `<color>` this rasterizer reads: hex, the 148 named colours,
/// `transparent`, `currentColor`, and the `rgb()` / `rgba()` / `hsl()` /
/// `hsla()` functions.
///
/// **ADR-0001's R1 in one function.** What is a valid `<color>` is the
/// property's grammar, so this answers the grammar and nothing above it —
/// `none` is a `<paint>` alternative rather than a colour and is read before
/// this, by [readColourDeclaration].
///
/// `currentColor` resolves to **black**, and that is measured rather than
/// assumed: rendered in a document where no ancestor declares `color`, Chrome
/// paints `0,0,0,255`, which is `color`'s initial value arriving through the
/// same inheritance R2 uses. Valid **as long as nothing this package emits
/// declares `color`** — nothing does, and a variant that started to would make
/// this wrong silently, because the rasterizer does not read the root.
RasterColour? parseCssColour(String? value) {
  if (value == null) return null;
  final v = _cssNormalise(value);
  if (v.isEmpty) return null;
  if (v.startsWith('#')) return parseHexColour(v);
  if (v == 'transparent') return const RasterColour(0, 0, 0, 0);
  if (v == 'currentcolor') return const RasterColour(0, 0, 0);
  final named = namedColours[v];
  if (named != null) {
    return RasterColour(
      (named >> 16) & 0xFF,
      (named >> 8) & 0xFF,
      named & 0xFF,
    );
  }
  return _parseColourFunction(v);
}

/// A finite double, or `null`. `double.tryParse` accepts `Infinity` and `NaN`,
/// which would survive every clamp below and reach the buffer as a byte nobody
/// chose.
double? _cssNumber(String s) {
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  return n == null || !n.isFinite ? null : n;
}

/// `rgb()`, `rgba()`, `hsl()`, `hsla()` — measured, not read from a summary.
///
/// The grammar this accepts is exactly what Chrome accepted in #63's probe:
/// either separator (`a, b, c` or `a b c`, the latter taking its alpha after a
/// `/`), either value form for `rgb` (all three percentages or all three
/// numbers, **never mixed** — `rgb(100%,0,0)` is invalid there), percentages
/// required for `hsl`'s saturation and lightness (`hsl(0,100,50)` is invalid),
/// alpha as a number or a percentage, and every value clamped rather than
/// refused (`rgb(300,-20,0)` is `255,0,0`; an alpha of `-1` is 0 and `150%` is
/// 1).
RasterColour? _parseColourFunction(String v) {
  final open = v.indexOf('(');
  if (open < 0 || !v.endsWith(')')) return null;
  final name = v.substring(0, open);
  final isRgb = name == 'rgb' || name == 'rgba';
  if (!isRgb && name != 'hsl' && name != 'hsla') return null;

  var body = v.substring(open + 1, v.length - 1);
  List<String> parts;
  if (body.contains(',')) {
    // The legacy comma form has no `/` alternative; accepting both would take
    // a string Chrome refuses.
    if (body.contains('/')) return null;
    parts = body.split(',').map(_cssNormalise).toList();
  } else {
    var alpha = '';
    final slash = body.indexOf('/');
    if (slash >= 0) {
      alpha = _cssNormalise(body.substring(slash + 1));
      body = body.substring(0, slash);
      if (alpha.isEmpty) return null;
    }
    parts = [
      for (final p in body.split(RegExp(r'[ \t\n\f\r]+')))
        if (p.isNotEmpty) p,
      if (alpha.isNotEmpty) alpha,
    ];
  }
  if (parts.length != 3 && parts.length != 4) return null;
  if (parts.any((p) => p.isEmpty)) return null;

  final a = parts.length == 4 ? _cssAlpha(parts[3]) : 255;
  if (a == null) return null;

  if (isRgb) {
    final percent = parts[0].endsWith('%');
    // All three or none: a browser refuses the mixture rather than coercing it.
    if (parts.take(3).any((p) => p.endsWith('%') != percent)) return null;
    final channels = <int>[];
    for (final p in parts.take(3)) {
      final n = _cssNumber(percent ? p.substring(0, p.length - 1) : p);
      if (n == null) return null;
      channels.add((percent ? n * 255 / 100 : n).round().clamp(0, 255));
    }
    return RasterColour(channels[0], channels[1], channels[2], a);
  }

  final h = _cssHue(parts[0]);
  if (h == null) return null;
  if (!parts[1].endsWith('%') || !parts[2].endsWith('%')) return null;
  final s = _cssNumber(parts[1].substring(0, parts[1].length - 1));
  final l = _cssNumber(parts[2].substring(0, parts[2].length - 1));
  if (s == null || l == null) return null;
  return _hslToRgb(h, (s / 100).clamp(0.0, 1.0), (l / 100).clamp(0.0, 1.0), a);
}

/// A hue in degrees, from any of CSS's four angle units.
///
/// **`grad` is tested before `rad` and that ordering is load-bearing** — `grad`
/// ends with `rad`, so the other order reads `200grad` as the number `200g`
/// and refuses a valid colour. All four are measured: `3.14159rad` and
/// `200grad` both render cyan, `0.5turn` likewise, and `1.5708rad` comes out a
/// shade *past* 90° because 1.5708 is larger than π/2 — which is the case that
/// separates a wrong conversion from a rounding difference.
double? _cssHue(String s) {
  for (final (suffix, factor) in const [
    ('deg', 1.0),
    ('grad', 0.9),
    ('rad', 180 / math.pi),
    ('turn', 360.0),
  ]) {
    if (s.endsWith(suffix)) {
      final n = _cssNumber(s.substring(0, s.length - suffix.length));
      return n == null ? null : n * factor;
    }
  }
  return _cssNumber(s);
}

/// 0–255 from a number in 0–1 or a percentage, clamped rather than refused.
int? _cssAlpha(String s) {
  final percent = s.endsWith('%');
  final n = _cssNumber(percent ? s.substring(0, s.length - 1) : s);
  if (n == null) return null;
  return ((percent ? n / 100 : n).clamp(0.0, 1.0) * 255).round();
}

/// CSS Color 4 §7.1's conversion, with the hue wrapped first.
///
/// Negative and out-of-range hues wrap rather than clamp — measured:
/// `hsl(-120…)` is blue and `hsl(480…)` is green, which are 240° and 120°.
/// Dart's `%` is already non-negative for a positive divisor, unlike JS's, so
/// no sign correction is needed here (hidden-state #2 is about the other
/// direction).
RasterColour _hslToRgb(double hue, double s, double l, int a) {
  final h = hue % 360;
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  final (r, g, b) = switch (h) {
    < 60 => (c, x, 0.0),
    < 120 => (x, c, 0.0),
    < 180 => (0.0, c, x),
    < 240 => (0.0, x, c),
    < 300 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  int byte(double channel) => ((channel + m) * 255).round().clamp(0, 255);
  return RasterColour(byte(r), byte(g), byte(b), a);
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

  /// Any hex notation, and `null` for anything else — see [parseHexColour].
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
      // **Alpha is mixed straight, like any other channel — measured, because
      // the two plausible models disagree loudly and nothing upstream can tell
      // them apart.** `#FF000000` → `#0000FFFF` over opaque white gives a
      // midpoint of 191,128,191 in Chrome; interpolating premultiplied would
      // give 127,127,255. Upstream never writes a stop with alpha, so a
      // premultiplied implementation would have left every golden green.
      return RasterColour(
        mix(previousColour.r, colour.r),
        mix(previousColour.g, colour.g),
        mix(previousColour.b, colour.b),
        mix(previousColour.a, colour.a),
      );
    }
    return stops.last.$2;
  }
}

/// How a shape combines with what is already under it.
///
/// SVG's own painting is `normal` — plain source-over. `marble`'s second blob
/// declares `style="mix-blend-mode: overlay"`, which is CSS Compositing and
/// Blending, not SVG: the blend function replaces the source colour with a
/// function of the source *and the backdrop*, and only then composites.
enum RasterBlendMode {
  normal,
  overlay;

  /// The separable blend function `B(Cb, Cs)`, on channels in 0–1.
  ///
  /// CSS Compositing and Blending Level 1 defines overlay as `HardLight` with
  /// its arguments swapped, which expands to this. Verified against Chrome:
  /// `overlay(#808080, #3399CC)` is `(52, 153, 204)` both ways.
  double apply(double backdrop, double source) => switch (this) {
    RasterBlendMode.normal => source,
    RasterBlendMode.overlay =>
      backdrop <= 0.5
          ? 2 * backdrop * source
          : 1 - 2 * (1 - backdrop) * (1 - source),
  };
}

/// Something to fill, and what to fill it with.
///
/// [blurSigma] and [blendMode] are both `marble`'s: it is the only variant of
/// the six that reaches for a `<filter>` or an inline blend mode. A shape
/// carrying either is drawn into its **own layer** rather than straight onto
/// the destination — see [rasterizeMaskedShapes].
sealed class RasterShape {
  const RasterShape({
    this.blurSigma,
    this.blendMode = RasterBlendMode.normal,
    this.filterRegion,
  });

  /// The `feGaussianBlur`'s `stdDeviation` in **device pixels**, or `null` for
  /// an unfiltered shape.
  final double? blurSigma;

  final RasterBlendMode blendMode;

  /// This shape's filter region as a closed quad, in **device** coordinates.
  ///
  /// **Per shape, not per scene, and not axis-aligned.** SVG 1.1 §15.7.2 puts
  /// the region's `x/y/width/height` in the *referencing element's* user space
  /// — the same sentence that governs `stdDeviation` — so the element's own
  /// `transform` moves, scales and **rotates** it. Its image here is therefore
  /// a quadrilateral, which is why this is a contour and not a rectangle.
  ///
  /// It is a contour rather than a predicate so the clip can be **antialiased**
  /// by the same integrator every other shape uses. A binary pixel-centre test
  /// measured 11/255 against Chrome at the boundary where Chrome shades it.
  final PathContour? filterRegion;

  /// Whether this shape needs an offscreen layer at all.
  bool get needsLayer =>
      blurSigma != null || blendMode != RasterBlendMode.normal;

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
  const RasterRect(
    this.x,
    this.y,
    this.width,
    this.height,
    this.fill, {
    super.blurSigma,
    super.blendMode,
    super.filterRegion,
  });
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
  const RasterPolygon(
    this.contours,
    this.fill, {
    super.blurSigma,
    super.blendMode,
    super.filterRegion,
  });
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
/// Each filtered shape carries its own region test — see
/// [RasterShape.filterRegion]. SVG 1.1 §15.7.5 makes the region a clip on
/// the **output**, not on the source, which is the half that is easy to assume
/// and wrong. Measured in Chrome: a bar spanning x = −40…20 blurred inside a
/// region starting at x = 6 renders identically to an unclipped one at every
/// x ≥ 6, and is cut to nothing below it. So content outside the region still
/// bleeds *in*; it just cannot be *seen* outside.
RasterImage rasterizeMaskedShapes({
  required int width,
  required int height,
  required List<RasterShape> shapes,
  required RoundedRectMask mask,
}) {
  final image = RasterImage(width, height);
  for (final _ in rasterizeMaskedShapesSteps(
    image: image,
    shapes: shapes,
    mask: mask,
  )) {
    // Drained here; a caller that wants the thread back drives it itself.
  }
  return image;
}

/// The same drawing, as a sequence a caller can stop between.
///
/// **This is the only implementation** — [rasterizeMaskedShapes] drains it, so
/// the synchronous path and the banded one cannot draw different pictures. That
/// is deliberate and it is what makes byte-identity structural rather than
/// something a test has to keep re-establishing: a `yield` moves control, not a
/// number, and every loop below runs in the order it always ran.
///
/// **A step is a band, never a pixel.** The unit is one row of the image, one
/// row of a filter layer, or one line of a box pass — small enough that a caller
/// on a 60 Hz frame budget can stop in time, large enough that the generator's
/// own per-`yield` cost stays in the noise.
///
/// The caller decides how long to run before yielding, and *what to yield with*.
/// On the web that second choice is the whole thing: a microtask (`await null`)
/// drains before the browser paints and buys nothing — measured in #80, which is
/// how Flutter's own web `compute` manages to move no work at all.
Iterable<void> rasterizeMaskedShapesSteps({
  required RasterImage image,
  required List<RasterShape> shapes,
  required RoundedRectMask mask,
}) sync* {
  final width = image.width;
  final height = image.height;

  for (final shape in shapes) {
    final paint = shape.fill;
    if (paint == null) continue; // no fill attribute — nothing is drawn

    if (shape.needsLayer) {
      yield* _drawThroughLayerSteps(image, shape, paint);
      continue;
    }

    switch (shape) {
      case RasterRect():
        yield* _fillRectSteps(image, shape, paint);
      case RasterPolygon():
        yield* _fillPolygonSteps(image, shape, paint);
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
    yield null;
  }
}

/// SVG 1.1 §15.17's box size for a Gaussian of standard deviation [sigma].
///
/// `d = floor(s * 3 * sqrt(2 * PI) / 4 + 0.5)`. The spec gives the *algorithm*
/// here, not merely a target — which is why this is one of the few places the
/// package can match a browser exactly rather than to within a tolerance.
/// Measured against Chrome at sigma 56 device px (d = 105): **0/255** across
/// eleven samples of a step edge. Contrast hidden-state #27, where Chrome's own
/// curve tessellation makes the same bar unmeetable.
int gaussianBoxSize(double sigma) =>
    (sigma * 3 * math.sqrt(2 * math.pi) / 4 + 0.5).floor();

/// How far a three-box blur of size [d] reaches, in pixels.
///
/// Three convolutions of width `d` have support `3d - 2`, so a pixel can be
/// touched by source up to `(3d - 2 + 1) / 2` away. Rounded up, with a pixel to
/// spare — this decides how far outside the canvas a filtered layer has to be
/// rasterised, and getting it *short* silently drops the part of a shape that
/// blurs back into view.
int blurReach(int d) => d <= 1 ? 0 : (3 * d) ~/ 2 + 1;

/// One three-box pass over [source], in place, along one axis.
///
/// [stride] steps between neighbouring samples on the blur axis and [count] is
/// how many there are; [lines] and [lineStride] walk the other axis. Values
/// outside the buffer are **transparent black**, which is what the filter
/// region's "everything outside is transparent" amounts to for the source.
Iterable<void> _boxPassSteps(
  Float64List source,
  int channels,
  int count,
  int stride,
  int lines,
  int lineStride,
  int d,
) sync* {
  if (d <= 1) return;
  final scratch = Float64List(count);
  final result = Float64List(count);

  // §15.17: an odd `d` is three boxes of `d` centred on the pixel. An even one
  // is two of `d` centred on the two pixel boundaries and a third of `d + 1`
  // centred on the pixel — which is how the spec keeps an even-width box from
  // shifting the image half a pixel.
  //
  // **The even branch's two half-pixel boxes can be swapped and nothing in this
  // package can tell.** Measured by the #41 refuting lens and reproduced on a
  // standalone transcription of this function: box convolutions commute, so
  // with the signal clear of the buffer edge the two orderings agree to
  // **0.0 exactly**, and they diverge only when a pass pushes mass outside
  // `[0, count)` and loses it — up to 3.75/255 for ink flush against index 0.
  // The layer is padded by [blurReach], which always leaves the kernel headroom,
  // so that case is unreachable here. Recorded rather than tested: a test that
  // cannot distinguish two implementations is not a weak test, it is an
  // unfalsifiable distinction, and writing one would read as coverage.
  //
  // The branch *itself* is exercised — `marble`'s `scale(1.2)` gives d = 16 —
  // and mutating its box widths does die. Only the ordering is free.
  final passes = d.isOdd
      ? [(d, (d - 1) ~/ 2), (d, (d - 1) ~/ 2), (d, (d - 1) ~/ 2)]
      : [(d, d ~/ 2), (d, d ~/ 2 - 1), (d + 1, d ~/ 2)];

  for (var line = 0; line < lines; line++) {
    for (var c = 0; c < channels; c++) {
      final base = line * lineStride + c;
      for (var i = 0; i < count; i++) {
        scratch[i] = source[base + i * stride];
      }
      for (final (size, offset) in passes) {
        // A running sum, so the cost is O(n) per pass rather than O(n·d).
        var sum = 0.0;
        for (var k = 0; k < size; k++) {
          final j = k - offset;
          if (j >= 0 && j < count) sum += scratch[j];
        }
        for (var i = 0; i < count; i++) {
          result[i] = sum / size;
          final leaving = i - offset;
          final entering = i - offset + size;
          if (leaving >= 0 && leaving < count) sum -= scratch[leaving];
          if (entering >= 0 && entering < count) sum += scratch[entering];
        }
        scratch.setAll(0, result);
      }
      for (var i = 0; i < count; i++) {
        source[base + i * stride] = scratch[i];
      }
    }
    yield null;
  }
}

/// Draws one shape into its own layer, blurs it, and composites the result.
///
/// **The layer is bigger than the canvas, and it has to be.** `marble`'s second
/// blob reaches x ≈ 89 and y ≈ 100 once its `scale(1.3)` is applied — outside an
/// 80 × 80 target — and a blur of sigma 7 pulls that back about 20 pixels into
/// view. Rasterising only `[0, width)` would drop it, and the result would be a
/// picture that is wrong at the edges with nothing thrown.
///
/// The blur runs on **premultiplied** channels, which is what makes a flat fill
/// keep its colour: blurring `(C·a, a)` and dividing back out gives `C` exactly
/// wherever any coverage survives. It is also why the colour space does not
/// matter here — measured, an sRGB and a linearRGB blur of a single flat colour
/// agree, because only the alpha varies and alpha is not gamma-encoded.
Iterable<void> _drawThroughLayerSteps(
  RasterImage image,
  RasterShape shape,
  RasterPaint paint,
) sync* {
  final sigma = shape.blurSigma;
  final d = sigma == null ? 0 : gaussianBoxSize(sigma);
  final pad = blurReach(d);

  final lw = image.width + 2 * pad;
  final lh = image.height + 2 * pad;
  // Premultiplied RGBA in float — no byte round-trip between the draw and the
  // blur, so the layer rounds once, at the composite.
  final layer = Float64List(lw * lh * 4);

  void put(int px, int py, RasterColour colour, double coverage) {
    // Same product as [RasterImage.blend], for the same reason — a filtered
    // shape painted in a translucent colour is translucent before it is
    // blurred, not after. Unreachable from any upstream variant today
    // (`marble` is the only filtered one and its palette is opaque), which is
    // exactly why it is written here rather than left for the day it is not.
    final a = (coverage * colour.a / 255).clamp(0.0, 1.0);
    if (a <= 0) return;
    final i = ((py + pad) * lw + (px + pad)) * 4;
    // Shapes inside one filtered layer would source-over each other here.
    // Every filtered element upstream writes is a single path, so this is only
    // ever reached once per pixel — but writing it as a composite rather than
    // an assignment keeps the layer correct if that ever stops being true.
    final da = layer[i + 3];
    final outA = a + da * (1 - a);
    if (outA <= 0) return;
    layer[i] = colour.r / 255 * a + layer[i] * (1 - a);
    layer[i + 1] = colour.g / 255 * a + layer[i + 1] * (1 - a);
    layer[i + 2] = colour.b / 255 * a + layer[i + 2] * (1 - a);
    layer[i + 3] = outA;
  }

  switch (shape) {
    case RasterRect():
      // Unreachable, and deleted rather than tested. `filter` and `style` are
      // on `<path>`'s allow-list only, so nothing can build a rect that needs
      // a layer — the #41 refuting lens replaced this branch's 32-line
      // coverage routine with a throw and the whole suite stayed green. That
      // is lessons.md's third question (is the code reachable at all?) and
      // its third answer.
      throw UnsupportedSceneError(
        'a filtered or blended <rect> is not reachable from any scene this '
        'package builds; only <path> carries a filter or a style',
      );
    case RasterPolygon():
      yield* _coverPolygonSteps(shape, lw, lh, pad, put, paint);
  }

  if (d > 1) {
    yield* _boxPassSteps(layer, 4, lw, 4, lh, lw * 4, d); // horizontal
    yield* _boxPassSteps(layer, 4, lh, lw * 4, lw, 4, d); // vertical
  }

  // The region is a quad in device space, so its coverage comes from the same
  // scanline integrator every other shape uses — one implementation, not two.
  final region = shape.filterRegion;
  Float64List? regionCoverage;
  if (region != null) {
    regionCoverage = Float64List(image.width * image.height);
    yield* polygonCoverageSteps(
      width: image.width,
      height: image.height,
      polygon: RasterPolygon([region], null),
      out: regionCoverage,
    );
  }

  for (var py = 0; py < image.height; py++) {
    for (var px = 0; px < image.width; px++) {
      // §15.7.5's clip, on the output only — and **antialiased**, because
      // Chrome shades the boundary rather than stepping it. Measured on
      // `marble-clara-square`, where the region really does cut a corner: a
      // binary pixel-centre test leaves 11/255 at the edge and this leaves
      // less. The coverage is computed once per shape, above.
      final coverage = regionCoverage == null
          ? 1.0
          : regionCoverage[py * image.width + px];
      if (coverage <= 0) continue;
      final i = ((py + pad) * lw + (px + pad)) * 4;
      final layerAlpha = layer[i + 3];
      if (layerAlpha <= 0) continue;
      image.blendSource(
        px,
        py,
        // Back to straight alpha for the composite, which is the buffer's
        // format. The divisor is the **layer's own** alpha, not the clipped
        // one: the region scales how much of the result is let through, and
        // scaling a straight colour by it would darken the boundary instead of
        // fading it.
        layer[i] / layerAlpha,
        layer[i + 1] / layerAlpha,
        layer[i + 2] / layerAlpha,
        layerAlpha * coverage,
        shape.blendMode,
      );
    }
    yield null;
  }
}

/// Coverage of a polygon, offset into a padded layer.
///
/// The contours are translated by [pad] and run through the same integrator the
/// unfiltered path uses, so a filtered shape and an unfiltered one cannot
/// disagree about coverage — there is one implementation, not two.
Iterable<void> _coverPolygonSteps(
  RasterPolygon polygon,
  int lw,
  int lh,
  int pad,
  void Function(int, int, RasterColour, double) put,
  RasterPaint paint,
) sync* {
  final shifted = RasterPolygon([
    for (final contour in polygon.contours)
      PathContour([
        for (var i = 0; i < contour.points.length; i++) contour.points[i] + pad,
      ]),
  ], polygon.fill);
  final coverage = Float64List(lw * lh);
  yield* polygonCoverageSteps(
    width: lw,
    height: lh,
    polygon: shifted,
    out: coverage,
  );
  // Row-major, which is the order the flat walk this replaced already used —
  // `i % lw` and `i ~/ lw` visit exactly these pixels in exactly this sequence.
  for (var ly = 0; ly < lh; ly++) {
    final base = ly * lw;
    for (var lx = 0; lx < lw; lx++) {
      final c = coverage[base + lx];
      if (c <= 0) continue;
      final px = lx - pad, py = ly - pad;
      put(px, py, paint.colourAt(px, py), c);
    }
    yield null;
  }
}

Iterable<void> _fillRectSteps(
  RasterImage image,
  RasterRect rect,
  RasterPaint paint,
) sync* {
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
    yield null;
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

Iterable<void> _fillPolygonSteps(
  RasterImage image,
  RasterPolygon polygon,
  RasterPaint paint,
) sync* {
  final coverage = Float64List(image.width * image.height);
  yield* polygonCoverageSteps(
    width: image.width,
    height: image.height,
    polygon: polygon,
    out: coverage,
  );
  for (var py = 0; py < image.height; py++) {
    final base = py * image.width;
    for (var px = 0; px < image.width; px++) {
      final c = coverage[base + px];
      if (c <= 0) continue;
      image.blend(px, py, paint.colourAt(px, py), c);
    }
    yield null;
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
  for (final _ in polygonCoverageSteps(
    width: width,
    height: height,
    polygon: polygon,
    out: out,
  )) {
    // Drained here.
  }
  return out;
}

/// [polygonCoverage], as a sequence with one step per scanline.
///
/// **This is where the time goes**, which is why it is the finest-grained of the
/// generators: every row integrates [_slicesPerRow] slices against the active
/// edge list, so a single row of a large target is already milliseconds. Writing
/// into a caller-supplied [out] rather than returning one is what lets it be a
/// generator at all — `sync*` has no return value.
Iterable<void> polygonCoverageSteps({
  required int width,
  required int height,
  required RasterPolygon polygon,
  required Float64List out,
}) sync* {
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
  if (edges.isEmpty) return;

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
    yield null;
  }
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
