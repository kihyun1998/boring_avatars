/// SVG path data → closed polygons, with a stated flattening tolerance.
///
/// The rasterizer draws polygons; everything curved arrives here first. Two
/// things about this file are load-bearing:
///
/// * **The flattening tolerance is a constant, not a heuristic.** [flatness] is
///   the largest distance a chord may fall inside the true curve, so the number
///   of segments follows from the radius and the swept angle and nothing else.
///   Two runs on two machines produce the same vertices.
/// * **Arc flags are single characters and may be packed against the numbers
///   that follow them.** Upstream writes `a32 32 0 10-64 0`, where `10` is *two
///   flags*, not the number ten. A tokeniser that scans numbers uniformly reads
///   this as a radius sweep of ten and produces a plausible wrong picture — the
///   exact failure mode [UnsupportedSceneError] exists to prevent, except that
///   here nothing would even throw.
///
/// **Scope.** Across all 600 renders in the v1.6.1 fixture the six variants use
/// nine commands in total — `M H h L l v z a` and, in `beam` alone, `c`. The
/// straight-line and arc commands are implemented here in both cases; cubics
/// throw, and arrive with `beam`.
library;

import 'dart:math' as math;

import 'raster.dart';

/// The default flattening tolerance, in user units.
///
/// A chord may sit at most this far inside the arc it replaces. At 1/4096 of a
/// unit the geometric error is two orders of magnitude below the ≤1/255
/// coverage the calibration bar allows, and the segment counts stay in the low
/// hundreds: `ring`'s widest arc, a semicircle of radius 38, becomes 440
/// segments.
const double defaultFlatness = 1 / 4096;

/// Parses SVG path data into closed contours.
///
/// Every subpath is treated as closed whether or not it ends in `z`, because a
/// *filled* path closes implicitly — which is what the fill rule sees.
List<PathContour> parsePath(String d, {double flatness = defaultFlatness}) {
  final scanner = _Scanner(d);
  final contours = <PathContour>[];
  var current = <double>[];

  var x = 0.0, y = 0.0; // the current point
  var startX = 0.0, startY = 0.0; // the current subpath's origin

  void moveTo(double nx, double ny) {
    if (current.length >= 6) contours.add(PathContour(current));
    current = <double>[nx, ny];
    x = startX = nx;
    y = startY = ny;
  }

  void lineTo(double nx, double ny) {
    current.addAll([nx, ny]);
    x = nx;
    y = ny;
  }

  var command = '';
  while (!scanner.atEnd) {
    final next = scanner.peekCommand();
    if (next != null) {
      command = next;
      scanner.skipCommand();
    } else if (command.isEmpty) {
      throw UnsupportedSceneError(
        'path data does not start with a command: "$d"',
      );
    } else if (command == 'M') {
      command =
          'L'; // an implicit repeat of moveto is a lineto, per the grammar
    } else if (command == 'm') {
      command = 'l';
    }

    final relative = command == command.toLowerCase();
    switch (command.toUpperCase()) {
      case 'M':
        final nx = scanner.number(), ny = scanner.number();
        moveTo(relative ? x + nx : nx, relative ? y + ny : ny);
      case 'L':
        final nx = scanner.number(), ny = scanner.number();
        lineTo(relative ? x + nx : nx, relative ? y + ny : ny);
      case 'H':
        final nx = scanner.number();
        lineTo(relative ? x + nx : nx, y);
      case 'V':
        final ny = scanner.number();
        lineTo(x, relative ? y + ny : ny);
      case 'A':
        final rx = scanner.number();
        final ry = scanner.number();
        final rotation = scanner.number();
        // Flags are single characters. Reading them as numbers is the trap
        // this file's doc opens with.
        final largeArc = scanner.flag();
        final sweep = scanner.flag();
        final ex = scanner.number(), ey = scanner.number();
        final tx = relative ? x + ex : ex;
        final ty = relative ? y + ey : ey;
        _appendArc(
          current,
          x0: x,
          y0: y,
          x1: tx,
          y1: ty,
          rx: rx,
          ry: ry,
          rotationDegrees: rotation,
          largeArc: largeArc,
          sweep: sweep,
          flatness: flatness,
        );
        x = tx;
        y = ty;
      case 'Z':
        // `closepath` takes no arguments, so a number here cannot belong to a
        // repeat of it. Without this the loop consumes nothing and spins
        // forever — a malformed `d` would hang the render rather than fail it.
        if (next == null) {
          throw UnsupportedSceneError(
            'a number follows `z`, which takes no arguments, in "$d"',
          );
        }
        // `z` ends the subpath. Anything that follows begins a *new* one, from
        // the same origin — so the contour has to be pushed here. Leaving it
        // open welded the next subpath onto this one: `M0 0h10v10H0zh10v10`
        // came out as a single 75-unit contour instead of two squares.
        if (current.length >= 6) contours.add(PathContour(current));
        current = <double>[startX, startY];
        x = startX;
        y = startY;
      default:
        throw UnsupportedSceneError(
          'path command "$command" is not implemented (in "$d")',
        );
    }
  }

  if (current.length >= 6) contours.add(PathContour(current));
  return contours;
}

/// A circle as one closed contour, flattened on the same tolerance.
PathContour flattenCircle(
  double cx,
  double cy,
  double r, {
  double flatness = defaultFlatness,
}) {
  final segments = _segmentsFor(r, 2 * math.pi, flatness);
  final points = <double>[];
  for (var i = 0; i < segments; i++) {
    final theta = 2 * math.pi * i / segments;
    points.addAll([cx + r * math.cos(theta), cy + r * math.sin(theta)]);
  }
  return PathContour(points);
}

/// An axis-aligned rectangle as one closed contour, wound clockwise.
PathContour rectangleContour(double x, double y, double width, double height) =>
    PathContour([x, y, x + width, y, x + width, y + height, x, y + height]);

/// The outline of a stroked straight segment, with **butt** caps.
///
/// SVG 1.1 §11.4 gives `stroke-linecap` an initial value of `butt`, and no
/// element in the six variants declares another one — `beam`'s stroked path
/// does declare `stroke-linecap`, and it arrives with `beam`. Butt caps mean
/// the stroke stops exactly at the endpoints, so the outline is the rectangle
/// swept by a segment of width [width] centred on the line: no extension, no
/// round end.
///
/// Returns `null` where the specification says nothing is stroked, rather than
/// a degenerate contour:
///
/// * **a zero-length segment** — §11.4: "Any zero length subpath shall not be
///   stroked if the `stroke-linecap` property has a value of `butt`". Guarding
///   it is not only spec compliance: normalising a zero vector would put `NaN`
///   in every vertex, and `NaN` propagates silently into the scanline
///   integrator.
/// * **a zero or negative width** — §11.4: "A zero value causes no stroke to be
///   painted."
PathContour? strokeSegmentContour(
  double x1,
  double y1,
  double x2,
  double y2,
  double width,
) {
  if (width <= 0) return null;
  final dx = x2 - x1;
  final dy = y2 - y1;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return null;

  // The offset to each side: the unit normal times half the stroke width.
  //
  // **Which** side is which does not matter, and that is provable rather than
  // lucky: negating the normal yields the same four points in reverse order, so
  // the polygon is identical and only its winding flips — and the nonzero rule
  // fills either way. A mutation flipping it survives the suite, predicted
  // before it was run. What is *not* symmetric is using the tangent instead, or
  // taking a full width to each side; both are mutation-tested.
  final nx = -dy / length * width / 2;
  final ny = dx / length * width / 2;
  return PathContour([
    x1 + nx, y1 + ny, //
    x2 + nx, y2 + ny,
    x2 - nx, y2 - ny,
    x1 - nx, y1 - ny,
  ]);
}

/// How many chords approximate an arc of [radius] sweeping [sweep] radians
/// without any of them falling more than [flatness] inside it.
///
/// The sagitta of a chord subtending `α` on a circle of radius `r` is
/// `r(1 − cos(α/2))`, so the largest admissible `α` is `2·acos(1 − ε/r)`.
int _segmentsFor(double radius, double sweep, double flatness) {
  final span = sweep.abs();
  if (radius <= flatness) return 4; // degenerate; any polygon is within ε
  final maxAngle = 2 * math.acos(1 - flatness / radius);
  return math.max(2, (span / maxAngle).ceil());
}

/// Appends an elliptical arc to [out], excluding its start point.
///
/// This is SVG 1.1 F.6.5 (endpoint → centre parameterisation) followed by
/// F.6.6 (out-of-range radii). Both are implemented from the specification
/// text rather than from a restatement of it, because the corrections are
/// exactly where an approximation goes wrong.
void _appendArc(
  List<double> out, {
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  required double rx,
  required double ry,
  required double rotationDegrees,
  required bool largeArc,
  required bool sweep,
  required double flatness,
}) {
  // F.6.6 step 1: a zero radius degenerates to a straight line.
  if (rx == 0 || ry == 0 || (x0 == x1 && y0 == y1)) {
    out.addAll([x1, y1]);
    return;
  }

  // F.6.6 step 1 (continued): radii are taken as absolute values.
  var a = rx.abs();
  var b = ry.abs();

  final phi = rotationDegrees * math.pi / 180;
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);

  // F.6.5 step 1 — the endpoints in the ellipse's own frame.
  final dx = (x0 - x1) / 2;
  final dy = (y0 - y1) / 2;
  final px = cosPhi * dx + sinPhi * dy;
  final py = -sinPhi * dx + cosPhi * dy;

  // F.6.6 step 3 — scale both radii up until the ellipse can reach.
  //
  // `ring`'s arcs land exactly on the boundary: each chord is 76, 64 or 52
  // long on radii of 38, 32 and 26, so lambda is exactly 1 and no correction
  // applies. That is also why the square root below needs its clamp.
  final lambda = (px * px) / (a * a) + (py * py) / (b * b);
  if (lambda > 1) {
    final scale = math.sqrt(lambda);
    a *= scale;
    b *= scale;
  }

  // F.6.5 step 2 — the centre, in the ellipse's frame.
  final aa = a * a, bb = b * b;
  final denominator = aa * py * py + bb * px * px;
  // Exactly zero when the arc is a half-ellipse. Floating point can put it a
  // few ulps below, and `sqrt` of a negative is NaN — which would propagate
  // silently into every vertex.
  final radicand = math.max(0.0, (aa * bb - denominator) / denominator);
  final sign = largeArc != sweep ? 1.0 : -1.0;
  final coefficient = sign * math.sqrt(radicand);
  final cxPrime = coefficient * (a * py / b);
  final cyPrime = coefficient * (-b * px / a);

  // F.6.5 step 3 — back to user space.
  final cx = cosPhi * cxPrime - sinPhi * cyPrime + (x0 + x1) / 2;
  final cy = sinPhi * cxPrime + cosPhi * cyPrime + (y0 + y1) / 2;

  // F.6.5 step 4 — the start angle and the swept angle.
  final ux = (px - cxPrime) / a;
  final uy = (py - cyPrime) / b;
  final vx = (-px - cxPrime) / a;
  final vy = (-py - cyPrime) / b;

  final theta0 = math.atan2(uy, ux);
  var delta = math.atan2(vy, vx) - theta0;
  if (!sweep && delta > 0) {
    delta -= 2 * math.pi;
  } else if (sweep && delta < 0) {
    delta += 2 * math.pi;
  }

  // The tolerance is set against the larger radius, so the smaller direction
  // is flattened at least as finely as it needs.
  final segments = _segmentsFor(math.max(a, b), delta, flatness);
  for (var i = 1; i <= segments; i++) {
    final theta = theta0 + delta * i / segments;
    final ex = a * math.cos(theta);
    final ey = b * math.sin(theta);
    out.addAll([
      cosPhi * ex - sinPhi * ey + cx,
      sinPhi * ex + cosPhi * ey + cy,
    ]);
  }
}

/// A minimal SVG path-data tokeniser.
///
/// Separators in path data are optional wherever they are unambiguous, so
/// `h90v45H0z` and `a38 38 0 00-76 0` are both well-formed. Numbers may be
/// separated by a sign or a decimal point alone.
class _Scanner {
  _Scanner(this.source);

  final String source;
  int index = 0;

  bool get atEnd {
    _skipSeparators();
    return index >= source.length;
  }

  void _skipSeparators() {
    while (index < source.length) {
      final c = source.codeUnitAt(index);
      // space, tab, LF, CR, FF, comma
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          c == 0x0C ||
          c == 0x2C) {
        index++;
      } else {
        return;
      }
    }
  }

  static const _commands = 'MmLlHhVvAaCcSsQqTtZz';

  /// The command letter at the cursor, or `null` if a number is next.
  String? peekCommand() {
    _skipSeparators();
    if (index >= source.length) return null;
    final c = source[index];
    return _commands.contains(c) ? c : null;
  }

  void skipCommand() => index++;

  /// A single `0` or `1` flag, which may be packed against what follows.
  bool flag() {
    _skipSeparators();
    if (index >= source.length) {
      throw UnsupportedSceneError('path data ended where a flag was expected');
    }
    final c = source[index];
    if (c != '0' && c != '1') {
      throw UnsupportedSceneError('"$c" is not an arc flag in "$source"');
    }
    index++;
    return c == '1';
  }

  double number() {
    _skipSeparators();
    final start = index;
    if (index < source.length &&
        (source[index] == '-' || source[index] == '+')) {
      index++;
    }
    while (index < source.length && _isDigit(source.codeUnitAt(index))) {
      index++;
    }
    if (index < source.length && source[index] == '.') {
      index++;
      while (index < source.length && _isDigit(source.codeUnitAt(index))) {
        index++;
      }
    }
    if (index < source.length &&
        (source[index] == 'e' || source[index] == 'E')) {
      final save = index;
      index++;
      if (index < source.length &&
          (source[index] == '-' || source[index] == '+')) {
        index++;
      }
      if (index < source.length && _isDigit(source.codeUnitAt(index))) {
        while (index < source.length && _isDigit(source.codeUnitAt(index))) {
          index++;
        }
      } else {
        index = save; // an `e` that is not an exponent belongs to no number
      }
    }
    final text = source.substring(start, index);
    final value = double.tryParse(text);
    if (value == null) {
      throw UnsupportedSceneError(
        'expected a number at offset $start in "$source"',
      );
    }
    return value;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
}
