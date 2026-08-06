import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/ring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';
import 'support/golden_cases.dart';

/// Layer 3 for `ring`.
///
/// The picture is asserted from its own geometry before any golden is opened:
/// nine bands stacked largest first, so the colour at a point follows from the
/// point's distance to the centre and which side of the horizontal diameter it
/// falls on. That rule comes from upstream's `d` strings, not from our
/// rasterizer, so a wrong arc direction or a wrong paint order fails here — and
/// the golden then locks the verified state against regression.
void main() {
  const palette = ['#92A1C6', '#146A7C', '#F0AB3D', '#C271B4', '#C20D90'];
  const size = 90;

  RasterImage render(
    String name,
    List<String> colours, {
    bool square = false,
  }) => rasterizeScene(
    buildRingScene(name: name, colors: colours, size: size, square: square),
    width: size,
    height: size,
  );

  List<int> px(RasterImage img, int x, int y) {
    final i = (y * img.width + x) * 4;
    return img.bytes.sublist(i, i + 4);
  }

  List<int> opaque(String hex) => [
    int.parse(hex.substring(1, 3), radix: 16),
    int.parse(hex.substring(3, 5), radix: 16),
    int.parse(hex.substring(5, 7), radix: 16),
    255,
  ];

  group('the bands land where the path data says, independently of a golden', () {
    final image = render('Clara Barton', palette);
    final bands = ringColors('Clara Barton', palette);

    // Paint order is document order: the two half-plane rects, then the three
    // radii from 38 inwards split top/bottom, then the centre disc. So a point
    // takes the colour of the smallest band that contains it.
    //
    // Each sample is a pixel whose *four corners* all fall inside one band and
    // inside the mask, so it is fully opaque and exactly one colour — no
    // antialiasing, nothing to round.
    const samples = <String, (int, int, int)>{
      'centre disc (r<23)': (45, 45, 8),
      'r 23–26 above': (45, 20, 6),
      'r 23–26 below': (45, 69, 7),
      'r 26–32 above': (45, 16, 4),
      'r 26–32 below': (45, 73, 5),
      'r 32–38 above': (45, 10, 2),
      'r 32–38 below': (45, 79, 3),
      'outside 38, above': (45, 4, 0),
      'outside 38, below': (45, 85, 1),
    };

    samples.forEach((label, sample) {
      final (x, y, slot) = sample;
      test('$label is slot $slot', () {
        expect(px(image, x, y), opaque(bands[slot]!), reason: label);
      });
    });

    test('the samples really are one band and one band only', () {
      // A sample that straddled a band edge would be an antialiased blend, and
      // the assertion above would then be pinning our blend rather than the
      // geometry. Checked here rather than trusted.
      const radii = [23.0, 26.0, 32.0, 38.0, 45.0];
      samples.forEach((label, sample) {
        final (x, y, _) = sample;
        final distances = [
          for (final cx in [x, x + 1])
            for (final cy in [y, y + 1])
              math.sqrt((cx - 45) * (cx - 45) + (cy - 45.0) * (cy - 45.0)),
        ];
        for (final r in radii) {
          final below = distances.where((d) => d < r).length;
          expect(
            below == 0 || below == 4,
            isTrue,
            reason: '$label straddles r=$r',
          );
        }
        // …and entirely on one side of the diameter.
        expect((y < 45) == (y + 1 <= 45), isTrue, reason: '$label straddles y');
      });
    });

    test('the bands are the right size and are actually concentric', () {
      // The nine samples above all sit on the column x = 45 with about a unit
      // of margin, which is exactly the slack a sub-unit geometry error hides
      // in: a centre disc rasterised 3% small, or every path shifted 0.3px
      // sideways, passes all nine — and is caught only by the goldens, which
      // makes "verified independently of a golden" false where it matters.
      //
      // So the geometry is *measured*. Each boundary is found along 72 rays;
      // one ray locates it only to about a pixel, but the mean over the circle
      // is far sharper — and the mean of the boundary *points* is the centre,
      // which is what a translation moves and a rescale does not.
      const boundaries = [23.0, 26.0, 32.0, 38.0];
      const rays = 72;

      for (final boundary in boundaries) {
        var sumRadius = 0.0, sumX = 0.0, sumY = 0.0, found = 0;
        for (var i = 0; i < rays; i++) {
          final theta = 2 * math.pi * i / rays;
          final dx = math.cos(theta), dy = math.sin(theta);
          final from = boundary - 2.0, to = boundary + 2.0;
          String colourAt(double r) => px(
            image,
            (45 + dx * r).floor(),
            (45 + dy * r).floor(),
          ).toString();
          final inner = colourAt(from), outer = colourAt(to);
          if (inner == outer) continue;

          // The last pure inner sample and the first pure outer one bracket the
          // boundary. Taking either alone is biased by the antialiased pixels
          // between them — about 0.7 units, which is the size of the error this
          // is meant to detect. Their midpoint is not.
          var lastInner = from, firstOuter = to;
          for (var r = from; r <= to; r += 0.02) {
            if (colourAt(r) == inner) lastInner = r;
          }
          for (var r = to; r >= from; r -= 0.02) {
            if (colourAt(r) == outer) firstOuter = r;
          }
          final radius = (lastInner + firstOuter) / 2;
          sumRadius += radius;
          sumX += 45 + dx * radius;
          sumY += 45 + dy * radius;
          found++;
        }
        expect(found, rays, reason: 'r=$boundary was not found on every ray');
        // A pixel grid quantises each ray, so the mean lands about half a pixel
        // out; 0.2 is far tighter than the ~0.7 a single sample could claim,
        // and tight enough that a 3% radius error (0.7 units at r=23) fails.
        expect(
          sumRadius / rays,
          closeTo(boundary, 0.2),
          reason: 'measured radius of the r=$boundary boundary',
        );
        expect(sumX / rays, closeTo(45, 0.1), reason: 'centre x, r=$boundary');
        expect(sumY / rays, closeTo(45, 0.1), reason: 'centre y, r=$boundary');
      }
    });

    test('the drawing as a whole is a disc of radius 45, centred', () {
      // The mask, measured the same way but from alpha alone: total coverage is
      // its area and the alpha-weighted centroid is its centre. A global shift
      // or scale that survived every band check would fail here.
      var area = 0.0, cx = 0.0, cy = 0.0;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final a = px(image, x, y)[3] / 255;
          area += a;
          cx += a * (x + 0.5);
          cy += a * (y + 0.5);
        }
      }
      expect(area, closeTo(math.pi * 45 * 45, 0.5));
      expect(cx / area, closeTo(45, 0.01));
      expect(cy / area, closeTo(45, 0.01));
    });

    test('the mask cuts the corners away completely', () {
      for (final corner in const [(0, 0), (89, 0), (0, 89), (89, 89)]) {
        expect(px(image, corner.$1, corner.$2), [0, 0, 0, 0]);
      }
    });

    test('there is no seam where the two half-planes meet', () {
      // The upper and lower halves abut along y=45 rather than overlapping, and
      // each of the three radii is split into two shapes that abut on the same
      // line. A gap of even one slice would show as an alpha below 255 —
      // hidden-state #24, which is inert here only because the join lands
      // exactly on a pixel boundary.
      for (var x = 0; x < size; x++) {
        for (final y in const [44, 45]) {
          final dx = x + 0.5 - 45, dy = y + 0.5 - 45;
          if (math.sqrt(dx * dx + dy * dy) > 43) continue; // near the mask edge
          expect(px(image, x, y)[3], 255, reason: 'seam at ($x, $y)');
        }
      }
    });

    test('everything well inside the mask is fully opaque', () {
      // The two half-plane rects cover the whole drawing, so alpha is the mask
      // and nothing else. A hole anywhere — a mis-wound contour, a dropped
      // subpath — shows up here.
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final dx = x + 0.5 - 45, dy = y + 0.5 - 45;
          if (math.sqrt(dx * dx + dy * dy) > 43) continue;
          expect(px(image, x, y)[3], 255, reason: 'hole at ($x, $y)');
        }
      }
    });
  });

  group('an empty palette draws nothing at all', () {
    test('every pixel is transparent, and it does not throw', () {
      final image = render('Clara Barton', const []);
      expect(image.bytes.every((b) => b == 0), isTrue);
    });
  });

  group('square replaces the circular mask with the full square', () {
    test('the corners are painted rather than cut', () {
      final image = render('Clara Barton', palette, square: true);
      final bands = ringColors('Clara Barton', palette);
      expect(px(image, 0, 0), opaque(bands[0]!));
      expect(px(image, 89, 0), opaque(bands[0]!));
      expect(px(image, 0, 89), opaque(bands[1]!));
      expect(px(image, 89, 89), opaque(bands[1]!));
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

  group('a circle is read from its own attributes, not a neighbour\'s', () {
    test('cx and cy are not interchangeable', () {
      // `ring`'s only circle is at (45, 45), so swapping cx for cy in the scene
      // reader changes nothing anywhere in this variant — a mutation doing
      // exactly that survived the whole suite. Nothing in the six variants
      // would catch it either; `bauhaus`'s circle is also centred. So the case
      // is made rather than waited for.
      final scene = SvgNode(
        SvgElement.svg,
        attributes: const [
          SvgAttribute('viewBox', '0 0 40 40'),
          SvgAttribute('width', 40),
          SvgAttribute('height', 40),
        ],
        children: const [
          SvgNode(
            SvgElement.mask,
            attributes: [
              SvgAttribute('id', 'm'),
              SvgAttribute('mask-type', 'alpha'),
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
                SvgElement.circle,
                attributes: [
                  SvgAttribute('cx', 30),
                  SvgAttribute('cy', 10),
                  SvgAttribute('r', 5),
                  SvgAttribute('fill', '#FF0000'),
                ],
              ),
            ],
          ),
        ],
      );
      final image = rasterizeScene(scene, width: 40, height: 40);
      expect(px(image, 30, 10), [255, 0, 0, 255], reason: 'the circle');
      expect(px(image, 10, 30), [0, 0, 0, 0], reason: 'cx and cy transposed');
      expect(px(image, 30, 30), [0, 0, 0, 0], reason: 'cy read as cx');
      expect(px(image, 10, 10), [0, 0, 0, 0], reason: 'cx read as cy');
    });
  });

  group('the seam checks containers too, not only the shapes', () {
    // Found by the completeness pass: `_collectShapes` validated attributes
    // only on elements it knew how to *draw*, and walked through `<svg>`, `<g>`
    // and `<defs>` unchecked. Every scene in this package hangs its content off
    // `<g mask="url(#…)">`, so the hole was invisible from `pixel` and `ring` —
    // and `beam`, the next variant, wraps its entire face in a transformed `g`.
    SvgNode wrap(
      List<SvgNode> content, {
      List<SvgAttribute> group = const [],
    }) => SvgNode(
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
          attributes: [const SvgAttribute('mask', 'url(#m)'), ...group],
          children: content,
        ),
      ],
    );

    const redSquare = SvgNode(
      SvgElement.rect,
      attributes: [
        SvgAttribute('width', 4),
        SvgAttribute('height', 4),
        SvgAttribute('fill', '#FF0000'),
      ],
    );

    void expectRejected(SvgNode scene) => expect(
      () => rasterizeScene(scene, width: 8, height: 8),
      throwsA(isA<UnsupportedSceneError>()),
    );

    test('a transform on the group is applied, not ignored and not refused', () {
      // This test used to assert the *refusal* of a group transform, because
      // ignoring one drew `beam`'s face 4.5 units off and unrotated while
      // throwing nothing (hidden-state #30). #38 implements composition, so the
      // subject flips: the guard is discharged by making the thing work, and
      // what has to be pinned now is that it really moves the content.
      //
      // A 4×4 red square at the origin, pushed 4 right and 4 down by the group
      // alone, must land in the far quadrant of the 8×8 canvas.
      final image = rasterizeScene(
        wrap(
          const [redSquare],
          group: const [SvgAttribute('transform', 'translate(4 4)')],
        ),
        width: 8,
        height: 8,
      );
      expect(image.bytes.sublist((5 * 8 + 5) * 4, (5 * 8 + 5) * 4 + 4), [
        255,
        0,
        0,
        255,
      ], reason: 'moved into the far quadrant');
      expect(image.bytes.sublist((1 * 8 + 1) * 4, (1 * 8 + 1) * 4 + 4), [
        0,
        0,
        0,
        0,
      ], reason: 'and left the near one empty');
    });

    test('an opacity on the group is refused', () {
      expectRejected(
        wrap(const [redSquare], group: const [SvgAttribute('opacity', '0.25')]),
      );
    });

    test('an unknown attribute on the root <svg> is refused', () {
      expectRejected(
        SvgNode(
          SvgElement.svg,
          attributes: const [
            SvgAttribute('viewBox', '0 0 8 8'),
            SvgAttribute('transform', 'scale(2)'),
          ],
          children: wrap(const [redSquare]).children,
        ),
      );
    });

    test('a maskUnits this rasterizer cannot honour is refused', () {
      // `objectBoundingBox` reinterprets the mask's x/y/width/height as
      // fractions of the bounding box, so honouring the attribute name while
      // reading the numbers as user units draws a mask of the wrong size.
      expectRejected(
        SvgNode(
          SvgElement.svg,
          attributes: const [SvgAttribute('viewBox', '0 0 8 8')],
          children: const [
            SvgNode(
              SvgElement.mask,
              attributes: [
                SvgAttribute('id', 'm'),
                SvgAttribute('mask-type', 'alpha'),
                SvgAttribute('maskUnits', 'objectBoundingBox'),
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
              attributes: [SvgAttribute('mask', 'url(#m)')],
              children: [redSquare],
            ),
          ],
        ),
      );
    });

    test('a mask region that would clip its own shape is refused', () {
      expectRejected(
        SvgNode(
          SvgElement.svg,
          attributes: const [SvgAttribute('viewBox', '0 0 8 8')],
          children: const [
            SvgNode(
              SvgElement.mask,
              attributes: [
                SvgAttribute('id', 'm'),
                SvgAttribute('mask-type', 'alpha'),
                SvgAttribute('width', 4),
                SvgAttribute('height', 4),
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
              attributes: [SvgAttribute('mask', 'url(#m)')],
              children: [redSquare],
            ),
          ],
        ),
      );
    });

    test('a group referencing a mask that is not there is refused', () {
      // SVG 1.1 renders nothing for a dangling reference and SVG 2 renders
      // unmasked; treating it as *our* mask matches neither.
      expectRejected(
        SvgNode(
          SvgElement.svg,
          attributes: const [SvgAttribute('viewBox', '0 0 8 8')],
          children: const [
            SvgNode(
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
              attributes: [SvgAttribute('mask', 'url(#somewhere-else)')],
              children: [redSquare],
            ),
          ],
        ),
      );
    });

    test('an unknown attribute on the <mask> is refused', () {
      expectRejected(
        SvgNode(
          SvgElement.svg,
          attributes: const [SvgAttribute('viewBox', '0 0 8 8')],
          children: const [
            SvgNode(
              SvgElement.mask,
              attributes: [
                SvgAttribute('id', 'm'),
                SvgAttribute('mask-type', 'alpha'),
                SvgAttribute('transform', 'scale(2)'),
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
              attributes: [SvgAttribute('mask', 'url(#m)')],
              children: [redSquare],
            ),
          ],
        ),
      );
    });

    test('a fill that references a paint server is refused', () {
      // Verbatim from `sunset|accented|empty`. `parseHexColour` returns null
      // for it, which the fill path reads as "upstream omitted the attribute" —
      // so before the fix **every sunset render rasterised to a blank square**,
      // and a golden generated from one would have frozen the blank as correct.
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.path,
            attributes: [
              SvgAttribute('fill', 'url(#gradient)'),
              SvgAttribute('d', 'M0 0h8v4H0z'),
            ],
          ),
        ]),
      );
    });

    test('but an absent fill still draws nothing, as upstream does', () {
      // The distinction the fix rests on: *omitted* is upstream's own way of
      // saying "no paint" (hidden-state #17), while *present and unreadable* is
      // a capability we do not have. Collapsing the two is what hid sunset.
      final image = rasterizeScene(
        wrap(const [
          SvgNode(
            SvgElement.rect,
            attributes: [SvgAttribute('width', 8), SvgAttribute('height', 8)],
          ),
        ]),
        width: 8,
        height: 8,
      );
      expect(image.bytes.every((b) => b == 0), isTrue);
    });
  });

  group('the scene seam still refuses what it cannot draw', () {
    test('a target that does not match the 90-unit viewBox throws', () {
      // `ring` is the first variant whose drawing space is not 80, so this is
      // the first time the check can fail for a real scene rather than a
      // synthetic one.
      expect(
        () => rasterizeScene(
          buildRingScene(name: 'Clara Barton', colors: palette, size: 80),
          width: 80,
          height: 80,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });
  });

  group('goldens lock the verified state', () {
    // The roster is `test/support/golden_cases.dart`, shared with the generator
    // and with the directory check in `golden_contract_test.dart`.
    final cases = goldenCasesFor('ring');

    test('the roster is not empty, and it is ring\'s', () {
      expect(cases, hasLength(3));
    });

    cases.forEach((key, value) {
      test('$key is byte-identical', () {
        final (scene, size) = value;
        final actual = rasterizeScene(scene, width: size, height: size);
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
