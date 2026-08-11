// The CSS Color 4 conversion maths behind hwb(), lab()/lch(),
// oklab()/oklch() and color() — #95.
//
// **Matrices are derived from the primaries' chromaticities at load, not
// transcribed.** The spec's own conversion code ships long rational matrices;
// copying them by hand smuggles in a digit error nothing can catch locally
// (the named-colours rule, one level up: a wrong entry is wrong only for the
// input that hits it). The chromaticities below are short, they are the
// numbers the spec *defines* the spaces by, and the 70-odd Chrome-measured
// swatches in `raster_colour4_test.dart` are the cross-check that the
// derivation lands on the browser's bytes.
//
// **The gamut model is per-channel clip, and that is measured, not chosen.**
// CSS Color 4 §13 describes a chroma-reduction gamut-mapping algorithm; what
// Chrome 151 actually does to an out-of-gamut colour is clip each channel —
// `color(display-p3 1 0 0)` renders exactly `255,0,0`, `lab(50% 100 0)`
// exactly `255,0,124`, `oklch(0.7 0.35 30)` exactly `255,0,0`. The clip has
// exactly one copy, at the parser's byte conversion (`_encodedToColour`),
// because the transfer function is monotone: clipping linear, encoded or
// byte values are the same operation, and only one of them can be the one a
// mutation is able to kill. If a future Chrome switches to the spec's
// mapping, the swatches above are what will disagree first.
library;

import 'dart:math' as math;

/// A 3x3 matrix as nine doubles, row-major.
class _M3 {
  const _M3(this.m);
  final List<double> m;

  List<double> apply(double a, double b, double c) => [
    m[0] * a + m[1] * b + m[2] * c,
    m[3] * a + m[4] * b + m[5] * c,
    m[6] * a + m[7] * b + m[8] * c,
  ];

  _M3 multiply(_M3 o) {
    final r = List<double>.filled(9, 0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        r[i * 3 + j] =
            m[i * 3] * o.m[j] +
            m[i * 3 + 1] * o.m[3 + j] +
            m[i * 3 + 2] * o.m[6 + j];
      }
    }
    return _M3(r);
  }

  _M3 inverse() {
    final a = m;
    final c00 = a[4] * a[8] - a[5] * a[7];
    final c01 = a[5] * a[6] - a[3] * a[8];
    final c02 = a[3] * a[7] - a[4] * a[6];
    final det = a[0] * c00 + a[1] * c01 + a[2] * c02;
    return _M3([
      c00 / det,
      (a[2] * a[7] - a[1] * a[8]) / det,
      (a[1] * a[5] - a[2] * a[4]) / det,
      c01 / det,
      (a[0] * a[8] - a[2] * a[6]) / det,
      (a[2] * a[3] - a[0] * a[5]) / det,
      c02 / det,
      (a[1] * a[6] - a[0] * a[7]) / det,
      (a[0] * a[4] - a[1] * a[3]) / det,
    ]);
  }
}

/// White point XYZ from an xy chromaticity, at Y = 1.
List<double> _whiteXyz(double x, double y) => [x / y, 1.0, (1 - x - y) / y];

/// linear-RGB → XYZ for a space given by its primaries and white, the
/// standard construction: scale each primary's XYZ column so the white sums.
_M3 _rgbToXyz(List<double> xy, List<double> white) {
  final p = _M3([
    xy[0] / xy[1], xy[2] / xy[3], xy[4] / xy[5], //
    1, 1, 1, //
    (1 - xy[0] - xy[1]) / xy[1],
    (1 - xy[2] - xy[3]) / xy[3],
    (1 - xy[4] - xy[5]) / xy[5],
  ]);
  final s = p.inverse().apply(white[0], white[1], white[2]);
  return _M3([
    p.m[0] * s[0], p.m[1] * s[1], p.m[2] * s[2], //
    p.m[3] * s[0], p.m[4] * s[1], p.m[5] * s[2], //
    p.m[6] * s[0], p.m[7] * s[1], p.m[8] * s[2],
  ]);
}

final _d65 = _whiteXyz(0.3127, 0.3290);
final _d50 = _whiteXyz(0.3457, 0.3585);

/// The Bradford cone-response matrix, the one adaptation CSS Color 4 uses.
const _bradford = _M3([
  0.8951, 0.2664, -0.1614, //
  -0.7502, 1.7135, 0.0367, //
  0.0389, -0.0685, 1.0296,
]);

/// Chromatic adaptation [from] one white [to] another: cone responses of the
/// two whites, scaled per channel, conjugated back out of cone space.
_M3 _adapt(List<double> from, List<double> to) {
  final cf = _bradford.apply(from[0], from[1], from[2]);
  final ct = _bradford.apply(to[0], to[1], to[2]);
  final scale = _M3([
    ct[0] / cf[0], 0, 0, //
    0, ct[1] / cf[1], 0, //
    0, 0, ct[2] / cf[2],
  ]);
  return _bradford.inverse().multiply(scale).multiply(_bradford);
}

final _d50ToD65 = _adapt(_d50, _d65);
final _xyzD65ToLinearSrgb = _rgbToXyz([
  0.64,
  0.33,
  0.30,
  0.60,
  0.15,
  0.06,
], _d65).inverse();

/// sRGB's transfer function, linear → encoded, for a channel already clipped
/// to [0, 1].
double _srgbEncode(double c) =>
    c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

/// linear sRGB → the three encoded channels, **not yet clipped**.
///
/// The gamut clip lives in one place — the byte conversion at the parser —
/// and not also here, on the #40 rule that a guard no mutation can kill is
/// deleted rather than kept: the transfer function is monotone and fixes 0
/// and 1, so clipping the linear value and clipping the byte are the same
/// operation, and a second copy of the clip was unkillable by construction.
/// (A negative channel takes the linear branch below — `pow` never sees it —
/// so nothing here manufactures a NaN on the way to that clip.)
List<double> encodeLinearSrgb(double r, double g, double b) => [
  _srgbEncode(r),
  _srgbEncode(g),
  _srgbEncode(b),
];

List<double> _xyzD65ToEncoded(List<double> xyz) {
  final lin = _xyzD65ToLinearSrgb.apply(xyz[0], xyz[1], xyz[2]);
  return encodeLinearSrgb(lin[0], lin[1], lin[2]);
}

/// hwb → encoded sRGB channels, CSS Color 4 §8: the pure hue mixed toward
/// white by [w] and toward black by [b]; at `w + b >= 1` the hue is gone and
/// the colour is the gray `w / (w + b)`.
List<double> hwbToEncoded(double hue, double w, double b) {
  final wc = w.clamp(0.0, 1.0);
  final bc = b.clamp(0.0, 1.0);
  if (wc + bc >= 1) {
    final gray = wc / (wc + bc);
    return [gray, gray, gray];
  }
  final h = hue % 360;
  final x = 1 - ((h / 60) % 2 - 1).abs();
  final (r, g, bl) = switch (h) {
    < 60 => (1.0, x, 0.0),
    < 120 => (x, 1.0, 0.0),
    < 180 => (0.0, 1.0, x),
    < 240 => (0.0, x, 1.0),
    < 300 => (x, 0.0, 1.0),
    _ => (1.0, 0.0, x),
  };
  double mix(double c) => c * (1 - wc - bc) + wc;
  return [mix(r), mix(g), mix(bl)];
}

/// CIE Lab (D50, as CSS defines it) → encoded sRGB channels.
List<double> labToEncoded(double l, double a, double b) {
  const e = 216 / 24389;
  const k = 24389 / 27;
  final fy = (l + 16) / 116;
  final fx = fy + a / 500;
  final fz = fy - b / 200;
  final x3 = fx * fx * fx;
  final z3 = fz * fz * fz;
  final xr = x3 > e ? x3 : (116 * fx - 16) / k;
  final yr = l > k * e ? fy * fy * fy : l / k;
  final zr = z3 > e ? z3 : (116 * fz - 16) / k;
  final xyz = _d50ToD65.apply(xr * _d50[0], yr * _d50[1], zr * _d50[2]);
  return _xyzD65ToEncoded(xyz);
}

/// OKLab → encoded sRGB channels.
///
/// The two matrices are the specification's own (they define the space and
/// are not derivable from primaries the way the RGB spaces above are); the
/// Chrome-measured swatches are what checks the transcription.
List<double> oklabToEncoded(double l, double a, double b) {
  final l1 = l + 0.3963377773761749 * a + 0.2158037573099136 * b;
  final m1 = l - 0.1055613458156586 * a - 0.0638541728258133 * b;
  final s1 = l - 0.0894841775298119 * a - 1.2914855480194092 * b;
  final l3 = l1 * l1 * l1;
  final m3 = m1 * m1 * m1;
  final s3 = s1 * s1 * s1;
  return encodeLinearSrgb(
    4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
    -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
    -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
  );
}

/// `lch`/`oklch` are their rectangular spaces in polar clothes.
(double, double) lchToAb(double c, double h) {
  final rad = h * math.pi / 180;
  return (c * math.cos(rad), c * math.sin(rad));
}

/// One predefined `color()` RGB space: its transfer decode and its
/// linear-RGB → XYZ-D65 matrix (the D50 space adapts on the way).
class ColourSpace {
  ColourSpace._(this._decode, this._toXyzD65);
  final double Function(double) _decode;
  final _M3? _toXyzD65;

  List<double> encodedFrom(double a, double b, double c) {
    final la = _decode(a);
    final lb = _decode(b);
    final lc = _decode(c);
    final m = _toXyzD65;
    if (m == null) return encodeLinearSrgb(la, lb, lc);
    final xyz = m.apply(la, lb, lc);
    return _xyzD65ToEncoded(xyz);
  }
}

double _srgbDecode(double c) {
  final sign = c < 0 ? -1.0 : 1.0;
  final v = c.abs();
  return sign * (v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4));
}

double _a98Decode(double c) {
  final sign = c < 0 ? -1.0 : 1.0;
  return sign * math.pow(c.abs(), 563 / 256);
}

double _prophotoDecode(double c) {
  final sign = c < 0 ? -1.0 : 1.0;
  final v = c.abs();
  return sign * (v <= 16 / 512 ? v / 16 : math.pow(v, 1.8));
}

double _rec2020Decode(double c) {
  const alpha = 1.09929682680944;
  const beta = 0.018053968510807;
  final sign = c < 0 ? -1.0 : 1.0;
  final v = c.abs();
  return sign *
      (v < beta * 4.5 ? v / 4.5 : math.pow((v + alpha - 1) / alpha, 1 / 0.45));
}

double _identity(double c) => c;

/// The predefined spaces `color()` accepts, by their CSS names.
///
/// `xyz` is an alias of `xyz-d65` — measured identical — and `prophoto-rgb`
/// and `xyz-d50` are the two D50 spaces, adapted through the same Bradford
/// matrix Lab uses.
final Map<String, ColourSpace> colourFunctionSpaces = () {
  final p3 = _rgbToXyz([0.680, 0.320, 0.265, 0.690, 0.150, 0.060], _d65);
  final a98 = _rgbToXyz([0.6400, 0.3300, 0.2100, 0.7100, 0.1500, 0.0600], _d65);
  final prophoto = _rgbToXyz([
    0.734699,
    0.265301,
    0.159597,
    0.840403,
    0.036598,
    0.000105,
  ], _d50);
  final rec2020 = _rgbToXyz([0.708, 0.292, 0.170, 0.797, 0.131, 0.046], _d65);
  final d50Adapt = _d50ToD65;
  final identity3 = const _M3([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  return <String, ColourSpace>{
    'srgb': ColourSpace._(_srgbDecode, null),
    'srgb-linear': ColourSpace._(_identity, null),
    'display-p3': ColourSpace._(_srgbDecode, p3),
    'a98-rgb': ColourSpace._(_a98Decode, a98),
    'prophoto-rgb': ColourSpace._(_prophotoDecode, d50Adapt.multiply(prophoto)),
    'rec2020': ColourSpace._(_rec2020Decode, rec2020),
    'xyz': ColourSpace._(_identity, identity3),
    'xyz-d65': ColourSpace._(_identity, identity3),
    'xyz-d50': ColourSpace._(_identity, d50Adapt),
  };
}();
