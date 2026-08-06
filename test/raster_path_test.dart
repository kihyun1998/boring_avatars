import 'dart:math' as math;

import 'package:boring_avatars/src/raster/path.dart';
import 'package:boring_avatars/src/raster/raster.dart';
import 'package:flutter_test/flutter_test.dart';

/// The path parser and the polygon integrator, checked against numbers that
/// exist independently of this package.
///
/// A rasterizer compared only to its own output is the "golden that agrees with
/// itself" trap. The area of a disc is πr² whatever anyone implements, so every
/// area assertion here is an outside opinion — and the flattening error is
/// *predicted* rather than measured after the fact: an inscribed polygon loses
/// about `(2/3)·ε·L` of area against the curve it replaces, so the bar is set
/// at 0.05 and the shape must land **under** the true area, never over.
void main() {
  const pi = math.pi;

  /// Total coverage of one path over a canvas big enough to contain it.
  double areaOf(String d, {int size = 120}) {
    final coverage = polygonCoverage(
      width: size,
      height: size,
      polygon: RasterPolygon(parsePath(d), SolidPaint.hex('#000000')),
    );
    var total = 0.0;
    for (final c in coverage) {
      total += c;
    }
    return total;
  }

  ({double minX, double minY, double maxX, double maxY}) boundsOf(String d) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final contour in parsePath(d)) {
      for (var i = 0; i < contour.length; i++) {
        minX = math.min(minX, contour.x(i));
        maxX = math.max(maxX, contour.x(i));
        minY = math.min(minY, contour.y(i));
        maxY = math.max(maxY, contour.y(i));
      }
    }
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  group('arc flags are characters, not numbers', () {
    // `a32 32 0 10-64 0` packs large-arc=1 and sweep=0 against the `-64` that
    // follows. A tokeniser that scans numbers uniformly reads `10` as ten and
    // then takes `-64` as the sweep flag — and upstream writes this form, so
    // it is not a hypothetical.
    const top = 'M77 45a32 32 0 10-64 0h64z';
    const bottom = 'M77 45a32 32 0 11-64 0h64z';

    // The chord endpoints are *vertices*, so they land exactly. The apex is
    // only ever approached — the nearest vertex sits up to one sagitta inside
    // it, which is the flattening tolerance and nothing more. Asserting the
    // two the same way would either over-constrain the curve or under-constrain
    // the endpoints.
    void expectApex(double actual, double apex) {
      expect(actual, closeTo(apex, defaultFlatness));
      expect(
        (actual - apex).abs(),
        greaterThan(0),
        reason: 'an inscribed polygon does not reach the apex exactly',
      );
    }

    test('the packed pair parses as two flags', () {
      final b = boundsOf(top);
      expect(b.minX, closeTo(13, 1e-9));
      expect(b.maxX, closeTo(77, 1e-9));
      expect(b.maxY, closeTo(45, 1e-9));
      expectApex(b.minY, 13);
    });

    test('flipping only the sweep character mirrors the shape', () {
      // These two `d` strings differ in exactly one byte. If the flags were
      // being consumed as numbers the two would not be mirror images.
      final t = boundsOf(top);
      final b = boundsOf(bottom);
      expect(b.minX, closeTo(t.minX, 1e-9));
      expect(b.maxX, closeTo(t.maxX, 1e-9));
      expect(b.minY, closeTo(45, 1e-9));
      expectApex(b.maxY, 77);
      expect(areaOf(bottom), closeTo(areaOf(top), 1e-9));
    });

    test('an unseparated flag pair is rejected when it is not 0 or 1', () {
      expect(
        () => parsePath('M0 0a10 10 0 27 10 0z'),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });
  });

  group('the three ring radii come out as the half-discs upstream drew', () {
    // Each `d` is a closed half-disc: the arc, then the chord back. Its area is
    // πr²/2 and nothing about this package decides that.
    const arcs = <String, double>{
      'M83 45a38 38 0 00-76 0h76z': 38,
      'M83 45a38 38 0 01-76 0h76z': 38,
      'M77 45a32 32 0 10-64 0h64z': 32,
      'M77 45a32 32 0 11-64 0h64z': 32,
      'M71 45a26 26 0 00-52 0h52z': 26,
      'M71 45a26 26 0 01-52 0h52z': 26,
    };

    arcs.forEach((d, r) {
      test('r=$r — ${d.substring(d.indexOf("a"))}', () {
        final exact = pi * r * r / 2;
        final area = areaOf(d);
        expect(
          area,
          closeTo(exact, 0.05),
          reason: 'half-disc of radius $r: expected $exact, measured $area',
        );
        expect(
          area,
          lessThan(exact),
          reason: 'a polygon inscribed in the arc cannot exceed it',
        );
      });
    });

    test('a chord that rounds *past* the diameter still parses', () {
      // The clamp on F.6.5's square root is not defensive programming — this
      // input reaches it. The chord equals the diameter at an angle, so lambda
      // computes as exactly 1.0 and F.6.6 does not fire, while the radicand
      // computed a different way lands at -1.3e-16. Unclamped, `sqrt` returns
      // NaN, `_segmentsFor` then throws "Infinity or NaN toInt", and a path
      // that a browser draws without complaint takes the whole render down.
      //
      // Found by searching arc parameters, because a mutation removing the
      // clamp survived the entire suite: `ring`'s own arcs are horizontal, and
      // a horizontal chord makes the radicand exactly zero every time.
      const d =
          'M0 0a0.14285714285714285 0.14285714285714285 0 0 0 '
          '0.2853294730442844 0.014823794166658652z';
      for (final contour in parsePath(d)) {
        for (final value in contour.points) {
          expect(value.isFinite, isTrue, reason: d);
        }
      }
    });

    test('the lambda-is-exactly-one case does not become NaN', () {
      // Every one of these arcs has a chord equal to its diameter, so SVG's
      // F.6.5 centre formula takes the square root of a quantity that is zero
      // in exact arithmetic and can be a few ulps negative in float64. Without
      // the clamp every vertex is NaN — which rasterises as nothing at all,
      // silently.
      for (final d in arcs.keys) {
        for (final contour in parsePath(d)) {
          for (final value in contour.points) {
            expect(value.isFinite, isTrue, reason: d);
          }
        }
      }
    });

    test('sweep 0 is the upper half and sweep 1 the lower', () {
      // Which half is which decides the whole colour layout, and the sweep flag
      // alone settles it. SVG 1.1: sweep-flag 1 draws in the "positive-angle"
      // direction, and because y grows downwards that is clockwise on screen.
      // These arcs run right to left, so the positive-angle one passes through
      // six o'clock — the *lower* half.
      final up = boundsOf('M83 45a38 38 0 00-76 0h76z');
      final down = boundsOf('M83 45a38 38 0 01-76 0h76z');
      expect(up.maxY, closeTo(45, 1e-9));
      expect(up.minY, closeTo(7, defaultFlatness));
      expect(down.minY, closeTo(45, 1e-9));
      expect(down.maxY, closeTo(83, defaultFlatness));
    });
  });

  group('straight-line commands', () {
    test('a rect written as a path is integrated exactly', () {
      // Mixed relative and absolute — `h`, `v`, then `H`. The edges land on
      // integers, so the y-quantisation contributes nothing and the answer is
      // exact rather than close.
      expect(areaOf('M0 0h90v45H0z'), closeTo(90 * 45, 1e-9));
      expect(areaOf('M0 45h90v45H0z'), closeTo(90 * 45, 1e-9));
    });

    test('a subpath is closed for filling whether or not it says z', () {
      expect(areaOf('M0 0h10v10H0'), closeTo(100, 1e-9));
    });

    test('a subpath after z is its own contour, not welded onto the last', () {
      // `z` ends a subpath; what follows starts a new one from the same origin.
      // Leaving the contour open joined the two into a single 75-unit polygon
      // instead of two 100-unit squares. Latent at v1.6.1 — across the 18
      // distinct `d` strings in all 600 renders, `z` is always the last
      // command — so nothing in the corpus could have caught it.
      // The second subpath here is the triangle (0,0)-(10,0)-(10,10), which
      // sits inside the square and winds the same way — so the *area* is still
      // 100 under the nonzero rule. The contour **count** is what separates the
      // two readings, and welding them gave 75.
      expect(parsePath('M0 0h10v10H0zh10v10'), hasLength(2));
      expect(areaOf('M0 0h10v10H0zh10v10'), closeTo(100, 1e-9));
      // Two disjoint squares, where the area separates them too.
      expect(areaOf('M0 0h10v10H0zM20 0h10v10H20z'), closeTo(200, 1e-9));
    });

    test('a repeated moveto pair continues as a lineto', () {
      // Per the path grammar, `M0 0 10 0 10 10 0 10` is a moveto followed by
      // three linetos, not four movetos.
      expect(areaOf('M0 0 10 0 10 10 0 10z'), closeTo(100, 1e-9));
    });
  });

  group('the fill rule is nonzero, which is what SVG defaults to', () {
    // None of the six variants writes `fill-rule`, so the default governs. The
    // two rules disagree precisely here, and only here.
    const sameDirection = 'M0 0h10v10H0zM3 3h4v4H3z';
    const opposedDirection = 'M0 0h10v10H0zM3 3v4h4V3z';

    test('a hole wound the same way is filled, not punched', () {
      expect(areaOf(sameDirection), closeTo(100, 1e-9));
    });

    test('a hole wound the other way is punched', () {
      expect(areaOf(opposedDirection), closeTo(100 - 16, 1e-9));
    });
  });

  group('the large-arc flag chooses which of the two arcs is drawn', () {
    // Every arc in the whole upstream corpus has a chord equal to its diameter,
    // which makes F.6.5's centre offset exactly zero — so `sign = largeArc !=
    // sweep` multiplies a zero and the flag has no effect. Mutating the sign
    // rule survived the entire suite. Nothing upstream will ever exercise it;
    // the case is constructed instead, because the branch exists.
    //
    // Chord 20 on radius 15, so the two arcs are genuinely different: the minor
    // segment and the major one. Both areas are circular-segment arithmetic —
    // θ = 2·asin(10/15), minor = r²(θ − sin θ)/2 — and Chrome draws the same
    // four shapes (checked: minor below, minor above, major below, major above).
    const theta = 1.4594553124539327; // 2·asin(2/3)
    final minor = 225 * (theta - math.sin(theta)) / 2;
    final major = pi * 225 - minor;

    ({double area, double minY, double maxY}) measure(String flags) {
      final d = 'M30 40a15 15 0 $flags 20 0z';
      final b = boundsOf(d);
      return (area: areaOf(d), minY: b.minY, maxY: b.maxY);
    }

    test('flag 0 draws the minor segment and flag 1 the major one', () {
      expect(measure('0 0').area, closeTo(minor, 0.05));
      expect(measure('0 1').area, closeTo(minor, 0.05));
      expect(measure('1 0').area, closeTo(major, 0.05));
      expect(measure('1 1').area, closeTo(major, 0.05));
      // Inscribed either way.
      expect(measure('1 0').area, lessThan(major));
    });

    test('and the sweep flag still decides which side of the chord', () {
      expect(measure('0 0').minY, closeTo(40, 1e-9), reason: 'minor, below');
      expect(measure('0 1').maxY, closeTo(40, 1e-9), reason: 'minor, above');
      expect(measure('1 0').minY, closeTo(40, 1e-9), reason: 'major, below');
      expect(measure('1 1').maxY, closeTo(40, 1e-9), reason: 'major, above');
    });
  });

  group('out-of-range radii are corrected, not rejected (SVG F.6.6)', () {
    // rx=ry=1 cannot reach across a chord of 10, so the spec scales both up by
    // sqrt(lambda) until it just can — here to 5, making a half-disc.
    const d = 'M10 10a1 1 0 0 0 10 0z';

    test('both radii scale up until the ellipse fits the chord', () {
      // Left to right with sweep 0, so this one bulges *downwards* — the
      // mirror of `ring`'s arcs, which run right to left.
      final b = boundsOf(d);
      expect(b.minX, closeTo(10, 1e-9));
      expect(b.maxX, closeTo(20, 1e-9));
      expect(b.minY, closeTo(10, 1e-9));
      expect(b.maxY, closeTo(15, defaultFlatness));
    });

    test('and the corrected arc has the area of the radius it grew to', () {
      expect(areaOf(d), closeTo(pi * 25 / 2, 0.02));
    });
  });

  group('degenerate and unimplemented input', () {
    test('a zero radius degenerates to a straight line, per the spec', () {
      expect(areaOf('M10 10a0 5 0 0 0 10 0z'), closeTo(0, 1e-9));
    });

    test('a quadratic still throws — no variant of the six writes one', () {
      // This group used to hold the same assertion for a cubic, with a comment
      // saying `beam` would name itself when it arrived. It has arrived, so
      // that test was replaced by the cubic group below rather than deleted:
      // the guard it was protecting is still here, one command narrower.
      expect(
        () => parsePath('M0 0q1 1 2 2z'),
        throwsA(
          isA<UnsupportedSceneError>().having(
            (e) => e.message,
            'message',
            contains('"q"'),
          ),
        ),
      );
    });

    test('path data that does not start with a command throws', () {
      expect(
        () => parsePath('10 20 30'),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('a number after z throws instead of spinning forever', () {
      // `closepath` takes no arguments, so the repeat rule that turns a second
      // coordinate pair into another lineto has nothing to consume here. The
      // failure mode without the guard is not a wrong picture — it is a hang.
      expect(
        () => parsePath('M0 0h10z 5 5').toString(),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });
  });

  group('cubics, which `beam` brings and nothing else in the six uses', () {
    /// The cubic itself, evaluated from Bernstein's polynomial — the
    /// *definition*, not our flattener. Every assertion below compares the
    /// output to this, so none of them is the port marking its own homework.
    (double, double) bezier(
      List<(double, double)> p,
      double t,
    ) {
      final u = 1 - t;
      final b0 = u * u * u;
      final b1 = 3 * u * u * t;
      final b2 = 3 * u * t * t;
      final b3 = t * t * t;
      return (
        b0 * p[0].$1 + b1 * p[1].$1 + b2 * p[2].$1 + b3 * p[3].$1,
        b0 * p[0].$2 + b1 * p[1].$2 + b2 * p[2].$2 + b3 * p[3].$2,
      );
    }

    // `beam`'s open mouth at mouthSpread 0, verbatim from avatar-beam.js:95.
    const mouth = 'M15 19c2 1 4 1 6 0';
    const mouthPoints = <(double, double)>[
      (15, 19),
      (17, 20),
      (19, 20),
      (21, 19),
    ];

    test('the curve ends exactly on its last control point', () {
      final c = parsePath(mouth).single;
      final last = c.length - 1;
      expect(c.x(last), closeTo(21, 1e-12));
      expect(c.y(last), closeTo(19, 1e-12));
    });

    test('every vertex lies on the curve, to float64 precision', () {
      // Uniform in the parameter, so vertex i is exactly B(i/n) — which makes
      // this an equality check against Bernstein rather than a proximity one.
      final c = parsePath(mouth).single;
      final n = c.length - 1;
      for (var i = 0; i <= n; i++) {
        final (x, y) = bezier(mouthPoints, i / n);
        expect(c.x(i), closeTo(x, 1e-12), reason: 'vertex $i');
        expect(c.y(i), closeTo(y, 1e-12), reason: 'vertex $i');
      }
    });

    test('no chord falls further from the curve than the declared flatness', () {
      // The same bar the arcs are held to, measured the same way: sample the
      // true curve densely and take the worst distance to the polyline.
      final c = parsePath(mouth).single;
      var worst = 0.0;
      for (var s = 0; s <= 4000; s++) {
        final (x, y) = bezier(mouthPoints, s / 4000);
        var best = double.infinity;
        for (var i = 0; i < c.length - 1; i++) {
          best = math.min(
            best,
            _distanceToSegment(x, y, c.x(i), c.y(i), c.x(i + 1), c.y(i + 1)),
          );
        }
        worst = math.max(worst, best);
      }
      expect(worst, lessThanOrEqualTo(defaultFlatness));
    });

    test('a cubic whose control points are collinear is a straight line', () {
      // The degenerate case a flattener gets wrong by dividing by a curvature
      // that is zero — here the second-derivative bound is exactly 0, so the
      // segment count cannot come from `ceil(sqrt(0/…))` by luck.
      //
      // Closed with two straight sides into a right triangle of legs 3, whose
      // area is 4.5 and is not this package's opinion. If the cubic bulged at
      // all the area would move.
      const d = 'M0 0c1 1 2 2 3 3L0 3z';
      final c = parsePath(d).single;
      for (var i = 0; i < c.length; i++) {
        if (c.x(i) == 0 && c.y(i) == 3) continue; // the L, not the curve
        expect(c.y(i), closeTo(c.x(i), 1e-12), reason: 'vertex $i');
      }
      expect(areaOf(d), closeTo(4.5, 1e-9));
    });

    test('a straight cubic is one chord, not a hundred', () {
      // The derived count has to *fall* as the curve flattens, or the tolerance
      // is not what decides it. Collinear is the limit, and there the answer is
      // a single segment.
      final straight = parsePath('M0 0c1 1 2 2 3 3L0 3z').single;
      final curved = parsePath('M15 19c2 1 4 1 6 0L15 19z').single;
      expect(straight.length, 3, reason: 'moveto, the chord, the L');
      expect(curved.length, greaterThan(50));
    });

    test('every vertex lies inside the control hull, which is a theorem', () {
      // A Bézier never leaves the convex hull of its control points. The mouth
      // curve's hull is the box x∈[15,21], y∈[19,20], so this is exact and
      // needs nothing from the implementation.
      final c = parsePath(mouth).single;
      for (var i = 0; i < c.length; i++) {
        expect(c.x(i), inInclusiveRange(15 - 1e-12, 21 + 1e-12));
        expect(c.y(i), inInclusiveRange(19 - 1e-12, 20 + 1e-12));
      }
    });

    test('relative and absolute forms describe the same curve', () {
      final relative = parsePath(mouth).single;
      final absolute = parsePath('M15 19C17 20 19 20 21 19').single;
      expect(relative.points.length, absolute.points.length);
      for (var i = 0; i < relative.points.length; i++) {
        expect(relative.points[i], closeTo(absolute.points[i], 1e-12));
      }
    });

    test('a repeated coordinate run continues the same command', () {
      // The grammar lets `c` take several sextuples in a row. No upstream
      // version writes one, so this is constructed — but the repeat rule is
      // shared with every other command and a cubic that silently consumed
      // only the first six numbers would be a wrong picture, not a throw.
      final c = parsePath('M0 0c1 1 2 2 3 3 1 1 2 2 3 3').single;
      final last = c.length - 1;
      expect(c.x(last), closeTo(6, 1e-12));
      expect(c.y(last), closeTo(6, 1e-12));
    });
  });

  group('a stroked path, which `beam`\'s open mouth brings', () {
    /// Coverage of a set of contours filled together under the nonzero rule.
    ///
    /// The stroke outline is deliberately *not* one polygon — it is a pile of
    /// overlapping quads and discs that nonzero winding unions. Measuring their
    /// combined coverage is therefore the only honest way to ask its area.
    double area(List<PathContour> contours, {int size = 120}) {
      final coverage = polygonCoverage(
        width: size,
        height: size,
        polygon: RasterPolygon(contours, SolidPaint.hex('#000000')),
      );
      var total = 0.0;
      for (final c in coverage) {
        total += c;
      }
      return total;
    }

    // The area of everything within distance ρ of a simple curve of length L is
    // `L·2ρ + πρ²` — the straight part swept, plus one full disc's worth from
    // the two ends. It holds while the curve does not double back on itself and
    // its curvature radius stays above ρ, which is true of every stroke in the
    // six. Nothing about this package decides it.
    double sausage(double length, double width) =>
        length * width + pi * width * width / 4;

    test('a straight round-capped stroke is the swept box plus two half-discs',
        () {
      final outline = strokePathOutline(
        parsePathSubpaths('M20 60h40'),
        width: 6,
        cap: StrokeCap.round,
      );
      expect(area(outline), closeTo(sausage(40, 6), 0.05));
    });

    test('butt caps stop at the endpoints and round caps do not', () {
      // The whole difference between the two is one disc, and it is visible in
      // both the area and the bounding box.
      final butt = strokePathOutline(
        parsePathSubpaths('M20 60h40'),
        width: 6,
        cap: StrokeCap.butt,
      );
      expect(area(butt), closeTo(40 * 6, 0.05));

      var minX = double.infinity;
      for (final c in strokePathOutline(
        parsePathSubpaths('M20 60h40'),
        width: 6,
        cap: StrokeCap.round,
      )) {
        for (var i = 0; i < c.length; i++) {
          minX = math.min(minX, c.x(i));
        }
      }
      // The cap is a flattened circle, so its leftmost vertex sits up to one
      // sagitta inside the true radius — same rule as the arc apexes above,
      // and the same bar. Butt would leave it at 20.
      expect(minX, closeTo(17, defaultFlatness));
      expect(minX, greaterThan(17), reason: 'inscribed, never beyond');
    });

    test('a curved stroke is the same formula, on the arc length', () {
      // A half-circle of radius 20 has length 20π exactly, so the expected area
      // needs no measurement of ours at all.
      final outline = strokePathOutline(
        parsePathSubpaths('M40 60a20 20 0 0 0 40 0'),
        width: 4,
        cap: StrokeCap.round,
      );
      expect(area(outline), closeTo(sausage(20 * pi, 4), 0.1));
    });

    test('`beam`\'s own mouth comes out at its own arc length', () {
      // Simpson's rule on |B'(t)|, which is the *definition* of arc length and
      // shares no code with the flattener.
      const p = <(double, double)>[(15, 19), (17, 20), (19, 20), (21, 19)];
      double speed(double t) {
        final u = 1 - t;
        final dx = 3 * u * u * (p[1].$1 - p[0].$1) +
            6 * u * t * (p[2].$1 - p[1].$1) +
            3 * t * t * (p[3].$1 - p[2].$1);
        final dy = 3 * u * u * (p[1].$2 - p[0].$2) +
            6 * u * t * (p[2].$2 - p[1].$2) +
            3 * t * t * (p[3].$2 - p[2].$2);
        return math.sqrt(dx * dx + dy * dy);
      }

      const n = 10000;
      var length = speed(0) + speed(1);
      for (var i = 1; i < n; i++) {
        length += speed(i / n) * (i.isOdd ? 4 : 2);
      }
      length *= 1 / (3 * n);

      final outline = strokePathOutline(
        parsePathSubpaths('M15 19c2 1 4 1 6 0'),
        width: 1,
        cap: StrokeCap.round,
      );
      expect(area(outline, size: 40), closeTo(sausage(length, 1), 0.02));
    });

    test('a zero-length subpath is a circle under round, nothing under butt',
        () {
      // 11.4, verbatim: such a subpath "shall not be stroked if stroke-linecap
      // has a value of butt but shall be stroked if it has a value of round or
      // square, producing respectively a circle or a square". The spec even
      // lists `M 40,40 c 0,0 0,0 0,0` as an example, which is a *cubic* — so
      // this is reachable from the very command `beam` introduces.
      final round = strokePathOutline(
        parsePathSubpaths('M40 40c0 0 0 0 0 0'),
        width: 8,
        cap: StrokeCap.round,
      );
      expect(area(round), closeTo(pi * 16, 0.05));

      final butt = strokePathOutline(
        parsePathSubpaths('M40 40c0 0 0 0 0 0'),
        width: 8,
        cap: StrokeCap.butt,
      );
      expect(area(butt), closeTo(0, 1e-9));
    });

    test('a single moveto is never stroked, whatever the cap', () {
      // 11.4: "A subpath consisting of a single moveto shall not be stroked."
      // Distinct from the zero-length case above, which *is* stroked under
      // round — collapsing the two paints a disc the spec says is not there.
      for (final cap in StrokeCap.values) {
        expect(
          area(strokePathOutline(
            parsePathSubpaths('M40 40'),
            width: 8,
            cap: cap,
          )),
          closeTo(0, 1e-9),
          reason: '$cap',
        );
      }
    });

    test('a zero width paints nothing, per 11.4', () {
      expect(
        area(strokePathOutline(
          parsePathSubpaths('M20 60h40'),
          width: 0,
          cap: StrokeCap.round,
        )),
        closeTo(0, 1e-9),
      );
    });

    test('the outline carries no NaN, whatever the input', () {
      // A normalised direction vector over a zero-length segment is the NaN
      // factory hidden-state #47 records, and the scanline integrator carries
      // NaN *silently* rather than throwing.
      for (final d in [
        'M20 60h40',
        'M40 40c0 0 0 0 0 0',
        'M15 19c2 1 4 1 6 0',
        'M10 10L10 10L20 20',
        'M0 0h10v10H0z',
      ]) {
        for (final c in strokePathOutline(
          parsePathSubpaths(d),
          width: 2,
          cap: StrokeCap.round,
        )) {
          for (final v in c.points) {
            expect(v.isFinite, isTrue, reason: d);
          }
        }
      }
    });

    test('a closed subpath joins rather than capping', () {
      // `z` makes the start and the end the same point, so an open stroke would
      // put two caps there and a closed one a single join. For a right-angled
      // corner under round joins the difference is a quarter disc.
      final closed = strokePathOutline(
        parsePathSubpaths('M30 30h30v30H30z'),
        width: 4,
        cap: StrokeCap.round,
      );
      // The stroked region is everything within 2 of the outline. Outside, a
      // 34-square with corner radius 2: 34² − (4−π)·2·2. Inside, a sharp
      // 26-square: 26². The difference is 464 + 4π ≈ 476.6 — and note it is
      // *not* perimeter × width (480), because a corner's outer wedge and its
      // inner overlap do not cancel the way a circle's do.
      expect(area(closed), closeTo(464 + 4 * pi, 0.15));
    });
  });

  group('a rounded rect clamps rx and ry independently (SVG 9.2)', () {
    /// Coverage of one contour, the same way [areaOf] measures a path.
    double area(PathContour contour, {int size = 120}) {
      final coverage = polygonCoverage(
        width: size,
        height: size,
        polygon: RasterPolygon([contour], SolidPaint.hex('#000000')),
      );
      var total = 0.0;
      for (final c in coverage) {
        total += c;
      }
      return total;
    }

    // Each corner replaces a square of rx·ry with a quarter ellipse, so the
    // shape loses (4 − π)·rx·ry in total. That is arithmetic, not a rendering
    // opinion, and it distinguishes elliptical corners from circular ones.
    double exactArea(double w, double h, double rx, double ry) =>
        w * h - (4 - pi) * rx * ry;

    test('no radius at all is the plain rectangle', () {
      final c = roundedRectContour(10, 10, 40, 20, null, null);
      expect(area(c), closeTo(40 * 20, 1e-9));
      expect(c.length, 4, reason: 'four corners, no arcs');
    });

    test('rx alone sets ry too, and then each clamps to its own half', () {
      // `beam`'s eye, verbatim: 1.5 x 2 with rx=1. 9.2 sets ry to rx, then
      // clamps rx to width/2 = 0.75 and ry to height/2 = 1 — **different
      // numbers**. The corners are elliptical, and since 2·rx is the full width
      // and 2·ry the full height, the straight edges vanish: the eye is an
      // ellipse. Hidden-state #21, live for the first time.
      final c = roundedRectContour(10, 10, 1.5, 2, 1, null);
      expect(area(c, size: 40), closeTo(pi * 0.75 * 1, 0.02));
    });

    test('and a single clamped radius would give a visibly different shape', () {
      // The mutation this exists for: clamping both to min(w, h)/2 = 0.75.
      // That is a circle-cornered rect of area 2.517 where the ellipse is
      // 2.356 — 7% apart, far outside the flattening error.
      final circular = exactArea(1.5, 2, 0.75, 0.75);
      final elliptical = pi * 0.75 * 1;
      expect((circular - elliptical).abs(), greaterThan(0.15));
      expect(area(roundedRectContour(10, 10, 1.5, 2, 1, null), size: 40),
          isNot(closeTo(circular, 0.05)));
    });

    test('a radius larger than the box becomes the inscribed ellipse', () {
      // `beam`'s wrapper at isCircle: 36 x 36 with rx=36, which clamps to 18 —
      // a circle. Upstream turns a rect into a circle exactly this way, and
      // `pixel` does the same to its mask with rx=160 on 80.
      final c = roundedRectContour(0, 0, 36, 36, 36, null);
      expect(area(c, size: 60), closeTo(pi * 18 * 18, 0.05));
    });

    test('an ordinary radius loses exactly the four corner slivers', () {
      // `beam`'s wrapper when it is not a circle: rx = SIZE/6 = 6 on 36 x 36.
      final c = roundedRectContour(0, 0, 36, 36, 6, null);
      expect(area(c, size: 60), closeTo(exactArea(36, 36, 6, 6), 0.05));
    });

    test('rx and ry given separately are both honoured', () {
      final c = roundedRectContour(10, 10, 40, 30, 8, 3);
      expect(area(c), closeTo(exactArea(40, 30, 8, 3), 0.05));
    });

    test('the shape never leaves its own box', () {
      for (final r in <double>[0.5, 6, 18, 100]) {
        final c = roundedRectContour(10, 20, 36, 36, r, null);
        for (var i = 0; i < c.length; i++) {
          expect(c.x(i), inInclusiveRange(10 - 1e-9, 46 + 1e-9));
          expect(c.y(i), inInclusiveRange(20 - 1e-9, 56 + 1e-9));
        }
      }
    });

    test('a negative radius is an error, not silently absolute', () {
      // 9.2: "A negative value is an error". Taking `abs()` — which is what the
      // arc code legitimately does for its own radii, F.6.6 step 1 — would draw
      // a rounded corner where the document is invalid.
      expect(
        () => roundedRectContour(0, 0, 10, 10, -2, null),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });
  });

  group('the flattening tolerance is a stated number, not a feeling', () {
    /// The largest distance any chord of [contour] falls inside a circle of
    /// radius [r] centred at (cx, cy).
    double worstSagitta(PathContour contour, double cx, double cy, double r) {
      var worst = 0.0;
      for (var i = 0; i < contour.length; i++) {
        final j = (i + 1) % contour.length;
        final mx = (contour.x(i) + contour.x(j)) / 2;
        final my = (contour.y(i) + contour.y(j)) / 2;
        final d = math.sqrt((mx - cx) * (mx - cx) + (my - cy) * (my - cy));
        worst = math.max(worst, r - d);
      }
      return worst;
    }

    test('every vertex lies on the circle, to float64 precision', () {
      final c = flattenCircle(45, 45, 23);
      for (var i = 0; i < c.length; i++) {
        final dx = c.x(i) - 45, dy = c.y(i) - 45;
        expect(math.sqrt(dx * dx + dy * dy), closeTo(23, 1e-12));
      }
    });

    test('no chord falls further inside than the declared flatness', () {
      for (final r in <double>[23, 26, 32, 38, 45]) {
        final c = flattenCircle(0, 0, r);
        expect(
          worstSagitta(c, 0, 0, r),
          lessThanOrEqualTo(defaultFlatness),
          reason: 'radius $r',
        );
      }
    });

    test('and it is the fewest segments that clears it, not merely enough', () {
      // A tolerance nothing binds is a tolerance that could be anything. One
      // segment fewer must break the bound, which pins the segment count to
      // the stated flatness rather than to a comfortable margin.
      for (final r in <double>[23, 38]) {
        final n = flattenCircle(0, 0, r).length;
        final coarser = PathContour([
          for (var i = 0; i < n - 1; i++) ...[
            r * math.cos(2 * math.pi * i / (n - 1)),
            r * math.sin(2 * math.pi * i / (n - 1)),
          ],
        ]);
        expect(
          worstSagitta(coarser, 0, 0, r),
          greaterThan(defaultFlatness),
          reason: 'radius $r is over-segmented at $n',
        );
      }
    });

    test('a disc comes out at pi r squared', () {
      for (final r in <double>[20, 23, 38]) {
        final coverage = polygonCoverage(
          width: 120,
          height: 120,
          polygon: RasterPolygon([
            flattenCircle(60, 60, r),
          ], SolidPaint.hex('#000000')),
        );
        var area = 0.0;
        for (final c in coverage) {
          area += c;
        }
        final exact = pi * r * r;
        expect(area, closeTo(exact, 0.05), reason: 'radius $r');
        expect(area, lessThan(exact), reason: 'inscribed, radius $r');
      }
    });
  });

  group('the mask applies to the composited group, not to each shape', () {
    // SVG masks a `<g mask="…">` by compositing its children first and scaling
    // the result's alpha afterwards. Folding the mask into every shape's own
    // coverage applies it once per shape, so two opaque shapes stacked on a
    // half-covered pixel come out at alpha 192 where one of them gives 128.
    //
    // Inert for `pixel` and `ring` — no mask-edge pixel of either is reached by
    // more than one shape — so nothing in the suite could see it. It is tens of
    // levels wrong on `marble`, `bauhaus` and `beam`, which each put a
    // full-canvas background rect under a shape that crosses the mask edge.
    final halfMask = RoundedRectMask(x: 0, y: 0, width: 1, height: 0.5, rx: 0);

    List<int> render(int shapes) => rasterizeMaskedShapes(
      width: 1,
      height: 1,
      mask: halfMask,
      shapes: [
        for (var i = 0; i < shapes; i++)
          RasterRect(0, 0, 1, 1, SolidPaint.hex('#FFFFFF')),
      ],
    ).bytes;

    test('stacking an opaque shape on itself does not darken the mask', () {
      expect(render(1), [255, 255, 255, 128]);
      expect(render(2), render(1));
      expect(render(5), render(1));
    });

    test('a partly covered shape still scales by the mask exactly once', () {
      final image = rasterizeMaskedShapes(
        width: 1,
        height: 1,
        mask: halfMask,
        shapes: [
          RasterRect(0, 0, 1, 0.5, SolidPaint.hex('#FF0000')),
          RasterRect(0, 0, 1, 0.5, SolidPaint.hex('#FF0000')),
        ],
      );
      // Coverage is a scalar, so two shapes each covering half the pixel
      // composite to 0.75 rather than to the 0.5 their geometry would give —
      // hidden-state #24, and what a browser does too. The mask then halves
      // that once: 0.75 · 0.5 · 255 ≈ 96. What matters here is that the mask is
      // applied a single time; applying it per shape would give 72.
      expect(image.bytes[3], 96);
    });

    test('a pixel the mask removes entirely is cleared, not left coloured', () {
      // Straight alpha leaves the colour of a transparent pixel undefined, so
      // it needs one canonical answer or the goldens are comparing noise.
      // Chrome writes zero.
      final image = rasterizeMaskedShapes(
        width: 1,
        height: 1,
        mask: RoundedRectMask(x: 0, y: 0, width: 1, height: 0, rx: 0),
        shapes: [RasterRect(0, 0, 1, 1, SolidPaint.hex('#FF0000'))],
      );
      expect(image.bytes, [0, 0, 0, 0]);
    });
  });

  group('a linear gradient projects onto its own axis', () {
    // **Every gradient this package has ever rasterised is vertical.**
    // `sunset` writes x1 = x2 = 40, so `dx` is zero and the x half of the
    // projection is multiplied away — `x1` and `x2` are values nothing reads.
    // Measured: replacing both with -12345 changes not one pixel of any render.
    //
    // Same shape as hidden-state #36, where `largeArc` turned out to be
    // dead-valued across the whole corpus, and the same answer: the cases below
    // are **constructed**, because no upstream variant will ever produce them.
    const red = RasterColour(255, 0, 0);
    const blue = RasterColour(0, 0, 255);

    LinearGradientPaint axis(double x1, double y1, double x2, double y2) =>
        LinearGradientPaint(
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          stops: const [(0.0, red), (1.0, blue)],
        );

    /// The blue fraction at a pixel, 0–1, which is `t` recovered from the mix.
    double blueness(LinearGradientPaint paint, int px, int py) =>
        paint.colourAt(px, py).b / 255;

    test('a horizontal gradient varies along x and not along y', () {
      final paint = axis(0, 0, 10, 0);
      expect(blueness(paint, 0, 0), closeTo(0.05, 0.005));
      expect(blueness(paint, 9, 0), closeTo(0.95, 0.005));
      // …and y does nothing.
      for (final y in [0, 3, 7]) {
        expect(blueness(paint, 5, y), blueness(paint, 5, 0), reason: 'y=$y');
      }
    });

    test('a diagonal gradient reads both axes', () {
      // From (0,0) to (10,10): t is the projection onto the diagonal, so
      // (8,2) and (2,8) sit on the same band and (0,0) and (9,9) do not.
      final paint = axis(0, 0, 10, 10);
      expect(blueness(paint, 8, 2), closeTo(blueness(paint, 2, 8), 0.005));
      expect(blueness(paint, 0, 0), closeTo(0.05, 0.005));
      expect(blueness(paint, 9, 9), closeTo(0.95, 0.005));
      // A gradient that ignored x would make these three equal, since they
      // share a row.
      expect(blueness(paint, 0, 5), isNot(blueness(paint, 9, 5)));
    });

    test('the axis direction is read, not just its length', () {
      // Reversing the axis reverses the ramp. A projection that took the
      // absolute distance from the start would give the same answer for both.
      final forward = axis(0, 0, 0, 10);
      final backward = axis(0, 10, 0, 0);
      expect(blueness(forward, 0, 1), closeTo(blueness(backward, 0, 8), 0.005));
      expect(blueness(forward, 0, 1), lessThan(blueness(forward, 0, 8)));
    });

    test('past either end the gradient pads, per the default spread', () {
      // `sunset`'s stops span exactly the shape, so t never leaves [0, 1] and
      // neither clamp is ever reached by a real render.
      final paint = axis(0, 4, 0, 6);
      expect(paint.colourAt(0, 0).b, 0, reason: 'before the first stop');
      expect(paint.colourAt(0, 9).b, 255, reason: 'after the last stop');
      expect(paint.colourAt(0, 0).r, 255);
      expect(paint.colourAt(0, 9).r, 0);
    });

    test('a zero-length axis paints the last stop everywhere', () {
      // SVG 1.1: "if x1 = x2 and y1 = y2, the area is painted with the colour
      // of the last gradient stop". Dividing by the squared length would give
      // NaN and paint nothing.
      final paint = axis(5, 5, 5, 5);
      for (final point in const [(0, 0), (5, 5), (9, 9)]) {
        expect(paint.colourAt(point.$1, point.$2).b, 255, reason: '$point');
      }
    });

    test('more than two stops interpolate piecewise', () {
      // Upstream writes two. The loop handles more, and nothing else reaches
      // it — so the case is made rather than assumed.
      const green = RasterColour(0, 255, 0);
      final paint = LinearGradientPaint(
        x1: 0,
        y1: 0,
        x2: 0,
        y2: 10,
        stops: const [(0.0, red), (0.5, green), (1.0, blue)],
      );
      expect(paint.colourAt(0, 2).g, greaterThan(paint.colourAt(0, 0).g));
      expect(
        paint.colourAt(0, 4).g,
        greaterThan(200),
        reason: 'near the green',
      );
      expect(paint.colourAt(0, 4).b, lessThan(30), reason: 'blue not yet');
      expect(paint.colourAt(0, 9).b, greaterThan(200));
      expect(paint.colourAt(0, 9).g, lessThan(60));
    });

    test('two stops at the same offset step rather than divide by zero', () {
      final paint = LinearGradientPaint(
        x1: 0,
        y1: 0,
        x2: 0,
        y2: 10,
        stops: const [(0.0, red), (0.5, red), (0.5, blue), (1.0, blue)],
      );
      expect(paint.colourAt(0, 2).r, 255);
      expect(paint.colourAt(0, 7).b, 255);
    });

    test('landing exactly on a doubled offset takes the later stop', () {
      // The zero-span branch is only reachable when `t` is *exactly* the shared
      // offset, which needs an axis short enough for a pixel centre to land on
      // it — one unit tall puts the first row's centre at t = 0.5 exactly. SVG
      // steps to the later stop there, and the branch that decides it survived
      // every mutation until this case was constructed.
      final paint = LinearGradientPaint(
        x1: 0,
        y1: 0,
        x2: 0,
        y2: 1,
        stops: const [(0.5, red), (0.5, blue)],
      );
      expect(paint.colourAt(0, 0).b, 255, reason: 'the later stop wins');
      expect(paint.colourAt(0, 0).r, 0);
    });
  });

  group('the two coverage paths agree with each other', () {
    test('a rect drawn as a polygon matches the closed-form rect', () {
      // `RasterRect` keeps its own exact integrator; a second implementation of
      // "fill a shape" is a divergence seed unless the two are tied together.
      // Fractional edges are the case where they could plausibly part.
      final mask = RoundedRectMask(x: 0, y: 0, width: 8, height: 8, rx: 0);
      final asRect = rasterizeMaskedShapes(
        width: 8,
        height: 8,
        shapes: [RasterRect(1.25, 2.5, 4.5, 3.25, SolidPaint.hex('#FF8000'))],
        mask: mask,
      );
      final asPolygon = rasterizeMaskedShapes(
        width: 8,
        height: 8,
        shapes: [
          RasterPolygon([
            rectangleContour(1.25, 2.5, 4.5, 3.25),
          ], SolidPaint.hex('#FF8000')),
        ],
        mask: mask,
      );
      // Both are quantised to a byte, so they may differ by the rounding of a
      // single level on the rows where the polygon integrator quantises y.
      for (var i = 0; i < asRect.bytes.length; i++) {
        expect(
          (asRect.bytes[i] - asPolygon.bytes[i]).abs(),
          lessThanOrEqualTo(1),
          reason: 'byte $i',
        );
      }
    });
  });
}

/// Distance from (px, py) to the segment (ax, ay)–(bx, by).
///
/// Used to measure a flattened polyline against the curve it replaces, in the
/// direction that matters: how far the *curve* strays from the chords, which
/// is what a coverage error is made of. A vertex-only check would pass for a
/// flattener that put every vertex on the curve and used two of them.
double _distanceToSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax, dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  final t = lengthSquared == 0
      ? 0.0
      : (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
  final qx = ax + t * dx, qy = ay + t * dy;
  return math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
}
