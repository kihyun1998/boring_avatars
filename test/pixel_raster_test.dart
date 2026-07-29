import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/raster/path.dart';
import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/pixel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// Layer 3 for `pixel`.
///
/// A golden that only agrees with itself proves nothing, so the geometry is
/// asserted independently first — which tile lands on which pixel, where the
/// circular mask cuts, what the corners do — and the golden then locks that
/// verified state against regression.
void main() {
  const palette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];

  RasterImage render(String name, List<String> colours) => rasterizeScene(
    buildPixelScene(name: name, colors: colours, size: 80),
    width: 80,
    height: 80,
  );

  List<int> px(RasterImage img, int x, int y) {
    final i = (y * img.width + x) * 4;
    return img.bytes.sublist(i, i + 4);
  }

  List<int> rgbOf(String hex) => [
    int.parse(hex.substring(1, 3), radix: 16),
    int.parse(hex.substring(3, 5), radix: 16),
    int.parse(hex.substring(5, 7), radix: 16),
  ];

  group('the geometry is right, independently of any golden', () {
    final image = render('Clara Barton', palette);
    final colours = pixelColors('Clara Barton', palette);

    test('the centre pixel carries the tile that covers it', () {
      // (40, 40) falls in the tile at x=40, y=40, which upstream fills from
      // colour index 25. Fully inside the circle, so alpha is opaque.
      final expected = rgbOf(colours[25]!);
      expect(px(image, 40, 40), [...expected, 255]);
    });

    test(
      'a different tile shows a different colour where the palette differs',
      () {
        // (5, 45) is in the tile at x=0, y=40 — colour index 11.
        final expected = rgbOf(colours[11]!);
        expect(px(image, 5, 45), [...expected, 255]);
      },
    );

    test('the corners are cut away by the circular mask', () {
      // rx is 160 on an 80-wide rect, clamped by SVG to 40 — a circle. The
      // four corners sit outside it.
      for (final c in [
        [0, 0],
        [79, 0],
        [0, 79],
        [79, 79],
      ]) {
        expect(px(image, c[0], c[1]), [0, 0, 0, 0], reason: '${c[0]},${c[1]}');
      }
    });

    test('the mask edge is antialiased, not a hard cut', () {
      // Somewhere along the boundary there must be partial alpha; a mask that
      // only ever produced 0 or 255 would mean coverage was never computed.
      var partial = 0;
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          final a = px(image, x, y)[3];
          if (a > 0 && a < 255) partial++;
        }
      }
      expect(partial, greaterThan(100), reason: 'edge pixels: $partial');
    });

    test('an unfilled tile draws nothing where it would have shown', () {
      // Tile 0 has no fill (hidden-state #17). It sits at x 0–10, y 0–10,
      // which the circle excludes anyway — so this asserts the *mechanism*:
      // a rect with a null fill contributes no coverage at all.
      final withFill = rasterizeMaskedShapes(
        width: 4,
        height: 4,
        shapes: [RasterRect(0, 0, 4, 4, SolidPaint.hex('#FF0000'))],
        mask: RoundedRectMask(x: 0, y: 0, width: 4, height: 4, rx: 0),
      );
      final withoutFill = rasterizeMaskedShapes(
        width: 4,
        height: 4,
        shapes: [RasterRect(0, 0, 4, 4, null)],
        mask: RoundedRectMask(x: 0, y: 0, width: 4, height: 4, rx: 0),
      );
      expect(withFill.bytes.any((b) => b != 0), isTrue);
      expect(withoutFill.bytes.every((b) => b == 0), isTrue);
    });
  });

  group('SVG rx clamping, which is where a naive port goes wrong', () {
    test('a radius larger than half the side is clamped, not scaled', () {
      final mask = RoundedRectMask(x: 0, y: 0, width: 80, height: 80, rx: 160);
      expect(mask.radius, 40, reason: 'SVG clamps to half the side');
    });

    test('square drops the radius entirely, filling the corners', () {
      final squared = rasterizeScene(
        buildPixelScene(
          name: 'Clara Barton',
          colors: palette,
          size: 80,
          square: true,
        ),
        width: 80,
        height: 80,
      );
      // The top-left corner is tile 0, which has no fill — so check a corner
      // that does: bottom-right is the tile at x=70, y=70, index 63.
      final expected = rgbOf(pixelColors('Clara Barton', palette)[63]!);
      expect(px(squared, 79, 79), [...expected, 255]);
      // And the round version leaves that same corner empty.
      expect(px(render('Clara Barton', palette), 79, 79), [0, 0, 0, 0]);
    });
  });

  group('the seam fails loudly instead of drawing something plausible', () {
    // Found by the completeness pass: an unhandled shape rendered blank and an
    // ignored `transform` drew the rect square and unrotated — a wrong picture
    // a golden would then freeze. Blank is bad; plausible-but-wrong is worse.
    SvgNode wrap(List<SvgNode> content, {String viewBox = '0 0 4 4'}) =>
        SvgNode(
          SvgElement.svg,
          attributes: [SvgAttribute('viewBox', viewBox)],
          children: [
            const SvgNode(
              SvgElement.mask,
              // The id matters: the group below references it, and since #37
              // an unmatched reference throws. Without it every assertion in
              // this group would pass on that throw instead of on the one it
              // names — which is how a mutation removing a *different* guard
              // stayed green.
              attributes: [
                SvgAttribute('id', 'm'),
                SvgAttribute('width', 4),
                SvgAttribute('height', 4),
              ],
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
            SvgNode(
              SvgElement.g,
              attributes: const [SvgAttribute('mask', 'url(#m)')],
              children: content,
            ),
          ],
        );

    void expectRejected(SvgNode scene, {int size = 4}) => expect(
      () => rasterizeScene(scene, width: size, height: size),
      throwsA(isA<UnsupportedSceneError>()),
    );

    test('a transformed rect is refused, not drawn unrotated', () {
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', 2),
              SvgAttribute('height', 2),
              SvgAttribute('transform', 'translate(2 2) rotate(45 2 2)'),
              SvgAttribute('fill', '#FF0000'),
            ],
          ),
        ]),
      );
    });

    test('a rect with rx is refused — the corners would be square', () {
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', 2),
              SvgAttribute('height', 2),
              SvgAttribute('rx', 1),
              SvgAttribute('fill', '#FF0000'),
            ],
          ),
        ]),
      );
    });

    test('the shapes no variant has needed yet are refused', () {
      // `path` and `circle` became drawable with `ring`; `line` is still
      // nobody's, and arrives with `bauhaus`. Narrowing this list is how the
      // seam records what has actually been implemented.
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.line,
            attributes: [SvgAttribute('fill', '#FF0000')],
          ),
        ]),
      );
    });

    test('a drawable element missing its geometry is refused, not crashed', () {
      // The seam's contract is a *named* failure. A `!` on a missing attribute
      // would throw a null-check TypeError instead, which says nothing about
      // which element was malformed — the failure mode this group exists to
      // rule out, one level down.
      for (final node in const [
        SvgNode(SvgElement.path, attributes: [SvgAttribute('fill', '#F00000')]),
        SvgNode(
          SvgElement.circle,
          attributes: [SvgAttribute('fill', '#F00000')],
        ),
        SvgNode(SvgElement.rect, attributes: [SvgAttribute('width', 2)]),
      ]) {
        expectRejected(wrap([node]));
      }
    });

    test('a viewBox that does not match the target is refused, not cropped', () {
      // ring's viewBox is 90 wide. Rendering it at 80 used to crop in silence.
      expectRejected(wrap(const [], viewBox: '0 0 90 90'));
    });

    test('a luminance mask that is not white is refused', () {
      // pixel declares mask-type="alpha"; the other five declare nothing, which
      // means luminance. They are all filled #FFFFFF, where the two agree.
      final scene = SvgNode(
        SvgElement.svg,
        attributes: const [SvgAttribute('viewBox', '0 0 4 4')],
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
                  SvgAttribute('fill', '#000000'),
                ],
              ),
            ],
          ),
        ],
      );
      expectRejected(scene);
    });
  });

  group('colour parsing refuses what it cannot draw correctly', () {
    test('forms a browser accepts but this cannot are null, not guesses', () {
      for (final bad in [
        '#F00',
        'red',
        'rgb(255,0,0)',
        '#FF0000FF',
        ' #FF0000',
      ]) {
        expect(parseHexColour(bad), isNull, reason: bad);
      }
    });

    test('a sign no longer turns punctuation into a colour', () {
      // int.tryParse accepts a sign, so '+12345' used to parse as #012345.
      expect(parseHexColour('+12345'), isNull);
      expect(parseHexColour('-00001'), isNull);
    });

    test('the forms upstream actually produces still parse', () {
      expect(parseHexColour('#FF0000')?.r, 255);
      expect(parseHexColour('#ff0000')?.r, 255);
      expect(parseHexColour('146A7C')?.g, 0x6A);
    });
  });

  group('mechanisms pixel does not exercise, pinned directly', () {
    // The refuting pass found four wrong rasterizers that passed the whole
    // suite. Every one of them was invisible for the same reason: `pixel` is
    // an 8x8 grid of integer-aligned tiles under a square mask, so the code
    // paths below are never taken by it — and the variants that come next take
    // all of them.

    test('rect coverage is exact, not rounded to the mask', () {
      // Deleting `rowOverlap * colOverlap` entirely used to pass everything,
      // because a tile edge at a multiple of 10 makes that factor exactly 1.
      final img = rasterizeMaskedShapes(
        width: 2,
        height: 1,
        // Covers 30% of pixel 0 and none of pixel 1.
        shapes: [RasterRect(0, 0, 0.3, 1, SolidPaint.hex('#FF0000'))],
        mask: RoundedRectMask(x: 0, y: 0, width: 2, height: 1, rx: 0),
      );
      expect(img.bytes.sublist(0, 4), [
        255,
        0,
        0,
        77,
      ], reason: '0.3 coverage is alpha 76.5 -> 77');
      expect(img.bytes.sublist(4, 8), [0, 0, 0, 0]);
    });

    test('a sub-pixel rect covers proportionally in both axes', () {
      final img = rasterizeMaskedShapes(
        width: 1,
        height: 1,
        shapes: [RasterRect(0.25, 0.5, 0.5, 0.5, SolidPaint.hex('#FFFFFF'))],
        mask: RoundedRectMask(x: 0, y: 0, width: 1, height: 1, rx: 0),
      );
      // 0.5 wide x 0.5 tall = 0.25 coverage -> alpha 64.
      expect(img.bytes[3], 64);
    });

    test('rx is clamped by the shorter side, not just the width', () {
      // `min(rx, width/2)` alone agrees with the correct formula on every
      // square mask — which is every mask the six variants have.
      final wide = RoundedRectMask(x: 0, y: 0, width: 100, height: 20, rx: 30);
      expect(wide.radius, 10, reason: 'height/2 is the binding constraint');
      final tall = RoundedRectMask(x: 0, y: 0, width: 20, height: 100, rx: 30);
      expect(tall.radius, 10, reason: 'width/2 is the binding constraint');
    });

    test('a shape outside the masked group is refused, not dropped', () {
      // **This assertion was inverted in #37.** It used to require that such a
      // rect be silently ignored — but a browser *draws* it, unmasked, so
      // dropping it produces a picture the reference does not. Nothing in the
      // six draws outside the mask group, so both readings agreed on every
      // real scene and only one of them agreed with SVG.
      final scene = SvgNode(
        SvgElement.svg,
        attributes: const [SvgAttribute('viewBox', '0 0 2 2')],
        children: const [
          SvgNode(
            SvgElement.mask,
            attributes: [SvgAttribute('width', 2), SvgAttribute('height', 2)],
            children: [
              SvgNode(
                SvgElement.rect,
                attributes: [
                  SvgAttribute('width', 2),
                  SvgAttribute('height', 2),
                  SvgAttribute('fill', '#FFFFFF'),
                ],
              ),
            ],
          ),
          // Outside the masked group — must not be drawn.
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', 2),
              SvgAttribute('height', 2),
              SvgAttribute('fill', '#FF0000'),
            ],
          ),
          SvgNode(
            SvgElement.g,
            attributes: [SvgAttribute('mask', 'url(#m)')],
            children: [],
          ),
        ],
      );
      expect(
        () => rasterizeScene(scene, width: 2, height: 2),
        throwsA(isA<UnsupportedSceneError>()),
        reason: 'the only rect sits outside the mask group',
      );
    });

    test('a mask-type this rasterizer cannot honour is refused', () {
      // pixel declares "alpha". Deleting the guard passed the suite because
      // nothing ever declared anything else.
      final scene = SvgNode(
        SvgElement.svg,
        attributes: const [SvgAttribute('viewBox', '0 0 2 2')],
        children: const [
          SvgNode(
            SvgElement.mask,
            attributes: [
              SvgAttribute('mask-type', 'luminance'),
              SvgAttribute('width', 2),
              SvgAttribute('height', 2),
            ],
            children: [
              SvgNode(
                SvgElement.rect,
                attributes: [
                  SvgAttribute('width', 2),
                  SvgAttribute('height', 2),
                  SvgAttribute('fill', '#FFFFFF'),
                ],
              ),
            ],
          ),
        ],
      );
      expect(
        () => rasterizeScene(scene, width: 2, height: 2),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('the mask integrator totals the right area', () {
      // πr² is an outside opinion, and this is what it can say: the *average*
      // coverage is right. It is not a per-pixel bound — errors of opposite
      // sign cancel in a sum — so the next test carries that half.
      const r = 40.0;
      final mask = RoundedRectMask(x: 0, y: 0, width: 80, height: 80, rx: 160);
      var area = 0.0;
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          area += mask.coverageAt(x, y);
        }
      }
      final exact = 3.141592653589793 * r * r;
      expect(
        (area - exact).abs(),
        lessThan(0.02),
        reason: 'total disc area err ${(area - exact).abs()}',
      );
    });

    test('and every individual pixel agrees with the other integrator', () {
      // The calibration bar is per pixel, so a per-pixel bound is what it
      // needs. `RoundedRectMask` solves the shape's edge in closed form over 64
      // slices; `polygonCoverage` walks flattened edge crossings over 256. Two
      // different algorithms on the same shape — so this is a cross-check, not
      // the self-check that comparing against our own supersampler would be.
      for (final size in [80, 90]) {
        final mask = RoundedRectMask(
          x: 0,
          y: 0,
          width: size.toDouble(),
          height: size.toDouble(),
          rx: size * 2,
        );
        final polygon = polygonCoverage(
          width: size,
          height: size,
          polygon: RasterPolygon([
            flattenCircle(size / 2, size / 2, size / 2),
          ], SolidPaint.hex('#000000')),
        );
        var worst = 0.0;
        var worstAt = '';
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final d = (mask.coverageAt(x, y) - polygon[y * size + x]).abs();
            if (d > worst) {
              worst = d;
              worstAt = '($x, $y)';
            }
          }
        }
        expect(
          worst * 255,
          lessThan(1.0),
          reason: 'worst per-pixel disagreement at $worstAt, mask $size',
        );
      }
    });
  });

  group('determinism', () {
    test('the same input produces identical bytes on every run', () {
      expect(
        render('Clara Barton', palette).bytes,
        render('Clara Barton', palette).bytes,
      );
    });
  });

  group('goldens lock the verified state', () {
    const cases = <String, (String, List<String>)>{
      'pixel-clara-default': ('Clara Barton', palette),
      'pixel-alice-pair': ('Alice', ['#000000', '#FFFFFF']),
      'pixel-empty-name': ('', ['#FF0000']),
    };

    for (final entry in cases.entries) {
      test('${entry.key} is byte-identical', () {
        final (name, colours) = entry.value;
        final actual = render(name, colours);
        final golden = File('test/goldens/${entry.key}.rgba').readAsBytesSync();
        expectGoldenIdentical(
          RgbaImage(actual.width, actual.height, actual.bytes),
          RgbaImage(80, 80, golden),
          reason: entry.key,
        );
      });
    }

    test('the goldens are not all the same image', () {
      // A generator bug that wrote one render three times would otherwise pass
      // every assertion above.
      final bytes = cases.keys
          .map(
            (k) => base64Encode(File('test/goldens/$k.rgba').readAsBytesSync()),
          )
          .toSet();
      expect(bytes, hasLength(cases.length));
    });
  });
}
