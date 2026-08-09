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
/// nine commands in total — `M H h L l v z a` and, in `beam` alone, `c`. All
/// nine are implemented, in both their relative and absolute forms. Everything
/// else — `q`, `s`, `t` — still throws, because no upstream version in scope
/// writes one and untested arithmetic is worse than a loud failure.
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

/// One subpath as the path data actually described it.
///
/// [points] is the flattened polyline, `[x0, y0, x1, y1, …]`, and [closed]
/// records whether a `z` ended it. **Both facts are dropped by [parsePath]**,
/// which is right for a fill — an unclosed subpath closes implicitly and a
/// subpath of one or two points has no area — and wrong for a stroke, where a
/// two-point subpath is a line to draw and `z` decides whether the ends meet in
/// a join or in two caps.
class PathSubpath {
  const PathSubpath(this.points, {required this.closed});

  final List<double> points;
  final bool closed;

  int get length => points.length ~/ 2;
  double x(int i) => points[i * 2];
  double y(int i) => points[i * 2 + 1];
}

/// Parses SVG path data into closed contours, for **filling**.
///
/// Every subpath is treated as closed whether or not it ends in `z`, because a
/// *filled* path closes implicitly — which is what the fill rule sees. Subpaths
/// with fewer than three vertices are dropped for the same reason: they enclose
/// nothing. [parsePathSubpaths] is the entry point that keeps both.
List<PathContour> parsePath(String d, {double flatness = defaultFlatness}) => [
  for (final subpath in parsePathSubpaths(d, flatness: flatness))
    if (subpath.points.length >= 6) PathContour(subpath.points),
];

/// Parses SVG path data into flattened subpaths, for **stroking**.
///
/// Keeps what [parsePath] discards: subpaths too short to enclose an area, and
/// whether each ended in `z`.
List<PathSubpath> parsePathSubpaths(
  String d, {
  double flatness = defaultFlatness,
}) {
  final scanner = _Scanner(d);
  final subpaths = <PathSubpath>[];
  var current = <double>[];
  var closed = false;

  var x = 0.0, y = 0.0; // the current point
  var startX = 0.0, startY = 0.0; // the current subpath's origin

  void flush() {
    if (current.isNotEmpty) subpaths.add(PathSubpath(current, closed: closed));
  }

  void moveTo(double nx, double ny) {
    flush();
    current = <double>[nx, ny];
    closed = false;
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
      case 'C':
        final c1x = scanner.number(), c1y = scanner.number();
        final c2x = scanner.number(), c2y = scanner.number();
        final ex = scanner.number(), ey = scanner.number();
        // Every one of the three pairs is relative to the *current point*, not
        // to the pair before it — §8.3.6. Chaining them instead puts the
        // control points somewhere plausible and draws a wrong curve.
        final ox = relative ? x : 0.0;
        final oy = relative ? y : 0.0;
        _appendCubic(
          current,
          x0: x,
          y0: y,
          x1: ox + c1x,
          y1: oy + c1y,
          x2: ox + c2x,
          y2: oy + c2y,
          x3: ox + ex,
          y3: oy + ey,
          flatness: flatness,
        );
        x = ox + ex;
        y = oy + ey;
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
        // the same origin — so the subpath has to be pushed here. Leaving it
        // open welded the next subpath onto this one: `M0 0h10v10H0zh10v10`
        // came out as a single 75-unit contour instead of two squares.
        closed = true;
        flush();
        current = <double>[startX, startY];
        closed = false;
        x = startX;
        y = startY;
      default:
        throw UnsupportedSceneError(
          'path command "$command" is not implemented (in "$d")',
        );
    }
  }

  flush();
  return subpaths;
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

/// A `<rect>` with rounded corners, as one closed contour.
///
/// This is SVG 1.1 §9.2's **equivalent path**, followed step for step rather
/// than reinvented: moveto `(x+rx, y)`, a horizontal lineto, then an elliptical
/// arc with `x-axis-rotation` 0, `large-arc-flag` 0 and `sweep-flag` 1 into the
/// next side, four times round. Building it this way means the corners go
/// through the same F.6.5/F.6.6 code the arc commands use and inherit the same
/// stated tolerance — a second corner routine would be a second thing to be
/// wrong.
///
/// **[rx] and [ry] are the attributes, not the effective values**, because
/// §9.2's resolution is the part that gets skipped:
///
/// 1. neither given → both 0, and the result is [rectangleContour];
/// 2. only one given → **both** take that value (not "the other stays 0");
/// 3. `rx` is then clamped to `width/2` and `ry` to `height/2` — **separately**.
///
/// Step 3 is why `beam`'s eye is an ellipse and not a stadium. It is 1.5 × 2
/// with `rx="1"`: step 2 makes `ry` 1 as well, then `rx` clamps to 0.75 while
/// `ry` stays 1. Two different radii, and because each is exactly half its
/// side the straight edges have zero length. Hidden-state #21 predicted this
/// and `beam` is the first variant to reach it.
///
/// A negative radius is an error under §9.2, so it throws rather than being
/// taken as absolute — the arc code's own `abs()` (F.6.6 step 1) is about a
/// *path* radius and does not licence the same here.
PathContour roundedRectContour(
  double x,
  double y,
  double width,
  double height,
  double? rx,
  double? ry, {
  double flatness = defaultFlatness,
}) {
  if ((rx != null && rx < 0) || (ry != null && ry < 0)) {
    throw UnsupportedSceneError(
      'a negative corner radius (rx=$rx, ry=$ry) is an error under SVG 9.2',
    );
  }

  // §9.2 steps 1 and 2 — one given value fills both slots.
  var a = rx ?? ry ?? 0;
  var b = ry ?? rx ?? 0;

  // §9.2 step 3 — each against its own side. Collapsing this to one clamp is
  // the mutation the eye's ellipse exists to kill.
  if (a > width / 2) a = width / 2;
  if (b > height / 2) b = height / 2;

  if (a <= 0 || b <= 0) return rectangleContour(x, y, width, height);

  final points = <double>[x + a, y];
  void arcTo(double px, double py, double tx, double ty) => _appendArc(
    points,
    x0: px,
    y0: py,
    x1: tx,
    y1: ty,
    rx: a,
    ry: b,
    rotationDegrees: 0,
    largeArc: false,
    sweep: true,
    flatness: flatness,
  );

  final right = x + width, bottom = y + height;

  points.addAll([right - a, y]); // H
  arcTo(right - a, y, right, y + b);
  points.addAll([right, bottom - b]); // V
  arcTo(right, bottom - b, right - a, bottom);
  points.addAll([x + a, bottom]); // H
  arcTo(x + a, bottom, x, bottom - b);
  points.addAll([x, y + b]); // V
  arcTo(x, y + b, x + a, y);

  return PathContour(points);
}

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

/// Appends a cubic Bézier to [out], excluding its start point.
///
/// **The segment count is derived, not tuned.** Linear interpolation of a
/// function over a parameter step `h` errs by at most `h²·max|f''|/8`, so
/// splitting the curve into `n` uniform steps in `t` puts every chord within
/// `M/(8n²)` of it, where `M` bounds the second derivative. For a cubic,
/// `B''(t) = 6[(1−t)(P₀−2P₁+P₂) + t(P₁−2P₂+P₃)]` is linear in `t`, so its
/// largest magnitude is at one end or the other and `M` is exact rather than
/// estimated. Setting `M/(8n²) ≤ ε` gives the `n` below.
///
/// Uniform in the parameter is also what makes this **deterministic**: an
/// adaptive subdivision branches on a float comparison, and two platforms that
/// disagree in the last ulp produce different vertex *counts* — a difference
/// invariant 4 cannot absorb. Here `n` comes from one square root and one
/// `ceil`.
///
/// `beam`'s open mouth, `c2 1 4 1 6 0`, has both second-difference vectors of
/// length exactly 1, so `M` is 6 and `n` is 56.
void _appendCubic(
  List<double> out, {
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  required double x3,
  required double y3,
  required double flatness,
}) {
  double hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
  final second =
      6 *
      math.max(
        hypot(x0 - 2 * x1 + x2, y0 - 2 * y1 + y2),
        hypot(x1 - 2 * x2 + x3, y1 - 2 * y2 + y3),
      );
  // A curve with no second derivative is a straight line: one chord is exact,
  // and the square root below would be zero anyway. Written as its own case so
  // the collinear input cannot depend on `ceil(0)` happening to be right.
  final segments = second <= 0
      ? 1
      : math.max(1, math.sqrt(second / (8 * flatness)).ceil());

  for (var i = 1; i <= segments; i++) {
    final t = i / segments;
    final u = 1 - t;
    final b0 = u * u * u;
    final b1 = 3 * u * u * t;
    final b2 = 3 * u * t * t;
    final b3 = t * t * t;
    out.addAll([
      b0 * x0 + b1 * x1 + b2 * x2 + b3 * x3,
      b0 * y0 + b1 * y1 + b2 * y2 + b3 * y3,
    ]);
  }
}

/// The `stroke-linecap` values this rasterizer reads.
///
/// SVG 1.1 §11.4 defines three; `square` is absent because no version in scope
/// writes one and a shape nothing produces is untested arithmetic. `butt` is
/// the initial value and what `bauhaus`'s `<line>` takes; `beam`'s open mouth
/// is the only element in the six that asks for `round`.
enum StrokeCap { butt, round }

/// The outline of a stroked path, as contours to fill under the **nonzero**
/// rule.
///
/// **This returns a pile of overlapping pieces, not one polygon, and that is
/// the design.** A quad per segment and a disc per joint, all wound the same
/// way, union exactly under nonzero — so there is no offset-curve arithmetic
/// to get wrong at a joint, and no self-intersection to resolve. The integrator
/// already fills by winding number, so the union costs nothing extra.
///
/// **Round joins for the interior, and that is not an approximation of
/// `miter`.** The initial `stroke-linejoin` is `miter`, and the only stroked
/// path in the six is a *flattened curve* — so a browser strokes the curve
/// itself, whose true offset is the Minkowski sum with a disc, which is what
/// discs at the joints produce. Mitering our own chords would reproduce an
/// artefact of the flattening rather than the drawing. The two answers differ
/// by `(w/2)(1/cos(θ/2) − 1)` at a joint turning θ, and `beam`'s mouth turns
/// 0.93 rad over 56 chords: **1.7e-5 user units**, four orders below the
/// ≤1/255 coverage bar. Valid **as long as every stroked path is a flattened
/// smooth curve**; a real corner in a `d` makes the difference visible and
/// wants a genuine miter.
///
/// §11.4's degenerate cases are three, and they are not the same case:
///
/// * a **single moveto** is never stroked;
/// * a **zero-length subpath** is not stroked under `butt` but *is* under
///   `round`, "producing … a circle centered at the given point" — the spec's
///   own example of one is `M 40,40 c 0,0 0,0 0,0`, a cubic;
/// * a **zero width** paints nothing.
List<PathContour> strokePathOutline(
  List<PathSubpath> subpaths, {
  required double width,
  required StrokeCap cap,
  double flatness = defaultFlatness,
}) {
  if (width <= 0) return const [];
  final radius = width / 2;
  final out = <PathContour>[];

  // **Every piece must wind the same way**, or the nonzero rule subtracts
  // instead of unioning and each joint becomes a hole. The quads are always
  // negatively oriented — that is direction-independent, because
  // [strokeSegmentContour] lists the `+n` side before the `−n` side whichever
  // way the segment runs — while [flattenCircle] sweeps θ upwards and comes out
  // positive. So the discs are reversed to match. Measured: without this a
  // straight round-capped stroke loses exactly the two cap discs.
  PathContour disc(double cx, double cy) {
    final circle = flattenCircle(cx, cy, radius, flatness: flatness);
    final points = List<double>.filled(circle.points.length, 0);
    for (var i = 0; i < circle.length; i++) {
      final j = circle.length - 1 - i;
      points[i * 2] = circle.x(j);
      points[i * 2 + 1] = circle.y(j);
    }
    return PathContour(points);
  }

  for (final subpath in subpaths) {
    // **No duplicate-point cleanup here, and that is a measured decision.**
    // Two passes were written and both were deleted rather than tested, for
    // the same reason: the nonzero union makes them invisible.
    //
    // * Removing *consecutive* duplicates. Its stated purpose was to stop a
    //   zero-length segment normalising into `NaN` — but [strokeSegmentContour]
    //   already returns `null` for `length == 0`, one level down.
    // * Removing a closed subpath's repeated origin (`M0 0h10v10H0V0z`, where
    //   the `V0` arrives back before the `z`). Without it the wrap-around
    //   segment is zero-length — a `null` quad — and the joint disc lands on a
    //   point another disc already covers. Two coincident discs wind to −2,
    //   and nonzero fills anything that is not zero.
    //
    // Both were mutation-tested by deletion and **survived**, which is the
    // third question a surviving mutant asks: not "is the test weak" or "is the
    // input degenerate", but *is this code reachable at all*. It is not. Same
    // disposition as #40's redundant gradient clamps.
    //
    // `raster_path_test.dart` still constructs the redundant-origin form and
    // asserts it agrees with the plain one — a regression pin on the output,
    // now that there is no branch left to pin.
    final points = subpath.points;

    final count = points.length ~/ 2;
    if (count == 0) continue;

    if (count == 1) {
      // Zero length. A single moveto reaches here too, and the two are told
      // apart by the source: a subpath that never moved has one point and no
      // segment ever existed, while `M40 40c0 0 0 0 0 0` collapsed to one.
      if (cap == StrokeCap.round && subpath.length > 1) {
        out.add(disc(points[0], points[1]));
      }
      continue;
    }

    final segments = subpath.closed ? count : count - 1;
    for (var i = 0; i < segments; i++) {
      final j = (i + 1) % count;
      final quad = strokeSegmentContour(
        points[i * 2],
        points[i * 2 + 1],
        points[j * 2],
        points[j * 2 + 1],
        width,
      );
      if (quad != null) out.add(quad);
    }

    // A joint at every interior vertex — and at the seam too when `z` closed
    // the subpath, which is the whole difference between a join and two caps.
    final firstJoint = subpath.closed ? 0 : 1;
    final lastJoint = subpath.closed ? count - 1 : count - 2;
    for (var i = firstJoint; i <= lastJoint; i++) {
      out.add(disc(points[i * 2], points[i * 2 + 1]));
    }

    if (!subpath.closed && cap == StrokeCap.round) {
      out.add(disc(points[0], points[1]));
      out.add(disc(points[(count - 1) * 2], points[(count - 1) * 2 + 1]));
    }
  }

  return out;
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
