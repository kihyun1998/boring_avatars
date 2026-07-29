import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:boring_avatars/src/raster/path.dart';
import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/raster/transform.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/bauhaus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// Layer-3 for `bauhaus` — the two capabilities it installs, and the variant.
///
/// Almost nothing here is compared against a golden. A golden freezes what we
/// already produce, so it can only catch a *regression*; these assertions are
/// the ones that can be checked without any of our own rendering being
/// trusted — a rotation is an isometry, so it preserves area and every point's
/// distance from the centre, whoever computes it; a butt-capped stroke of width
/// 2 along an 80-unit segment covers exactly 160 square units; and SVG 1.1 §7.4
/// defines `rotate(a cx cy)` as a composition of three other transforms, so the
/// two spellings must parse to the same matrix.
///
/// The machinery this slice installs is **wider than the slice** — `beam` and
/// `marble` will drive the same transform code, and `beam` the same stroke
/// code. That is the #36 war story, so several cases below are inputs `bauhaus`
/// never produces: a diagonal stroke, a rotation of exactly zero, an
/// unimplemented `scale`.
void main() {
  const palette = ['#FF0000', '#00FF00', '#0000FF', '#FFFF00'];

  /// Total coverage of one contour, over a canvas big enough to contain it.
  double areaOf(PathContour contour, {int size = 120}) {
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

  List<int> pixel(RasterImage image, int x, int y) {
    final i = (y * image.width + x) * 4;
    return image.bytes.sublist(i, i + 4);
  }

  /// A minimal scene: one square mask, and [shapes] inside the masked group.
  SvgNode sceneWith(List<SvgNode> shapes, {int size = 80}) => SvgNode(
    SvgElement.svg,
    attributes: [SvgAttribute('viewBox', '0 0 $size $size')],
    children: [
      SvgNode(
        SvgElement.mask,
        attributes: [
          const SvgAttribute('id', 'm'),
          SvgAttribute('width', size),
          SvgAttribute('height', size),
        ],
        children: [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', size),
              SvgAttribute('height', size),
              const SvgAttribute('fill', '#FFFFFF'),
            ],
          ),
        ],
      ),
      SvgNode(
        SvgElement.g,
        attributes: const [SvgAttribute('mask', 'url(#m)')],
        children: shapes,
      ),
    ],
  );

  group('the transform list is composed the way SVG 1.1 says', () {
    test('rotate(a cx cy) is its own three-transform expansion, §7.4', () {
      // The specification does not give the three-argument form a closed form
      // of its own — it says the operation "represents the equivalent of
      // translate(<cx>, <cy>) rotate(<rotate-angle>) translate(-<cx>, -<cy>)".
      // So the check is our parse of one spelling against our parse of the
      // other, which is independent of whichever matrix we hardcoded.
      for (final angle in <double>[0, 37, 90, 191, 356, -9]) {
        final compact = parseTransform('rotate($angle 40 40)');
        final expanded = parseTransform(
          'translate(40 40) rotate($angle) translate(-40 -40)',
        );
        for (final component in [
          (compact.a, expanded.a, 'a'),
          (compact.b, expanded.b, 'b'),
          (compact.c, expanded.c, 'c'),
          (compact.d, expanded.d, 'd'),
          (compact.e, expanded.e, 'e'),
          (compact.f, expanded.f, 'f'),
        ]) {
          expect(
            component.$1,
            closeTo(component.$2, 1e-12),
            reason: '${component.$3} at $angle°',
          );
        }
      }
    });

    test('a list post-multiplies: the rightmost transform applies first', () {
      // §7.5's nested-<g> equivalence, made discriminating. `translate(10 0)
      // rotate(90)` sends (1, 0) to (10, 1): the rotation acts on the shape's
      // own coordinates and the translation acts on the result. Composing the
      // other way round sends it to (0, 11) — a plausible place, on screen, for
      // a shape to be.
      final (x, y) = parseTransform('translate(10 0) rotate(90)').apply(1, 0);
      expect(x, closeTo(10, 1e-12));
      expect(y, closeTo(1, 1e-12));
    });

    test('rotate(0 …) is exactly the identity, not a near-identity', () {
      // `cos(0)` is 1 and `sin(0)` is 0 with no rounding, so the empty name —
      // whose hash is 0, so every one of its transforms is `rotate(0 40 40)` —
      // must keep the closed-form rectangle integrator rather than falling into
      // the polygon path. `rotate(360 …)` is *not* the identity in float, which
      // is why this is asserted rather than assumed; upstream never writes it,
      // because `getUnit(n, 360)` cannot return 360.
      expect(
        parseTransform('translate(0 0) rotate(0 40 40)').isTranslationOnly,
        isTrue,
      );
      expect(parseTransform('rotate(360 40 40)').isTranslationOnly, isFalse);
      expect(parseTransform('translate(3 -4)').isTranslationOnly, isTrue);
      expect(parseTransform('rotate(90 40 40)').isTranslationOnly, isFalse);
    });

    test('an empty or absent transform list is the identity, not an error', () {
      expect(parseTransform('').isTranslationOnly, isTrue);
      expect(parseTransform('   ').apply(3, 4), (3.0, 4.0));
    });

    test('an unimplemented function throws and names itself', () {
      // `beam` and `marble` both use `scale`; measured across all 600 renders,
      // those two and `bauhaus` are the only variants with a transform at all.
      // Ignoring one would draw a shape at a plausible size and throw nothing.
      expect(
        () => parseTransform('translate(4.5 4.5) scale(2)'),
        throwsA(
          isA<UnsupportedSceneError>().having(
            (e) => e.message,
            'message',
            allOf(contains('scale'), contains('beam')),
          ),
        ),
      );
      expect(
        () => parseTransform('skewX(20)'),
        throwsA(isA<UnsupportedSceneError>()),
      );
      expect(
        () => parseTransform('matrix(1 0 0 1 0 0)'),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('a malformed list throws rather than silently doing less', () {
      expect(
        () => parseTransform('translate(1 2) garbage'),
        throwsA(isA<UnsupportedSceneError>()),
      );
      expect(
        () => parseTransform('translate(a b)'),
        throwsA(isA<UnsupportedSceneError>()),
      );
      expect(
        () => parseTransform('rotate(1 2)'),
        throwsA(isA<UnsupportedSceneError>()),
      );
      expect(
        () => parseTransform('translate(1 2 3)'),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });
  });

  group('a rigid transform preserves what a rigid transform must', () {
    // Neither of these needs a golden, a browser, or our own rasterizer to be
    // right: they are properties of rotation itself.

    test('area survives, whatever the angle', () {
      for (final angle in <double>[0, 13, 37, 90, 191, 356]) {
        final matrix = parseTransform('translate(2 -3) rotate($angle 60 60)');
        final area = areaOf(
          matrix.transformContour(rectangleContour(50, 55, 20, 10)),
        );
        expect(area, closeTo(200, 0.05), reason: '$angle°');
      }
    });

    test('every vertex keeps its distance from the centre of rotation', () {
      final matrix = parseTransform('rotate(37 40 40)');
      final before = rectangleContour(10, 30, 80, 10);
      final after = matrix.transformContour(before);
      for (var i = 0; i < before.length; i++) {
        double distance(PathContour c, int i) =>
            math.sqrt(math.pow(c.x(i) - 40, 2) + math.pow(c.y(i) - 40, 2));
        expect(
          distance(after, i),
          closeTo(distance(before, i), 1e-9),
          reason: 'vertex $i',
        );
      }
    });
  });

  group('the stroked line', () {
    test('a butt-capped stroke is exactly the band it sweeps', () {
      // SVG 1.1 §11.4: `stroke-linecap` is `butt` by default, so the stroke
      // stops at the endpoints. Width 2 along 80 units is 160 square units, and
      // the band is 39..41 — a `square` cap would add 2 more at each end and a
      // `round` one would add a disc.
      final outline = strokeSegmentContour(0, 40, 80, 40, 2)!;
      expect(areaOf(outline), closeTo(160, 0.01));
      final xs = [for (var i = 0; i < outline.length; i++) outline.x(i)];
      final ys = [for (var i = 0; i < outline.length; i++) outline.y(i)];
      expect(xs.reduce(math.min), 0);
      expect(xs.reduce(math.max), 80);
      expect(ys.reduce(math.min), 39);
      expect(ys.reduce(math.max), 41);
    });

    test('and a diagonal one sweeps the same area — an input bauhaus never '
        'produces', () {
      // Upstream's line is horizontal in every render, so `dx`/`dy` are 80 and
      // 0 and the normal is (0, 1) whatever the arithmetic does with the other
      // component. A mutation swapping the two survives every real input, which
      // is the #37/#40 pattern: construct the case rather than shrug.
      for (final angle in <double>[0, 30, 45, 90]) {
        final radians = angle * math.pi / 180;
        final outline = strokeSegmentContour(
          60 - 40 * math.cos(radians),
          60 - 40 * math.sin(radians),
          60 + 40 * math.cos(radians),
          60 + 40 * math.sin(radians),
          2,
        )!;
        expect(areaOf(outline), closeTo(160, 0.05), reason: '$angle°');
      }
    });

    test('the specification\'s two "nothing is stroked" cases draw nothing', () {
      // §11.4: a zero-length subpath is not stroked under butt caps, and a zero
      // stroke-width paints nothing. Neither is reachable from `bauhaus`, and
      // the first would put NaN in every vertex if it were not guarded — a NaN
      // the scanline integrator carries silently rather than throwing.
      expect(strokeSegmentContour(40, 40, 40, 40, 2), isNull);
      expect(strokeSegmentContour(0, 40, 80, 40, 0), isNull);
      expect(strokeSegmentContour(0, 40, 80, 40, -2), isNull);
    });

    test('an absent stroke-width throws — the default arrives with beam', () {
      // SVG's initial `stroke-width` is 1, and `beam`'s stroked `<rect>` is the
      // element that actually omits it. Implementing a default no variant in
      // scope produces would ship arithmetic no test could reach.
      expect(
        () => rasterizeScene(
          sceneWith([
            const SvgNode(
              SvgElement.line,
              attributes: [
                SvgAttribute('x1', 0),
                SvgAttribute('y1', 40),
                SvgAttribute('x2', 80),
                SvgAttribute('y2', 40),
                SvgAttribute('stroke', '#FF0000'),
              ],
            ),
          ]),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('a <line fill="…"> throws — fill is not how a line is painted', () {
      expect(
        () => rasterizeScene(
          sceneWith([
            const SvgNode(
              SvgElement.line,
              attributes: [
                SvgAttribute('x1', 0),
                SvgAttribute('y1', 40),
                SvgAttribute('x2', 80),
                SvgAttribute('y2', 40),
                SvgAttribute('stroke-width', 2),
                SvgAttribute('fill', '#FF0000'),
              ],
            ),
          ]),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('an absent stroke draws nothing rather than falling back', () {
      // `stroke`'s initial value is `none`, so the empty palette — which makes
      // upstream omit the attribute — is a line that is simply not painted.
      final image = rasterizeScene(
        sceneWith([
          const SvgNode(
            SvgElement.line,
            attributes: [
              SvgAttribute('x1', 0),
              SvgAttribute('y1', 40),
              SvgAttribute('x2', 80),
              SvgAttribute('y2', 40),
              SvgAttribute('stroke-width', 2),
            ],
          ),
        ]),
        width: 80,
        height: 80,
      );
      expect(image.bytes.every((b) => b == 0), isTrue);
    });
  });

  group('bauhaus itself', () {
    /// The empty name hashes to **0**, so every `getUnit` is 0 and every
    /// transform is `translate(0 0) rotate(0 40 40)` — the identity. With a
    /// four-colour palette the elements take `colors[i]`, so each shape is
    /// identifiable by colour, and every edge lands on an integer.
    RasterImage identityRender({bool square = true}) => rasterizeScene(
      buildBauhausScene(name: '', colors: palette, size: 80, square: square),
      width: 80,
      height: 80,
    );

    test('a zero hash lands every edge on a pixel boundary', () {
      final image = identityRender();
      // `isSquare` is true for the empty name, so the bar is 80 × 80 at
      // (10, 30) — its left edge is the sharp one. At y = 70 nothing else is
      // drawn: the disc reaches y = 56 and the rule is at y = 39..41.
      expect(pixel(image, 9, 70), [255, 0, 0, 255], reason: 'background');
      expect(pixel(image, 10, 70), [0, 255, 0, 255], reason: 'the bar');
      // A rotation of a hair would antialias that boundary. Nothing between.
      expect(pixel(image, 8, 70), pixel(image, 0, 70));
    });

    test('a translated rect keeps its offsets apart — a constructed case', () {
      // Found by mutation: swapping the two components of a translation-only
      // transform survives every `bauhaus` render. Not a weak test — a
      // degenerate input. The only rect that takes the closed-form path is the
      // empty name's, whose translation is `(0, 0)`, so `e` and `f` are equal
      // and the swap is invisible.
      //
      // It is reachable in principle: element 1's two offsets are `±v` for the
      // same `v`, so a name that rotated by 0 with offsets of opposite sign
      // would move. Rather than search for one, the case is constructed —
      // which is what #37 and #40 record as the answer when a mechanism is
      // unreachable from the variant's own inputs.
      final image = rasterizeScene(
        sceneWith([
          const SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('x', 10),
              SvgAttribute('y', 30),
              SvgAttribute('width', 20),
              SvgAttribute('height', 20),
              SvgAttribute('fill', '#FF0000'),
              // Deliberately asymmetric, and a rotation of exactly zero so the
              // closed-form branch is the one under test.
              SvgAttribute('transform', 'translate(3 -4) rotate(0 40 40)'),
            ],
          ),
        ]),
        width: 80,
        height: 80,
      );
      // (13, 26) to (33, 46). Swapping the offsets would put it at (6, 33).
      expect(pixel(image, 13, 26), [255, 0, 0, 255], reason: 'top-left corner');
      expect(pixel(image, 32, 45), [255, 0, 0, 255], reason: 'bottom-right');
      expect(pixel(image, 12, 26), [0, 0, 0, 0], reason: 'one column left');
      expect(pixel(image, 13, 25), [0, 0, 0, 0], reason: 'one row above');
      // The swapped placement must be empty, or the assertions above could be
      // satisfied by a rectangle large enough to cover both.
      expect(pixel(image, 7, 34), [0, 0, 0, 0], reason: 'the swapped corner');
    });

    test('the rule is drawn last, over the disc, exactly two units thick', () {
      final image = identityRender();
      // The stroke band is y ∈ [39, 41], so rows 39 and 40 are fully covered.
      expect(pixel(image, 40, 39), [255, 255, 0, 255], reason: 'the rule');
      expect(pixel(image, 40, 40), [255, 255, 0, 255], reason: 'the rule');
      // Row 38 is the disc, which the rule is painted over — paint order is
      // document order, and the disc comes third.
      expect(pixel(image, 40, 38), [0, 0, 255, 255], reason: 'the disc');
      expect(pixel(image, 40, 41), [0, 0, 255, 255], reason: 'the disc');
    });

    test('the mask scales the composited group, not each shape', () {
      // Hidden-state #33. At (14, 70) the mask's circular edge cuts the pixel,
      // and **two** opaque shapes reach it — the background rect and the bar,
      // which spans x ∈ [10, 90] and y ∈ [30, 110]. Masking per shape would
      // apply the mask twice and lift the alpha above what one shape gives.
      //
      // The expected value is taken from a scene holding only the background,
      // so nothing here depends on the mask's own coverage number.
      final masked = rasterizeScene(
        buildBauhausScene(name: '', colors: palette, size: 80),
        width: 80,
        height: 80,
      );
      final backgroundOnly = rasterizeScene(
        SvgNode(
          SvgElement.svg,
          attributes: const [SvgAttribute('viewBox', '0 0 80 80')],
          children: const [
            SvgNode(
              SvgElement.mask,
              attributes: [
                SvgAttribute('id', 'm'),
                SvgAttribute('width', 80),
                SvgAttribute('height', 80),
              ],
              children: [
                SvgNode(
                  SvgElement.rect,
                  attributes: [
                    SvgAttribute('width', 80),
                    SvgAttribute('height', 80),
                    SvgAttribute('rx', 160),
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
                    SvgAttribute('width', 80),
                    SvgAttribute('height', 80),
                    SvgAttribute('fill', '#FF0000'),
                  ],
                ),
              ],
            ),
          ],
        ),
        width: 80,
        height: 80,
      );
      final alpha = pixel(masked, 14, 70)[3];
      expect(
        alpha,
        pixel(backgroundOnly, 14, 70)[3],
        reason: 'two stacked shapes must not be masked twice',
      );
      // And the pixel has to be a partially covered one, or the assertion is
      // satisfied by 0 == 0 or 255 == 255 and proves nothing.
      expect(alpha, greaterThan(0));
      expect(alpha, lessThan(255));
    });

    test('an empty palette draws nothing and does not throw', () {
      // Five of the six variants degrade this way; `sunset` is the one that
      // paints black instead, and `beam` is the one that throws. `bauhaus`
      // loses three `fill`s and one `stroke`, so nothing is painted at all.
      final image = rasterizeScene(
        buildBauhausScene(name: 'Clara Barton', colors: const [], size: 80),
        width: 80,
        height: 80,
      );
      expect(image.bytes.every((b) => b == 0), isTrue);
    });

    test('a rotated bar antialiases where an unrotated one does not', () {
      // The complement of the zero-hash case: `Clara Barton` rotates by 191°,
      // so the bar's edges fall between pixels and partial coverage has to
      // appear. A transform silently dropped would give the sharp picture here
      // too, and every other assertion in this file would still pass.
      final image = rasterizeScene(
        buildBauhausScene(
          name: 'Clara Barton',
          colors: palette,
          size: 80,
          square: true,
        ),
        width: 80,
        height: 80,
      );
      final blended = <List<int>>[];
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          final p = pixel(image, x, y);
          // Opaque, but not one of the four palette colours: a blend of two.
          final isPalette =
              (p[0] == 255 && p[1] == 0 && p[2] == 0) ||
              (p[0] == 0 && p[1] == 255 && p[2] == 0) ||
              (p[0] == 0 && p[1] == 0 && p[2] == 255) ||
              (p[0] == 255 && p[1] == 255 && p[2] == 0);
          if (p[3] == 255 && !isPalette) blended.add(p);
        }
      }
      expect(blended, isNotEmpty, reason: 'the bar must be antialiased');
    });
  });

  group('goldens lock the verified state', () {
    // The assertions above are what make these evidence — a golden generated
    // from the code under test can only catch a regression. There is
    // deliberately no empty-palette golden: `bauhaus` renders it fully
    // transparent, and freezing a blank as correct is the failure #40 found.
    final cases = <String, RasterImage Function()>{
      'bauhaus-clara-default': () => rasterizeScene(
        buildBauhausScene(
          name: 'Clara Barton',
          colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
          size: 80,
        ),
        width: 80,
        height: 80,
      ),
      'bauhaus-alice-pair': () => rasterizeScene(
        buildBauhausScene(
          name: 'Alice',
          colors: const ['#000000', '#FFFFFF'],
          size: 80,
        ),
        width: 80,
        height: 80,
      ),
      // The empty name hashes to 0, so every transform is the identity — the
      // only bauhaus render whose edges all land on pixel boundaries.
      'bauhaus-empty-name': () => rasterizeScene(
        buildBauhausScene(
          name: '',
          colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
          size: 80,
        ),
        width: 80,
        height: 80,
      ),
      'bauhaus-clara-square': () => rasterizeScene(
        buildBauhausScene(
          name: 'Clara Barton',
          colors: const ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'],
          size: 80,
          square: true,
        ),
        width: 80,
        height: 80,
      ),
    };

    cases.forEach((key, build) {
      test('$key is byte-identical', () {
        final actual = build();
        final golden = File('test/goldens/$key.rgba').readAsBytesSync();
        expectGoldenIdentical(
          RgbaImage(actual.width, actual.height, actual.bytes),
          RgbaImage(80, 80, golden),
          reason: key,
        );
      });
    });

    test('the goldens are not all the same image', () {
      // A generator bug writing one render four times would satisfy every
      // other assertion in this group.
      final bytes = cases.keys
          .map(
            (k) => base64Encode(File('test/goldens/$k.rgba').readAsBytesSync()),
          )
          .toSet();
      expect(bytes, hasLength(cases.length));
    });
  });
}
