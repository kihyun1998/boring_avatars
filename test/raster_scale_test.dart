import 'dart:math' as math;

import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_cases.dart';

/// Rasterising at a size the `viewBox` does not state (#58).
///
/// The widget cannot exist without this. A logical size becomes physical
/// pixels by multiplying by the device pixel ratio, and Flutter's own
/// `media_query.dart` says of that number: "This number might not be a power
/// of two. Indeed, it might not even be an integer." So an integer-only scale
/// is no scale at all, and handing a fixed-size raster to `RawImage` and
/// letting it stretch would put Skia's resampling in the output — the one
/// thing owning a rasterizer was supposed to prevent.
///
/// **What is not here.** That a 1:1 render is byte-identical to the committed
/// goldens is the additive invariant this ticket is most likely to break, and
/// it is already asserted — every `*_raster_test.dart` renders its variant at
/// its own viewBox and compares against `test/goldens/`. A copy here would be
/// a second assertion of the same fact, free to disagree with the first.
void main() {
  /// Every golden case, rasterised at [scale] times its own viewBox.
  ///
  /// The size is per variant, not global: `beam`'s viewBox is 36 and `ring`'s
  /// is 90 where the rest are 80. Hardcoding 80 mis-scales two of the six and
  /// the test still looks like it passed.
  RasterImage renderAt(String name, num scale) {
    final (scene, side) = goldenCases[name]!;
    return rasterizeScene(
      scene,
      width: (side * scale).round(),
      height: (side * scale).round(),
    );
  }

  int opaqueCount(RasterImage image) {
    var n = 0;
    for (var i = 3; i < image.bytes.length; i += 4) {
      if (image.bytes[i] > 0) n++;
    }
    return n;
  }

  /// The integral of alpha over the image — the drawn **area**, in units of
  /// 1/255 of a pixel.
  ///
  /// Counting pixels instead does not measure an area and cannot satisfy a
  /// square law: the interior grows as s squared but the antialiased boundary
  /// is one-dimensional and grows as s, so the ratio sags below 4 by the
  /// perimeter's share. Measured on `pixel-clara-default`: 5164 -> 20380, a
  /// ratio of 3.947, with a circumference of about 251 pixels accounting for
  /// the shortfall almost exactly. Coverage has no such term.
  int coverage(RasterImage image) {
    var total = 0;
    for (var i = 3; i < image.bytes.length; i += 4) {
      total += image.bytes[i];
    }
    return total;
  }

  group('an arbitrary real scale, not just an integer one', () {
    // 2.625 and 3.5 are real device pixel ratios, and the second is the one
    // `media_query.dart` names. Both land on whole pixels from an 80 viewBox
    // — 210 and 280 — so the scale is exactly non-integer rather than
    // approximately so.
    for (final scale in <num>[0.5, 1, 1.5, 2, 2.625, 3, 3.5]) {
      test('pixel at ${scale}x', () {
        final image = renderAt('pixel-clara-default', scale);
        expect(image.width, (80 * scale).round());
        expect(image.height, (80 * scale).round());
        expect(
          opaqueCount(image),
          greaterThan(0),
          reason: 'the scale produced an empty canvas',
        );
      });
    }

    test('every variant scales, not just the one with a square viewBox', () {
      for (final name in goldenCases.keys) {
        final image = renderAt(name, 2);
        final (_, side) = goldenCases[name]!;
        expect(image.width, side * 2, reason: name);
        expect(opaqueCount(image), greaterThan(0), reason: name);
      }
      // A loop over an empty roster would pass every assertion above.
      expect(goldenCases, isNotEmpty);
    });
  });

  group('the scale moves nothing but the resolution', () {
    test('area grows as the square of the scale', () {
      // Coverage is an area, so an avatar drawn at `s` covers `s²` times the
      // pixels. The mask is what bounds it, so this is also the mask having
      // scaled: a mask left at its 1:1 size would clip the 2x render to a
      // quarter of the canvas and the ratio would come out at 1, not 4.
      for (final name in <String>[
        'pixel-clara-default',
        'ring-clara-default',
        'beam-clara-default',
        'marble-clara-default',
      ]) {
        final one = coverage(renderAt(name, 1));
        final two = coverage(renderAt(name, 2));
        expect(
          two / one,
          closeTo(4, 0.01),
          reason: '$name: $one -> $two is not a square-law growth',
        );
      }
    });

    test('a finer render, box-filtered back down, is the coarser render', () {
      // The strongest statement available: scaling changes the sampling rate
      // and not the geometry. If a scale shifted a shape by a fraction of a
      // unit, averaging the finer render would not land on the coarser one.
      //
      // **Each shape sits entirely inside the mask, and that is the whole
      // premise.** Box-filtering commutes with *coverage* — the area of a
      // shape inside four sub-pixels sums to its area in the pixel — but not
      // with *compositing*, which is not linear. Where two coverages meet in
      // one pixel, 1:1 blends both into that pixel while the finer render
      // paints each sub-pixel once and averages afterwards. That is the
      // classic conflation artefact and it is a property of every compositing
      // rasterizer, not of this change.
      //
      // Measured, so the boundary of the claim is a number and not a hope.
      // The same path at 2x, moved so one corner crosses the mask circle:
      // worst 20.50. Moved back inside: 1.00. And over the real variants,
      // where shapes overlap each other as well as the mask —
      //
      //   pixel / ring      <= 1.00      no channel over 1/255
      //   sunset            <= 1.50      4-6 channels
      //   beam              <= 12.25     6-14 channels
      //   bauhaus           <= 24.75     29-41 channels
      //   marble            <= 3.00      205-1587 channels (a blur, so every
      //                                  pixel has many contributions)
      //
      // #58's acceptance asked for <= 1/255 across the variants. That bar
      // cannot be met by a correct rasterizer and asking for it was the
      // mistake; the numbers above are what the ticket gets instead, and the
      // square-law test above is what covers the real scenes.
      SvgNode inMask(SvgNode shape) => SvgNode(
        SvgElement.svg,
        attributes: const [SvgAttribute('viewBox', '0 0 40 40')],
        children: [
          const SvgNode(
            SvgElement.mask,
            attributes: [
              SvgAttribute('id', 'm'),
              SvgAttribute('width', 40),
              SvgAttribute('height', 40),
            ],
            children: [
              SvgNode(
                SvgElement.rect,
                attributes: [
                  SvgAttribute('width', 40),
                  SvgAttribute('height', 40),
                  SvgAttribute('rx', 80),
                  SvgAttribute('fill', '#FFFFFF'),
                ],
              ),
            ],
          ),
          SvgNode(
            SvgElement.g,
            attributes: const [SvgAttribute('mask', 'url(#m)')],
            children: [shape],
          ),
        ],
      );

      final cases = <String, SvgNode>{
        'circle': inMask(
          const SvgNode(
            SvgElement.circle,
            attributes: [
              SvgAttribute('cx', 21.3),
              SvgAttribute('cy', 18.7),
              SvgAttribute('r', 13.4),
              SvgAttribute('fill', '#C271B4'),
            ],
          ),
        ),
        'rotated rect': inMask(
          const SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('x', 5.5),
              SvgAttribute('y', 7.25),
              SvgAttribute('width', 22.5),
              SvgAttribute('height', 17.75),
              SvgAttribute('fill', '#146A7C'),
              SvgAttribute('transform', 'rotate(23 20 20)'),
            ],
          ),
        ),
        'path': inMask(
          const SvgNode(
            SvgElement.path,
            attributes: [
              SvgAttribute('d', 'M12 14L27 16L25 29L14 26z'),
              SvgAttribute('fill', '#F0AB3D'),
            ],
          ),
        ),
      };

      // **Premultiplied, and that is not a detail.** These bytes are straight
      // RGBA, so a transparent pixel carries RGB 0 — averaging the channels as
      // they sit drags the colour down wherever alpha varies, which is every
      // antialiased edge. Measured before this was fixed: a worst delta of
      // 180/255, entirely an artefact of the measurement.
      int premul(RasterImage img, int index, int channel) {
        final i = index * 4;
        final a = img.bytes[i + 3];
        return channel == 3 ? a : (img.bytes[i + channel] * a + 127) ~/ 255;
      }

      const side = 40;
      var compared = 0;
      for (final entry in cases.entries) {
        for (final s in <int>[2, 3]) {
          final one = rasterizeScene(entry.value, width: side, height: side);
          final fine = rasterizeScene(
            entry.value,
            width: side * s,
            height: side * s,
          );

          var worst = 0.0;
          for (var y = 0; y < side; y++) {
            for (var x = 0; x < side; x++) {
              for (var c = 0; c < 4; c++) {
                var sum = 0;
                for (var dy = 0; dy < s; dy++) {
                  for (var dx = 0; dx < s; dx++) {
                    sum += premul(
                      fine,
                      (y * s + dy) * side * s + x * s + dx,
                      c,
                    );
                  }
                }
                final delta = (sum / (s * s) - premul(one, y * side + x, c))
                    .abs();
                if (delta > worst) worst = delta;
              }
            }
          }
          expect(
            worst,
            lessThanOrEqualTo(1.0),
            reason: '${entry.key} at ${s}x: worst channel delta $worst/255',
          );
          compared++;
        }
      }
      expect(compared, cases.length * 2);
    });
  });

  group('the lengths that no matrix carries', () {
    /// A gradient-filled rect, alone inside a mask, in a **non-square**
    /// viewBox.
    ///
    /// Three mutants live here and nothing else in the suite kills them, which
    /// is the whole reason this scene is shaped the way it is:
    ///
    /// * the gradient axis is the only length in the rasterizer that neither
    ///   rides the matrix nor is scaled at construction, so leaving it in user
    ///   units is invisible to every scene without a `<linearGradient>`;
    /// * every viewBox in the six is square, so reading the scale off the
    ///   height, or swapping the two, is a no-op on all of them;
    /// * one shape inside the mask keeps the box-filter premise — no two
    ///   coverages meet in a pixel — so the bar can stay at 1/255.
    SvgNode gradientScene() => const SvgNode(
      SvgElement.svg,
      attributes: [SvgAttribute('viewBox', '0 0 80 40')],
      children: [
        SvgNode(
          SvgElement.defs,
          children: [
            SvgNode(
              SvgElement.linearGradient,
              attributes: [
                SvgAttribute('id', 'g'),
                SvgAttribute('x1', 8),
                SvgAttribute('y1', 6),
                SvgAttribute('x2', 68),
                SvgAttribute('y2', 32),
                SvgAttribute('gradientUnits', 'userSpaceOnUse'),
              ],
              children: [
                SvgNode(
                  SvgElement.stop,
                  attributes: [
                    SvgAttribute('offset', 0),
                    SvgAttribute('stop-color', '#146A7C'),
                  ],
                ),
                SvgNode(
                  SvgElement.stop,
                  attributes: [
                    SvgAttribute('offset', 1),
                    SvgAttribute('stop-color', '#F0AB3D'),
                  ],
                ),
              ],
            ),
          ],
        ),
        SvgNode(
          SvgElement.mask,
          attributes: [
            SvgAttribute('id', 'm'),
            SvgAttribute('width', 80),
            SvgAttribute('height', 40),
          ],
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                SvgAttribute('width', 80),
                SvgAttribute('height', 40),
                SvgAttribute('fill', '#FFFFFF'),
              ],
            ),
          ],
        ),
        SvgNode(
          SvgElement.g,
          attributes: [SvgAttribute('mask', 'url(#m)')],
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                SvgAttribute('x', 6),
                SvgAttribute('y', 4),
                SvgAttribute('width', 64),
                SvgAttribute('height', 30),
                SvgAttribute('fill', 'url(#g)'),
              ],
            ),
          ],
        ),
      ],
    );

    test('a gradient axis scales with everything else', () {
      // A gradient left in user units puts the whole ramp in the top-left
      // 1/scale of the image and clamps the rest to an end stop, so the
      // finer render stops agreeing with the coarser one immediately.
      const w = 80, h = 40;
      final one = rasterizeScene(gradientScene(), width: w, height: h);
      final two = rasterizeScene(gradientScene(), width: w * 2, height: h * 2);

      var worst = 0.0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          for (var c = 0; c < 4; c++) {
            var sum = 0;
            for (var dy = 0; dy < 2; dy++) {
              for (var dx = 0; dx < 2; dx++) {
                final i = ((y * 2 + dy) * w * 2 + x * 2 + dx) * 4;
                final a = two.bytes[i + 3];
                sum += c == 3 ? a : (two.bytes[i + c] * a + 127) ~/ 255;
              }
            }
            final j = (y * w + x) * 4;
            final a = one.bytes[j + 3];
            final base = c == 3 ? a : (one.bytes[j + c] * a + 127) ~/ 255;
            final delta = (sum / 4 - base).abs();
            if (delta > worst) worst = delta;
          }
        }
      }
      expect(worst, lessThanOrEqualTo(1.0), reason: 'worst $worst/255');
    });

    test('the ramp really runs, so the check above has something to see', () {
      // If both renders were a flat colour the comparison would pass on a
      // scene that proves nothing.
      final one = rasterizeScene(gradientScene(), width: 80, height: 40);
      final left = one.bytes[(20 * 80 + 10) * 4];
      final right = one.bytes[(20 * 80 + 66) * 4];
      expect(
        (left - right).abs(),
        greaterThan(40),
        reason: 'red went $left -> $right across the ramp',
      );
    });

    test('the default filter region reads the viewBox the right way round', () {
      // The region's default is -10%/120% **of the viewBox**, so for 80x40 it
      // is x=-8 y=-4 w=96 h=48 and its right edge sits at 88 — off canvas,
      // cutting nothing. Swap the two numbers and it becomes w=48, right edge
      // 44, which cuts the shape in half.
      //
      // Only a non-square viewBox can tell, and none of the six has one; the
      // swap survived the entire suite before this test existed.
      SvgNode filtered() => const SvgNode(
        SvgElement.svg,
        attributes: [SvgAttribute('viewBox', '0 0 80 40')],
        children: [
          SvgNode(
            SvgElement.defs,
            children: [
              SvgNode(
                SvgElement.filter,
                attributes: [
                  SvgAttribute('id', 'f'),
                  SvgAttribute('filterUnits', 'userSpaceOnUse'),
                  // The SVG default is linearRGB, which this rasterizer
                  // refuses rather than approximating; upstream declares sRGB
                  // and so does this scene.
                  SvgAttribute('color-interpolation-filters', 'sRGB'),
                ],
                children: [
                  SvgNode(
                    SvgElement.feFlood,
                    attributes: [
                      SvgAttribute('flood-opacity', 0),
                      SvgAttribute('result', 'bg'),
                    ],
                  ),
                  SvgNode(
                    SvgElement.feBlend,
                    attributes: [
                      SvgAttribute('in', 'SourceGraphic'),
                      SvgAttribute('in2', 'bg'),
                      SvgAttribute('result', 'shape'),
                    ],
                  ),
                  SvgNode(
                    SvgElement.feGaussianBlur,
                    attributes: [
                      SvgAttribute('stdDeviation', 1),
                      SvgAttribute('result', 'out'),
                    ],
                  ),
                ],
              ),
            ],
          ),
          SvgNode(
            SvgElement.mask,
            attributes: [
              SvgAttribute('id', 'm'),
              SvgAttribute('width', 80),
              SvgAttribute('height', 40),
            ],
            children: [
              SvgNode(
                SvgElement.rect,
                attributes: [
                  SvgAttribute('width', 80),
                  SvgAttribute('height', 40),
                  SvgAttribute('fill', '#FFFFFF'),
                ],
              ),
            ],
          ),
          SvgNode(
            SvgElement.g,
            attributes: [SvgAttribute('mask', 'url(#m)')],
            children: [
              SvgNode(
                SvgElement.path,
                attributes: [
                  SvgAttribute('d', 'M-100 -100H200V200H-100z'),
                  SvgAttribute('fill', '#FFFFFF'),
                  SvgAttribute('filter', 'url(#f)'),
                ],
              ),
            ],
          ),
        ],
      );

      int alphaAt(RasterImage i, int side, int x, int y) =>
          i.bytes[(y * side + x) * 4 + 3];

      for (final scale in <int>[1, 2]) {
        final image = rasterizeScene(
          filtered(),
          width: 80 * scale,
          height: 40 * scale,
        );
        // The shape covers everything, so the only thing that can remove ink
        // is the region. x=60 (user) is inside the correct region and beyond
        // the swapped one.
        expect(
          alphaAt(image, 80 * scale, 60 * scale, 20 * scale),
          greaterThan(0),
          reason:
              'at ${scale}x, user x=60 is inside the -10%/120% region of an '
              '80-wide viewBox; a swapped region would end at 44',
        );
      }
    });

    test('a non-square viewBox scales by its own proportion', () {
      final image = rasterizeScene(gradientScene(), width: 160, height: 80);
      expect(image.width, 160);
      expect(image.height, 80);
      // Reading the scale off the wrong axis, or swapping the viewBox's two
      // numbers, only shows up when they differ.
      expect(
        () => rasterizeScene(gradientScene(), width: 80, height: 80),
        throwsA(isA<UnsupportedSceneError>()),
        reason: '80x80 from an 80x40 viewBox is not a uniform scale',
      );
    });
  });

  _abuttingSeams();
  _strokeDiscs();

  group('what a scale cannot be', () {
    SvgNode viewBoxed(String viewBox) => SvgNode(
      SvgElement.svg,
      attributes: [SvgAttribute('viewBox', viewBox)],
      children: const [
        SvgNode(
          SvgElement.mask,
          attributes: [SvgAttribute('width', 4), SvgAttribute('height', 4)],
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                SvgAttribute('width', 4),
                SvgAttribute('height', 4),
                SvgAttribute('fill', '#FFFFFF'),
              ],
            ),
          ],
        ),
      ],
    );

    test('a non-uniform target is refused, not averaged', () {
      // `blurSigma` reads the matrix's column norms because a Gaussian is
      // isotropic only under a similarity transform. Two different scales
      // would make it pick one of two blurs with nothing said.
      expect(
        () => rasterizeScene(viewBoxed('0 0 4 4'), width: 8, height: 4),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('a non-positive target is refused', () {
      for (final (w, h) in <(int, int)>[(0, 4), (4, 0), (-4, 4), (-1, -1)]) {
        expect(
          () => rasterizeScene(viewBoxed('0 0 4 4'), width: w, height: h),
          // The message, not just the type. A zero-sized target throws further
          // down anyway, so `isA<UnsupportedSceneError>()` alone is satisfied
          // by the guard being absent — measured: relaxing `<= 0` to `< 0`
          // left the whole suite green.
          throwsA(
            isA<UnsupportedSceneError>().having(
              (e) => e.toString(),
              'message',
              contains('a raster needs a positive size'),
            ),
          ),
          reason: '${w}x$h',
        );
      }
    });

    test('a viewBox with no extent is refused', () {
      // The scale is `target / viewBox`, so a zero or negative viewBox is a
      // division that would come back infinite or mirrored rather than wrong
      // in a way anything downstream would notice.
      for (final box in <String>['0 0 0 4', '0 0 4 0', '0 0 -4 4']) {
        expect(
          () => rasterizeScene(viewBoxed(box), width: 4, height: 4),
          throwsA(
            isA<UnsupportedSceneError>().having(
              (e) => e.toString(),
              'message',
              contains('there is nothing to scale from'),
            ),
          ),
          reason: box,
        );
      }
    });
  });
}

/// The stroke outline's joint and cap discs (#58's completeness pass, F2).
///
/// They are curves, and until that pass they were the one flattening in the
/// rasterizer that never saw the device scale — `strokePathOutline` took no
/// `flatness` at all and its `flattenCircle` ran on the user-unit default. The
/// segment count was therefore constant in the scale while the radius grew, so
/// the device error grew linearly and crossed the 1/255 coverage bar at about
/// 25x. `beam`'s open mouth is the only round-capped stroke in the six, and a
/// 36-unit viewBox reaches 25x at a 900-pixel avatar.
void _strokeDiscs() {
  test('a stroked cap keeps its tolerance when the device scale grows', () {
    // The quads are exact polygons, so every square unit missing from the
    // total belongs to the two cap discs. Analytic area = L*W + pi*r^2.
    const length = 20.0, width = 8.0, r = width / 2;
    final analytic = length * width + math.pi * r * r;

    final scene = SvgNode(
      SvgElement.svg,
      attributes: const [SvgAttribute('viewBox', '0 0 40 40')],
      children: const [
        SvgNode(
          SvgElement.mask,
          attributes: [
            SvgAttribute('id', 'm'),
            SvgAttribute('width', 40),
            SvgAttribute('height', 40),
          ],
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                SvgAttribute('width', 40),
                SvgAttribute('height', 40),
                SvgAttribute('fill', '#FFFFFF'),
              ],
            ),
          ],
        ),
        SvgNode(
          SvgElement.g,
          attributes: [SvgAttribute('mask', 'url(#m)')],
          children: [
            SvgNode(
              SvgElement.path,
              attributes: [
                SvgAttribute('d', 'M10 20L30 20'),
                SvgAttribute('stroke', '#FFFFFF'),
                SvgAttribute('stroke-width', width),
                SvgAttribute('stroke-linecap', 'round'),
              ],
            ),
          ],
        ),
      ],
    );

    double deficitAt(int scale) {
      final side = 40 * scale;
      final image = rasterizeScene(scene, width: side, height: side);
      var ink = 0;
      for (var i = 3; i < image.bytes.length; i += 4) {
        ink += image.bytes[i];
      }
      return analytic * scale * scale - ink / 255;
    }

    // **Absolute, not relative — that is what discriminates.** A disc
    // flattened at a fixed segment count loses area as the *square* of the
    // radius, so its relative deficit is identical at every scale and a
    // percentage bar cannot see the defect at all.
    //
    // Held to the scaled tolerance the deficit is an inscribed polygon's sag
    // times its perimeter, which grows only **linearly**, and that is the
    // whole of what this fix buys. Measured at 26x: 0.0162 px² with the
    // tolerance threaded, 0.34 without — a bar of 0.05 sits three times above
    // the first and twenty times below the second.
    expect(deficitAt(1).abs(), lessThan(0.01), reason: 'at 1x');
    expect(deficitAt(26).abs(), lessThan(0.05), reason: 'at 26x');
  });
}

/// Hidden-state row #24, live for the first time (#58's completeness pass, F1).
///
/// Two shapes that **abut** inside one pixel should fill it; source-over
/// compositing gives 192 instead of 255. The row recorded that mechanism from
/// the start and called it inert, and both of its inertness arguments named
/// `_checkViewBox` — `pixel`'s tiles are integer-aligned *at a 1:1 target*,
/// `ring` abuts along y=45 *at the enforced 90×90*. #58 deleted that check, so
/// the condition the row reserved is now reachable from an ordinary device
/// pixel ratio.
///
/// **This test asserts the measurement, not a verdict.** Whether the seam is a
/// defect or the correct reproduction is unruled: a browser compositing a plain
/// display list conflates the same way (row #23), so matching it may be right,
/// and only a `tool/calibrate` run against Chrome can say. Pinning the number
/// keeps the gap visible instead of leaving it to be rediscovered — and the day
/// the ruling lands, this test is where it is cashed.
void _abuttingSeams() {
  test('abutting tiles seam at a fractional target — measured, not ruled', () {
    int seamed(int side) {
      final (scene, _) = goldenCases['pixel-clara-default']!;
      final image = rasterizeScene(scene, width: side, height: side);
      final r = side / 2;
      var n = 0;
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final dx = x + 0.5 - r, dy = y + 0.5 - r;
          // Clear of the mask rim, so only shape-meets-shape can show up.
          if (dx * dx + dy * dy > (r - 4) * (r - 4)) continue;
          if (image.bytes[(y * side + x) * 4 + 3] < 255) n++;
        }
      }
      return n;
    }

    // `pixel` draws 8x8 tiles of 10 units. A target that is a multiple of 8
    // puts every tile edge on a pixel boundary; anything else does not, and
    // seven target sizes in eight are anything else.
    expect(seamed(80), 0, reason: '1:1');
    expect(seamed(128), 0, reason: '80 * 1.6 — tiles land on 16 whole pixels');
    expect(seamed(100), 556, reason: 'tiles of 12.5 pixels');
    expect(
      seamed(210),
      1944,
      reason:
          '2.625, a real device pixel ratio, and the one the scale sweep '
          'above renders while asserting only that the canvas is not empty',
    );
  });

  test('and Chrome seams identically, which is what settles #24', () {
    // **The ruling, not another measurement.** The counts above were pinned in
    // #58 with "measured, not ruled" written beside them, because nothing said
    // whether a browser fills those pixels or leaves them exactly as we do.
    // #83 ran `tool/calibrate` and it does leave them:
    //
    //   pixel-clara-square-100   partial px — ours 784, Chrome 784
    //                            opaque in Chrome, translucent here: 0
    //                            worst edge delta 3/255
    //
    // The square case carries the ruling because it is the only one with no
    // curve in it. Every other row of that run has a rounded mask, and
    // hidden-state #27 measured Chrome's curves up to 0.13 px inside ours — so
    // a residue there says nothing about *this* mechanism. With the curve gone
    // the residue goes to zero, and `pixel-clara-210` — the device pixel ratio
    // a widget actually asks for — agrees too.
    //
    // **Why the count and not the picture.** 784 == 784 is a weaker statement
    // than per-pixel identity, and it is paired with the two that are not:
    // zero pixels where Chrome is opaque and we are not, and a worst edge delta
    // of 3/255 across the whole render — the best row in that table by a factor
    // of twenty. What this test can hold on its own is the count; what it is
    // *for* is that a change moving the count has invalidated the agreement
    // above, and should send someone back to Chrome rather than to this number.
    final (scene, _) = goldenCases['pixel-clara-square']!;
    final image = rasterizeScene(scene, width: 100, height: 100);
    var partial = 0;
    for (var i = 3; i < image.bytes.length; i += 4) {
      if (image.bytes[i] > 0 && image.bytes[i] < 255) partial++;
    }
    expect(
      partial,
      784,
      reason:
          'the square mask covers the canvas exactly at any target, so every '
          'one of these is a tile meeting a tile — no rim, no curve',
    );
  });
}
