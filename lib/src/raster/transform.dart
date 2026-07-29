/// The `transform` attribute → an affine matrix, per SVG 1.1 §7.
///
/// The SVG backend emits upstream's transform **string** verbatim; this is
/// where the other backend reads it back as geometry. Both start from the same
/// scene attribute, which is the point of the seam — a rasterizer that derived
/// its own placement from `translateX`/`rotate` would be a second copy of the
/// geometry, free to drift.
///
/// Three things are taken from the specification text rather than from a
/// restatement of it, because each is a place an approximation goes wrong:
///
/// * **A transform list post-multiplies.** §7.5: a list is "as if each
///   transform had been specified separately in the order provided", which §7.5
///   shows as nested `<g>` elements. So `translate(…) rotate(…)` is
///   `T · R` and the *rotation* applies to the shape's own coordinates first.
///   Writing the composition the other way round is a plausible wrong picture:
///   the shape lands somewhere reasonable and nothing throws.
/// * **`rotate(a cx cy)` is not a fourth kind of operation.** §7.4 defines it as
///   exactly `translate(cx, cy) rotate(a) translate(-cx, -cy)`, so it is built
///   that way here instead of from a remembered closed form.
/// * **The transform is applied before the element's own coordinates are
///   read.** §7.4: `x`, `y`, `width` and `height` are values in the *new* user
///   coordinate system. So the shape's geometry is built first and then mapped,
///   which is what [Affine.apply] does to each vertex.
///
/// **Only `translate` and `rotate` are implemented.** `bauhaus` uses those two;
/// `beam` and `marble` also use `scale`, measured across all 600 renders in the
/// v1.6.1 fixture. Anything else throws rather than being skipped — an ignored
/// transform is the failure `UnsupportedSceneError` exists for.
library;

import 'dart:math' as math;

import 'raster.dart';

/// A 2-D affine transform, in SVG's `[a b c d e f]` order.
///
/// The matrix is
///
/// ```
/// | a c e |
/// | b d f |
/// | 0 0 1 |
/// ```
///
/// which is §7.4's layout, not the row-major one a linear-algebra habit
/// reaches for.
class Affine {
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  static const Affine identity = Affine(1, 0, 0, 1, 0, 0);

  /// `[1 0 0 1 tx ty]` — §7.4.
  const Affine.translation(double tx, double ty) : this(1, 0, 0, 1, tx, ty);

  /// `[cos(a) sin(a) -sin(a) cos(a) 0 0]` — §7.4, about the origin.
  factory Affine.rotation(double degrees) {
    final radians = degrees * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return Affine(cos, sin, -sin, cos, 0, 0);
  }

  final double a, b, c, d, e, f;

  /// `this · other`, so [other] applies to a point **first**.
  ///
  /// This is the post-multiplication §7.5 describes, and the order is the whole
  /// content of the operation — swapping the operands compiles and draws.
  Affine multiply(Affine other) => Affine(
    a * other.a + c * other.b,
    b * other.a + d * other.b,
    a * other.c + c * other.d,
    b * other.c + d * other.d,
    a * other.e + c * other.f + e,
    b * other.e + d * other.f + f,
  );

  /// Maps a point from the new user space into the previous one.
  (double, double) apply(double x, double y) =>
      (a * x + c * y + e, b * x + d * y + f);

  /// Whether this moves points without rotating, scaling or skewing them.
  ///
  /// A pure translation lets an axis-aligned rectangle stay one — which matters,
  /// because [RasterRect] integrates its coverage in closed form and the polygon
  /// integrator quantises the vertical direction, where a horizontal edge is
  /// exactly the worst case. `rotate(0 cx cy)` lands here exactly: `cos(0)` is
  /// 1 and `sin(0)` is 0 with no rounding, so a zero rotation is not a
  /// near-identity, it *is* the identity.
  bool get isTranslationOnly => a == 1 && b == 0 && c == 0 && d == 1;

  /// A copy of [contour] with every vertex mapped.
  PathContour transformContour(PathContour contour) {
    final points = List<double>.filled(contour.points.length, 0);
    for (var i = 0; i < contour.length; i++) {
      final (x, y) = apply(contour.x(i), contour.y(i));
      points[i * 2] = x;
      points[i * 2 + 1] = y;
    }
    return PathContour(points);
  }
}

/// The functions this rasterizer can read. Everything else is a real capability.
const _implemented = {'translate', 'rotate'};

/// Parses a `transform` attribute into a single matrix.
///
/// Returns [Affine.identity] for an empty list, which is what a `transform=""`
/// means — not an error.
Affine parseTransform(String source) {
  var matrix = Affine.identity;
  var index = 0;
  var found = false;

  while (index < source.length) {
    final match = _function.matchAsPrefix(source, index);
    if (match == null) {
      if (source.substring(index).trim().isEmpty) break;
      throw UnsupportedSceneError(
        'transform "$source" is not a list of transform functions',
      );
    }
    index = match.end;
    found = true;

    final name = match.group(1)!;
    if (!_implemented.contains(name)) {
      throw UnsupportedSceneError(
        'transform function "$name(…)" is not implemented; only '
        '${_implemented.join(", ")} are — `scale` arrives with `beam`',
      );
    }

    final arguments = match
        .group(2)!
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty)
        .map((t) {
          final value = double.tryParse(t);
          if (value == null) {
            throw UnsupportedSceneError(
              '"$t" is not a number, in transform "$source"',
            );
          }
          return value;
        })
        .toList();

    matrix = matrix.multiply(_build(name, arguments, source));
  }

  if (!found && source.trim().isNotEmpty) {
    throw UnsupportedSceneError('unreadable transform "$source"');
  }
  return matrix;
}

Affine _build(String name, List<double> arguments, String source) {
  switch (name) {
    case 'translate':
      // §7.4: "If <ty> is not provided, it is assumed to be zero."
      if (arguments.length != 1 && arguments.length != 2) {
        throw UnsupportedSceneError(
          'translate takes one or two numbers, got ${arguments.length}, in '
          '"$source"',
        );
      }
      return Affine.translation(
        arguments[0],
        arguments.length == 2 ? arguments[1] : 0,
      );
    case 'rotate':
      if (arguments.length == 1) {
        return Affine.rotation(arguments[0]);
      }
      if (arguments.length != 3) {
        throw UnsupportedSceneError(
          'rotate takes one or three numbers, got ${arguments.length}, in '
          '"$source"',
        );
      }
      // §7.4, verbatim: the three-argument form "represents the equivalent of
      // translate(<cx>, <cy>) rotate(<rotate-angle>) translate(-<cx>, -<cy>)".
      final (cx, cy) = (arguments[1], arguments[2]);
      return Affine.translation(cx, cy)
          .multiply(Affine.rotation(arguments[0]))
          .multiply(Affine.translation(-cx, -cy));
    default:
      throw UnsupportedSceneError('transform "$name" reached _build');
  }
}

/// `name(args)`, with optional leading whitespace or commas.
final RegExp _function = RegExp(r'[\s,]*([a-zA-Z]+)\s*\(([^)]*)\)');
