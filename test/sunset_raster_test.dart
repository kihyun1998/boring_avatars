import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/sunset.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// Layer 3 for `sunset`.
///
/// The picture is two vertical gradients stacked, so it is checked against the
/// interpolation *formula* rather than against a golden: the colour at row `y`
/// follows from the two stop colours and `y` alone, and nothing in this package
/// gets a say in that. The golden then locks the verified state.
void main() {
  const palette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];
  const size = 80;

  RasterImage render(
    String name,
    List<String> colours, {
    bool square = false,
  }) => rasterizeScene(
    buildSunsetScene(name: name, colors: colours, size: size, square: square),
    width: size,
    height: size,
  );

  List<int> px(RasterImage img, int x, int y) {
    final i = (y * img.width + x) * 4;
    return img.bytes.sublist(i, i + 4);
  }

  List<int> rgb(String hex) => [
    int.parse(hex.substring(1, 3), radix: 16),
    int.parse(hex.substring(3, 5), radix: 16),
    int.parse(hex.substring(5, 7), radix: 16),
  ];

  group('the gradients follow the formula, not a golden', () {
    final image = render('Clara Barton', palette);
    final stops = sunsetColors('Clara Barton', palette);

    test('every row matches an exact sRGB interpolation of its two stops', () {
      var checked = 0;
      // Upstream declares `userSpaceOnUse` from y=0 to y=40 and y=40 to y=80,
      // with stops at offset 0 and 1. So the colour at row y is the two stop
      // colours mixed by (y + 0.5) / 40 — sampled at the pixel centre, mixed
      // component-wise in sRGB because that is SVG's default, and rounded once.
      for (var y = 0; y < size; y++) {
        final top = y < 40;
        final from = rgb(stops[top ? 0 : 2]!);
        final to = rgb(stops[top ? 1 : 3]!);
        final t = (y + 0.5 - (top ? 0 : 40)) / 40;
        final expected = [
          for (var c = 0; c < 3; c++) (from[c] + (to[c] - from[c]) * t).round(),
          255,
        ];
        // x = 40 is the centre column. Rows 0 and 79 land on the mask's own
        // curve even there and come back at alpha 254, so the comparison would
        // be measuring the mask rather than the gradient; they are the only two
        // skipped, and the count below is what says so.
        if (px(image, 40, y)[3] != 255) continue;
        expect(px(image, 40, y), expected, reason: 'row $y');
        checked++;
      }
      // **Without this the test cannot fail.** It is a bare loop behind a
      // `continue`, so an all-transparent image executes zero assertions and
      // passes — which is precisely the bug #40 fixed (every sunset render came
      // out blank) leaving its own proof green.
      expect(checked, size - 2, reason: 'only rows 0 and 79 may be skipped');
    });

    test(
      'the gradient is vertical — a row is one colour all the way across',
      () {
        for (final y in [5, 12, 25, 38, 41, 55, 68, 74]) {
          final colours = <String>{};
          for (var x = 20; x < 60; x++) {
            if (px(image, x, y)[3] != 255) continue;
            colours.add(px(image, x, y).join(','));
          }
          expect(colours, hasLength(1), reason: 'row $y varies across x');
        }
      },
    );

    test('the two halves are separate gradients, not one continuous ramp', () {
      // Row 39 is 39.5/40 of the way through the *first* gradient; row 40 is
      // 0.5/40 into the *second*. A port that read one gradient spanning 0..80
      // would put a smooth ramp across the join and still pass every
      // "is it linear" check above, because each half would still be linear.
      double mix(int from, int to, double t) => from + (to - from) * t;

      final endOfFirst = [
        for (var c = 0; c < 3; c++)
          mix(rgb(stops[0]!)[c], rgb(stops[1]!)[c], 39.5 / 40).round(),
        255,
      ];
      final startOfSecond = [
        for (var c = 0; c < 3; c++)
          mix(rgb(stops[2]!)[c], rgb(stops[3]!)[c], 0.5 / 40).round(),
        255,
      ];

      expect(px(image, 40, 39), endOfFirst);
      expect(px(image, 40, 40), startOfSecond);
      // …and the join is a jump, not a continuation.
      expect(endOfFirst, isNot(startOfSecond));
    });

    test('the mask still cuts the corners away', () {
      for (final corner in const [(0, 0), (79, 0), (0, 79), (79, 79)]) {
        expect(px(image, corner.$1, corner.$2), [0, 0, 0, 0]);
      }
    });
  });

  group('an empty palette paints black, not nothing', () {
    // The other five variants answer an empty palette by dropping `fill`, which
    // draws nothing at all. `sunset` drops `stop-color`, and SVG's initial value
    // for that is black — so the avatar is a solid black disc. Confirmed in
    // Chrome before it was implemented.
    test('the disc is solid black and fully opaque', () {
      final image = render('Clara Barton', const []);
      for (final point in const [(40, 5), (40, 40), (40, 74), (10, 40)]) {
        expect(px(image, point.$1, point.$2), [0, 0, 0, 255], reason: '$point');
      }
    });

    test('and the corners are still cut, so it is a disc and not a square', () {
      final image = render('Clara Barton', const []);
      expect(px(image, 0, 0), [0, 0, 0, 0]);
    });
  });

  group('the scene seam still refuses what it cannot draw', () {
    SvgNode wrap(List<SvgNode> defs, String fill) => SvgNode(
      SvgElement.svg,
      attributes: const [SvgAttribute('viewBox', '0 0 8 8')],
      children: [
        const SvgNode(
          SvgElement.mask,
          attributes: [
            SvgAttribute('id', 'm'),
            SvgAttribute('mask-type', 'alpha'),
          ],
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                SvgAttribute('width', 8),
                SvgAttribute('height', 8),
                SvgAttribute('fill', '#FFFFFF'),
              ],
            ),
          ],
        ),
        SvgNode(
          SvgElement.g,
          attributes: const [SvgAttribute('mask', 'url(#m)')],
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                const SvgAttribute('width', 8),
                const SvgAttribute('height', 8),
                SvgAttribute('fill', fill),
              ],
            ),
          ],
        ),
        SvgNode(SvgElement.defs, children: defs),
      ],
    );

    SvgNode gradient(List<SvgAttribute> attributes) => SvgNode(
      SvgElement.linearGradient,
      attributes: attributes,
      children: const [
        SvgNode(
          SvgElement.stop,
          attributes: [SvgAttribute('stop-color', '#FF0000')],
        ),
        SvgNode(
          SvgElement.stop,
          attributes: [
            SvgAttribute('offset', 1),
            SvgAttribute('stop-color', '#0000FF'),
          ],
        ),
      ],
    );

    void expectRejected(SvgNode scene) => expect(
      () => rasterizeScene(scene, width: 8, height: 8),
      throwsA(isA<UnsupportedSceneError>()),
    );

    test('a fill naming a gradient that is not declared is refused', () {
      // A dangling paint reference makes a browser draw *nothing* — measured,
      // 0,0,0,0 everywhere, because a CSS <url> with no fallback and an invalid
      // target resolves to . Throwing is still right: a blank is
      // indistinguishable from the paint never having been read at all, which
      // is the bug #40 fixed and it was silent for a whole variant.
      expectRejected(
        wrap([
          gradient(const [
            SvgAttribute('id', 'here'),
            SvgAttribute('x1', 0),
            SvgAttribute('y1', 0),
            SvgAttribute('x2', 0),
            SvgAttribute('y2', 8),
            SvgAttribute('gradientUnits', 'userSpaceOnUse'),
          ]),
        ], 'url(#elsewhere)'),
      );
    });

    test('objectBoundingBox gradient units are refused', () {
      // The default in SVG, and it reinterprets x1/y1/x2/y2 as fractions of the
      // shape's box — so the same numbers paint a different picture.
      expectRejected(
        wrap([
          gradient(const [
            SvgAttribute('id', 'g'),
            SvgAttribute('x1', 0),
            SvgAttribute('y1', 0),
            SvgAttribute('x2', 0),
            SvgAttribute('y2', 1),
            SvgAttribute('gradientUnits', 'objectBoundingBox'),
          ]),
        ], 'url(#g)'),
      );
    });

    test('an unknown attribute on the gradient is refused', () {
      expectRejected(
        wrap([
          gradient(const [
            SvgAttribute('id', 'g'),
            SvgAttribute('x1', 0),
            SvgAttribute('y1', 0),
            SvgAttribute('x2', 0),
            SvgAttribute('y2', 8),
            SvgAttribute('gradientUnits', 'userSpaceOnUse'),
            SvgAttribute('spreadMethod', 'reflect'),
          ]),
        ], 'url(#g)'),
      );
    });

    test('a <defs> holding something that is not a paint server is refused', () {
      // This is the branch `marble` hits **first**. Since #40 the paint servers
      // are read before the shapes, so marble's `<filter>` throws here — ahead
      // of its `style="mix-blend-mode:overlay"`, its `transform` and its
      // `filter="url(…)"`. Whoever implements marble meets this message before
      // they can discover whether anything else validates.
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.filter,
            attributes: [SvgAttribute('id', 'f')],
            children: [
              SvgNode(
                SvgElement.feGaussianBlur,
                attributes: [SvgAttribute('stdDeviation', 7)],
              ),
            ],
          ),
        ], '#FF0000'),
      );
    });

    test('an unknown attribute on a <stop> is refused', () {
      // `stop-opacity` is real SVG that changes the picture, and the allow-list
      // is the only thing refusing it. Nothing tested that the list was closed.
      expectRejected(
        wrap([
          SvgNode(
            SvgElement.linearGradient,
            attributes: const [
              SvgAttribute('id', 'g'),
              SvgAttribute('x1', 0),
              SvgAttribute('y1', 0),
              SvgAttribute('x2', 0),
              SvgAttribute('y2', 8),
              SvgAttribute('gradientUnits', 'userSpaceOnUse'),
            ],
            children: const [
              SvgNode(
                SvgElement.stop,
                attributes: [
                  SvgAttribute('stop-color', '#FF0000'),
                  SvgAttribute('stop-opacity', '0.5'),
                ],
              ),
              SvgNode(
                SvgElement.stop,
                attributes: [
                  SvgAttribute('offset', 1),
                  SvgAttribute('stop-color', '#0000FF'),
                ],
              ),
            ],
          ),
        ], 'url(#g)'),
      );
    });

    test('a <linearGradient> with no id is refused, not skipped', () {
      expectRejected(
        wrap([
          gradient(const [
            SvgAttribute('x1', 0),
            SvgAttribute('y1', 0),
            SvgAttribute('x2', 0),
            SvgAttribute('y2', 8),
            SvgAttribute('gradientUnits', 'userSpaceOnUse'),
          ]),
        ], '#FF0000'),
      );
    });

    test('an unknown attribute on <defs> itself is refused', () {
      expectRejected(
        SvgNode(
          SvgElement.svg,
          attributes: const [SvgAttribute('viewBox', '0 0 8 8')],
          children: [
            ...wrap(const [], '#FF0000').children.take(2),
            const SvgNode(
              SvgElement.defs,
              attributes: [SvgAttribute('transform', 'scale(2)')],
            ),
          ],
        ),
      );
    });

    test('a gradient with no stops is refused', () {
      expectRejected(
        wrap([
          const SvgNode(
            SvgElement.linearGradient,
            attributes: [
              SvgAttribute('id', 'g'),
              SvgAttribute('x1', 0),
              SvgAttribute('y1', 0),
              SvgAttribute('x2', 0),
              SvgAttribute('y2', 8),
              SvgAttribute('gradientUnits', 'userSpaceOnUse'),
            ],
          ),
        ], 'url(#g)'),
      );
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
    final cases = <String, RasterImage Function()>{
      'sunset-clara-default': () => render('Clara Barton', palette),
      'sunset-empty-palette': () => render('Clara Barton', const []),
      // A second name, because `sunset` was rasterised for one only — and the
      // corpus name that would have caught the url-fragment divergence is not
      // `Clara Barton`. `pixel` and `ring` each carry a second-name golden.
      'sunset-hangul': () => render('박기현', palette),
      'sunset-clara-square': () =>
          render('Clara Barton', palette, square: true),
    };

    cases.forEach((key, build) {
      test('$key is byte-identical', () {
        final actual = build();
        final golden = File('test/goldens/$key.rgba').readAsBytesSync();
        expectGoldenIdentical(
          RgbaImage(actual.width, actual.height, actual.bytes),
          RgbaImage(size, size, golden),
          reason: key,
        );
      });
    });

    test('the goldens are not all the same image', () {
      final bytes = cases.keys
          .map(
            (k) => base64Encode(File('test/goldens/$k.rgba').readAsBytesSync()),
          )
          .toSet();
      expect(bytes, hasLength(cases.length));
    });
  });
}
