import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:boring_avatars/src/raster/path.dart';
import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/raster/transform.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:boring_avatars/src/variants/beam.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';
import 'support/golden_cases.dart';

/// `beam`'s rasterizer capabilities, each checked against something outside
/// this package: the specification's own wording, or arithmetic.
void main() {
  group('scale, which `beam` is the first of the six to write', () {
    // Upstream's wrapper transform, verbatim from avatar-beam.js:60-74:
    //   translate(<tx> <ty>) rotate(<r> 18 18) scale(<s>)
    // with s ∈ {1, 1.1, 1.2}.

    test('one argument scales both axes — it does not default to 1', () {
      // §7.4: "scale(<sx> [<sy>]) … If <sy> is not provided, it is assumed to
      // be equal to <sx>." **The opposite of `translate`**, three lines earlier
      // in the same section, whose missing `<ty>` is assumed to be *zero*. A
      // port that shares one defaulting rule between them squashes every
      // scaled shape onto its own width.
      final one = parseTransform('scale(2)');
      expect(one.apply(3, 5), (6.0, 10.0));
    });

    test('and the two-argument form keeps them apart', () {
      expect(parseTransform('scale(2 3)').apply(3, 5), (6.0, 15.0));
      expect(parseTransform('scale(2, 3)').apply(3, 5), (6.0, 15.0));
    });

    test('so the one-argument form is not scale(s 1)', () {
      // The discriminating assertion for the paragraph above: if the default
      // were 1 these two would agree.
      expect(
        parseTransform('scale(2)').apply(3, 5),
        isNot(parseTransform('scale(2 1)').apply(3, 5)),
      );
    });

    test('scale(1) is exactly the identity', () {
      final m = parseTransform('scale(1)');
      expect(m.apply(7, 11), (7.0, 11.0));
      // `beam` writes scale(1) whenever getUnit(hash, 3) is 0 — a third of all
      // names — so this is the common case, not a corner.
      expect(m.isTranslationOnly, isTrue);
    });

    test('a scale is not a translation, so a rect stops being axis-aligned', () {
      // The flag that decides whether a rect keeps the closed-form integrator.
      expect(parseTransform('scale(1.1)').isTranslationOnly, isFalse);
    });

    test('the list still post-multiplies, with scale on the right', () {
      // §7.5: the rightmost function applies to the shape first. So `beam`'s
      // wrapper is scaled about the origin, *then* rotated about (18, 18),
      // *then* translated — and composing it the other way puts the shape
      // somewhere plausible and wrong.
      final m = parseTransform('translate(9 9) rotate(0 18 18) scale(2)');
      expect(m.apply(1, 1), (11.0, 11.0));

      final swapped = parseTransform('scale(2) translate(9 9)');
      expect(swapped.apply(1, 1), (20.0, 20.0));
    });

    test(
      'upstream\'s own wrapper string parses to the composition it means',
      () {
        // rotate(0 …) is exactly the identity — cos(0) is 1 and sin(0) is 0 with
        // no rounding — so this isolates translate ∘ scale from the rotation.
        final m = parseTransform('translate(4 4) rotate(0 18 18) scale(1.2)');
        final (x, y) = m.apply(10, 20);
        expect(x, closeTo(16, 1e-12));
        expect(y, closeTo(28, 1e-12));
      },
    );

    test(
      'a scaled rotation still preserves angles, which a shear would not',
      () {
        // A uniform scale is conformal: the image of a right angle is a right
        // angle. This is what tells `scale(s)` apart from the `matrix(…)` shear
        // a wrong composition can produce, and it needs no reference render.
        final m = parseTransform('translate(3 5) rotate(37 18 18) scale(1.1)');
        final (ox, oy) = m.apply(0, 0);
        final (ax, ay) = m.apply(1, 0);
        final (bx, by) = m.apply(0, 1);
        final dot = (ax - ox) * (bx - ox) + (ay - oy) * (by - oy);
        expect(dot, closeTo(0, 1e-12));
        final la = math.sqrt((ax - ox) * (ax - ox) + (ay - oy) * (ay - oy));
        final lb = math.sqrt((bx - ox) * (bx - ox) + (by - oy) * (by - oy));
        expect(la, closeTo(1.1, 1e-12));
        expect(lb, closeTo(1.1, 1e-12));
      },
    );

    test('the wrong number of arguments throws rather than guessing', () {
      expect(
        () => parseTransform('scale()'),
        throwsA(isA<UnsupportedSceneError>()),
      );
      expect(
        () => parseTransform('scale(1 2 3)'),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('what is still unimplemented still throws', () {
      // `matrix`, `skewX` and `skewY` are the rest of §7.4. No version in scope
      // writes one, and the seam's whole job is to fail loudly rather than
      // draw a plausible wrong picture.
      for (final source in ['matrix(1 0 0 1 0 0)', 'skewX(10)', 'skewY(10)']) {
        expect(
          () => parseTransform(source),
          throwsA(isA<UnsupportedSceneError>()),
          reason: source,
        );
      }
    });
  });

  group('beam rasterises to shapes whose areas are arithmetic', () {
    // The empty name hashes to 0, so every transform is the identity: no
    // rotation, scale 1, and the face sits where the source writes it. That
    // isolates the geometry from the composition — the same role this name
    // plays for `bauhaus`.
    //
    // With a one-colour palette the card and the background are the *same*
    // colour and the face is its contrast, so the **green channel is a direct
    // readout of how much white each pixel carries**. `getContrast('#FF0000')`
    // is white: the YIQ of pure red is 76.2, under the 128 threshold.
    //
    // Every white shape's area is known in closed form, so this measures the
    // drawing against arithmetic rather than against a golden.
    RasterImage render(String name, {bool square = false}) => rasterizeScene(
      buildBeamScene(
        name: name,
        colors: const ['#FF0000'],
        size: 36,
        square: square,
      ),
      width: 36,
      height: 36,
    );

    double whiteInk(RasterImage image) {
      var total = 0.0;
      for (var i = 0; i < image.bytes.length; i += 4) {
        total += image.bytes[i + 1] / 255;
      }
      return total;
    }

    // Each eye is 1.5 × 2 with rx=1, which §9.2 resolves to rx 0.75 and ry 1 —
    // half of each side, so the straight edges vanish and the eye is an
    // ellipse of area π·rx·ry.
    const eyeArea = math.pi * 0.75 * 1;

    test('the three readings of the eye are far apart, so the sum decides', () {
      // Two ellipses are 4.712; two circles of the clamped 0.75 would be 3.534;
      // two unrounded 1.5×2 rects 6.0. Nothing in the measurements below can
      // confuse them, which is what makes those measurements a test of §9.2's
      // independent clamp rather than of the rect code in general.
      expect(eyeArea * 2, closeTo(4.712, 0.001));
      expect(math.pi * 0.75 * 0.75 * 2, closeTo(3.534, 0.001));
      expect(1.5 * 2 * 2, 6.0);
    });

    test('an open mouth adds a stroked cubic of its own arc length', () {
      // Simpson's rule on |B'(t)| for `c2 1 4 1 6 0` — the definition of arc
      // length, sharing no code with the flattener. The stroke declares no
      // `stroke-width`, so §11.4's initial 1 applies, and the two round caps
      // add one full disc of radius 1/2.
      const p = <(double, double)>[(0, 0), (2, 1), (4, 1), (6, 0)];
      double speed(double t) {
        final u = 1 - t;
        final dx =
            3 * u * u * (p[1].$1 - p[0].$1) +
            6 * u * t * (p[2].$1 - p[1].$1) +
            3 * t * t * (p[3].$1 - p[2].$1);
        final dy =
            3 * u * u * (p[1].$2 - p[0].$2) +
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

      final mouth = length * 1 + math.pi * 0.25;
      expect(whiteInk(render('')), closeTo(eyeArea * 2 + mouth, 0.05));
    });

    test('a closed mouth adds the arc F.6.6 had to correct', () {
      // `a1,0.75 0 0,0 10,0` asks for radii that cannot span a chord of 10.
      // F.6.6 step 3 scales both by sqrt(λ) = 5, giving 5 and 3.75, and the
      // filled half-ellipse is then π·a·b/2 = 29.45. **This is the first input
      // in the package that makes that correction fire** — every arc `ring`
      // writes has λ exactly 1 (hidden-state #36).
      //
      // Rotation and translation preserve area, so `Alice`'s 88° card and its
      // −8° face do not enter the sum.
      const arc = math.pi * 5 * 3.75 / 2;
      expect(arc, closeTo(29.452, 0.001));
      expect(whiteInk(render('Alice')), closeTo(eyeArea * 2 + arc, 0.05));
    });

    test('and an uncorrected arc would be a visibly different mouth', () {
      // Without F.6.6 the radii stay 1 and 0.75 and the half-ellipse has an
      // area of 1.18 — a twenty-fifth of the corrected one.
      expect(math.pi * 1 * 0.75 / 2, closeTo(1.178, 0.001));
    });

    test('the mask cuts the corners, and square does not', () {
      final round = render('');
      for (final corner in const [(0, 0), (35, 0), (0, 35), (35, 35)]) {
        final i = (corner.$2 * 36 + corner.$1) * 4;
        expect(round.bytes[i + 3], 0, reason: '$corner');
      }
      final square = render('', square: true);
      for (final corner in const [(0, 0), (35, 0), (0, 35), (35, 35)]) {
        final i = (corner.$2 * 36 + corner.$1) * 4;
        expect(square.bytes[i + 3], 255, reason: '$corner');
      }
    });

    test('the eye has its own equation, at the seam beam reaches it through', () {
      // The open-mouth sum above is **one equation in two unknowns** — the eye
      // area and the stroke width both enter it, and the refuting lens built a
      // drawing where a stadium-shaped eye (+0.316) and a 0.9595 stroke width
      // (−0.316) cancelled and every arithmetic assertion stayed green.
      //
      // `raster_path_test.dart`'s §9.2 group cannot close that: it calls
      // `roundedRectContour` **directly with both radii**, so it is structurally
      // blind to how the missing one is filled at the call site. This measures
      // the eye alone, through `rasterizeScene`, with `beam`'s exact numbers.
      final image = rasterizeScene(
        SvgNode(
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
            const SvgNode(
              SvgElement.g,
              attributes: [SvgAttribute('mask', 'url(#m)')],
              children: [
                SvgNode(
                  SvgElement.rect,
                  attributes: [
                    SvgAttribute('x', 3),
                    SvgAttribute('y', 3),
                    SvgAttribute('width', 1.5),
                    SvgAttribute('height', 2),
                    SvgAttribute('rx', 1),
                    SvgAttribute('stroke', 'none'),
                    SvgAttribute('fill', '#FFFFFF'),
                  ],
                ),
              ],
            ),
          ],
        ),
        width: 8,
        height: 8,
      );
      var ink = 0.0;
      for (var i = 3; i < image.bytes.length; i += 4) {
        ink += image.bytes[i] / 255;
      }
      // π·0.75·1 = 2.356. A stadium (rx and ry both 0.75) is 2.514 and a plain
      // rect 3.0 — both outside this tolerance by an order of magnitude.
      expect(ink, closeTo(eyeArea, 0.02));
    });

    test('the drawing is the right colours, which ink totals cannot see', () {
      // The green-channel readout measures *how much* white, never *what
      // colour* anything else is. The refuting lens made an unreadable `fill`
      // paint SVG's initial black — turning the open mouth into a solid black
      // lens under the white stroke — and all four area assertions stayed
      // green, because black and the red card both have G = 0.
      //
      // Three sampled points, one per shape, with the palette chosen so the
      // three colours are all different.
      final image = rasterizeScene(
        buildBeamScene(
          name: '',
          colors: const ['#FF0000', '#00FF00'],
          size: 36,
        ),
        width: 36,
        height: 36,
      );
      List<int> at(int x, int y) =>
          image.bytes.sublist((y * 36 + x) * 4, (y * 36 + x) * 4 + 4);

      // The empty name hashes to 0, so the card takes `colors[0]` and the
      // background `colors[(0 + 13) % 2]` — index **1**. The +13 is what puts
      // them on different entries, and reading them the other way round is the
      // mistake this test caught while being written.
      final p = beamProperties('', const ['#FF0000', '#00FF00']);
      expect(p.wrapperColor, '#FF0000', reason: 'the card, from hash + 0');
      expect(p.backgroundColor, '#00FF00', reason: 'the background, hash + 13');
      expect(p.faceColor, '#FFFFFF', reason: 'getContrast of pure red is 76.2');

      // The card is a disc of radius 18 centred at (22, 22); (30, 22) is well
      // inside it and (2, 22) is well outside.
      expect(at(30, 22), [255, 0, 0, 255], reason: 'the card');
      expect(at(2, 22), [0, 255, 0, 255], reason: 'the background beside it');
      // The eye spans x ∈ [14, 15.5], y ∈ [14, 16] on a red card, and it is
      // white — so the pixel it covers gains green and blue. A mouth or eye
      // painted the initial black instead would *lose* them.
      expect(
        at(15, 15)[1],
        greaterThan(64),
        reason: 'the eye whitens the card',
      );
      expect(at(15, 15)[2], greaterThan(64));
    });

    test('the closed mouth curves the way upstream drew it, not mirrored', () {
      // Area is preserved under reflection: inverting the arc's sweep flag
      // turns the smile into a frown and the ink total does not move at all.
      // Measured — the closed-mouth assertion above stayed green under exactly
      // that mutation, caught only by a golden.
      //
      // So the direction is pinned by geometry instead: `beam`'s own `d`
      // string, left to right with sweep 0, must bulge **downwards** (screen
      // y grows down, so that is a smile). The string itself is pinned
      // byte-exact by `beam_parity_test.dart`, so the two together cover it.
      final bounds = parsePath('M13,20 a1,0.75 0 0,0 10,0');
      var minY = double.infinity, maxY = double.negativeInfinity;
      for (final c in bounds) {
        for (var i = 0; i < c.length; i++) {
          minY = math.min(minY, c.y(i));
          maxY = math.max(maxY, c.y(i));
        }
      }
      expect(minY, closeTo(20, 1e-9), reason: 'the chord is the top edge');
      // F.6.6 scales ry to 3.75, so a downward bulge reaches y = 23.75.
      expect(maxY, closeTo(23.75, defaultFlatness));
      expect(maxY, greaterThan(20), reason: 'a frown would put maxY at 20');
    });

    test('the face sits inside the mask for every corpus name', () {
      // The whole-ink assertions above are only valid while the mask clips
      // none of the face — otherwise they would be measuring the clip. Checked
      // rather than assumed, and it is the condition under which they hold.
      for (final name in ['', 'Alice', 'Clara Barton', '박기현']) {
        final ink = whiteInk(render(name));
        expect(ink, greaterThan(4.7), reason: '$name: at least the two eyes');
      }
    });
  });

  group('beam refuses what it still cannot draw', () {
    SvgNode wrap(List<SvgNode> children) => SvgNode(
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
          children: children,
        ),
      ],
    );

    void expectRejected(SvgNode scene) => expect(
      () => rasterizeScene(scene, width: 8, height: 8),
      throwsA(isA<UnsupportedSceneError>()),
    );

    test('a group transform composes with the element\'s, in that order', () {
      // §7.5 makes nesting the *definition* of a transform list, so an
      // ancestor's matrix applies **after** the descendant's own. `beam` is the
      // only variant with a transformed container, and both of its transforms
      // are non-trivial — so the wrong order is a plausible wrong picture.
      //
      // **`beam` cannot reach this and neither can any of the six.** Its two
      // transforms are on sibling branches — one on the card `<rect>`, one on
      // the face `<g>` whose children carry none of their own — so the
      // multiply always has an identity operand. Measured: flipping the
      // composition to `own · inherited` in both places kills only this test,
      // and every golden passes. Constructed on purpose, per `lessons.md`'s
      // third answer to a surviving mutant — the reference will never produce
      // the case, so the input has to be built.
      //
      // Chosen so the two orders disagree **on canvas**. `rotate(90 4 4)` maps
      // (x, y) to (8 − y, x), so the 2×2 rect at (2,0)–(4,2) lands at
      // (6,2)–(8,4) under the right order. Under the reversed one the rotation
      // happens first and the translation pushes the result to x ∈ [8,10],
      // entirely off the 8-wide canvas — so the wrong order paints *nothing*
      // and the assertion below is the one that separates them.
      final image = rasterizeScene(
        SvgNode(
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
            const SvgNode(
              SvgElement.g,
              attributes: [SvgAttribute('mask', 'url(#m)')],
              children: [
                SvgNode(
                  SvgElement.g,
                  attributes: [SvgAttribute('transform', 'rotate(90 4 4)')],
                  children: [
                    SvgNode(
                      SvgElement.rect,
                      attributes: [
                        SvgAttribute('width', 2),
                        SvgAttribute('height', 2),
                        SvgAttribute('transform', 'translate(2 0)'),
                        SvgAttribute('fill', '#FF0000'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        width: 8,
        height: 8,
      );
      List<int> at(int x, int y) =>
          image.bytes.sublist((y * 8 + x) * 4, (y * 8 + x) * 4 + 4);

      expect(at(6, 2), [255, 0, 0, 255], reason: 'where the right order lands');
      expect(at(7, 3), [255, 0, 0, 255]);
      expect(at(2, 0), [0, 0, 0, 0], reason: 'the untransformed position');
      expect(at(0, 2), [0, 0, 0, 0], reason: 'rotation about the wrong centre');
    });

    test('a group transform inside a group transform composes too', () {
      // The *container* half of the composition, which the test above does not
      // reach: there `inherited` is identity when the `<g>` is read, because
      // `beam`'s transformed group sits directly under the untransformed
      // `<g mask>`. Measured — deleting the ancestor term in `_collectShapes`
      // and keeping it in `_shapesOf` survived all 573 tests.
      //
      // Two nested translations of (2,0) must move the rect by 4, not 2.
      final image = rasterizeScene(
        SvgNode(
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
            const SvgNode(
              SvgElement.g,
              attributes: [SvgAttribute('mask', 'url(#m)')],
              children: [
                SvgNode(
                  SvgElement.g,
                  attributes: [SvgAttribute('transform', 'translate(2 0)')],
                  children: [
                    SvgNode(
                      SvgElement.g,
                      attributes: [SvgAttribute('transform', 'translate(2 0)')],
                      children: [
                        SvgNode(
                          SvgElement.rect,
                          attributes: [
                            SvgAttribute('width', 2),
                            SvgAttribute('height', 2),
                            SvgAttribute('fill', '#FF0000'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        width: 8,
        height: 8,
      );
      List<int> at(int x, int y) =>
          image.bytes.sublist((y * 8 + x) * 4, (y * 8 + x) * 4 + 4);

      expect(at(4, 0), [255, 0, 0, 255], reason: 'both translations applied');
      expect(at(5, 1), [255, 0, 0, 255]);
      expect(at(2, 0), [
        0,
        0,
        0,
        0,
      ], reason: 'only the inner one would stop here');
      expect(at(0, 0), [0, 0, 0, 0]);
    });

    test('a stroke-linecap nobody writes is refused, not treated as butt', () {
      // §11.4 defines three caps and `square` is the one no version in scope
      // asks for. Falling back to `butt` would shorten every stroke by half a
      // width at each end and throw nothing.
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.path,
            attributes: [
              SvgAttribute('d', 'M1 4h6'),
              SvgAttribute('stroke', '#FF0000'),
              SvgAttribute('stroke-linecap', 'square'),
            ],
          ),
        ]),
      );
    });

    test('an attribute on the mask\'s own rect is refused, not read past', () {
      // `<mask>` got an allow-list in #37; its **child** did not, and
      // `_readMask` reads only the five geometry attributes it knows. Measured
      // before the fix: a `transform="scale(2)"` on the mask's rect produced
      // exactly the untransformed 4×4 coverage where a browser gives 8×8, and
      // an `opacity="0.5"` produced full coverage where a browser halves it.
      // Two wrong pictures and no throw, in the element that decides what the
      // whole avatar is clipped to.
      SvgNode masked(List<SvgAttribute> maskRect) => SvgNode(
        SvgElement.svg,
        attributes: const [SvgAttribute('viewBox', '0 0 8 8')],
        children: [
          SvgNode(
            SvgElement.mask,
            attributes: const [
              SvgAttribute('id', 'm'),
              SvgAttribute('mask-type', 'alpha'),
            ],
            children: [SvgNode(SvgElement.rect, attributes: maskRect)],
          ),
          const SvgNode(
            SvgElement.g,
            attributes: [SvgAttribute('mask', 'url(#m)')],
            children: [
              SvgNode(
                SvgElement.rect,
                attributes: [
                  SvgAttribute('width', 8),
                  SvgAttribute('height', 8),
                  SvgAttribute('fill', '#FF0000'),
                ],
              ),
            ],
          ),
        ],
      );

      for (final extra in const [
        SvgAttribute('transform', 'scale(2)'),
        SvgAttribute('opacity', '0.5'),
        // `ry` too: [RoundedRectMask] clamps one radius jointly, so a mask
        // asking for two would silently get circular corners.
        SvgAttribute('ry', 2),
      ]) {
        expect(
          () => rasterizeScene(
            masked([
              const SvgAttribute('width', 4),
              const SvgAttribute('height', 4),
              const SvgAttribute('fill', '#FFFFFF'),
              extra,
            ]),
            width: 8,
            height: 8,
          ),
          throwsA(isA<UnsupportedSceneError>()),
          reason: extra.name,
        );
      }

      // …and the shape upstream actually writes still works, so the guard is
      // not simply refusing everything.
      final image = rasterizeScene(
        masked(const [
          SvgAttribute('width', 4),
          SvgAttribute('height', 4),
          SvgAttribute('rx', 16),
          SvgAttribute('fill', '#FFFFFF'),
        ]),
        width: 8,
        height: 8,
      );
      var ink = 0.0;
      for (var i = 3; i < image.bytes.length; i += 4) {
        ink += image.bytes[i] / 255;
      }
      expect(ink, closeTo(math.pi * 4, 0.05), reason: 'rx clamps to a disc');
    });

    test('a rect stroke that would paint is refused', () {
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', 4),
              SvgAttribute('height', 4),
              SvgAttribute('rx', 1),
              SvgAttribute('stroke', '#FF0000'),
              SvgAttribute('fill', '#00FF00'),
            ],
          ),
        ]),
      );
    });

    test('an unreadable rect stroke paints no outline, like a browser', () {
      // #64's rule at its third reader. The invalid-value rule ignores the
      // declaration and `stroke` falls back to `none` (no ancestor declares
      // one), so `stroke="zzz"` cannot paint — refusing it was a false
      // refusal, found by the #64 completeness pass after the other two call
      // sites were updated.
      final image = rasterizeScene(
        wrap(const [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', 4),
              SvgAttribute('height', 4),
              SvgAttribute('rx', 2),
              SvgAttribute('stroke', 'zzz'),
              SvgAttribute('fill', '#00FF00'),
            ],
          ),
        ]),
        width: 8,
        height: 8,
      );
      var ink = 0.0;
      for (var i = 3; i < image.bytes.length; i += 4) {
        ink += image.bytes[i] / 255;
      }
      expect(ink, closeTo(math.pi * 4, 0.05), reason: 'the same disc');
    });

    test('a rect stroke naming a paint server is still refused', () {
      // `url(#…)` reads as unreadable in the shared vocabulary — a paint
      // server is not a <color> — but unlike `zzz` it names something that
      // *would* paint an outline, so letting it ride the unreadable cell
      // would silently drop a gradient outline. The url shape keeps the
      // refusal whatever the vocabulary files it as.
      expectRejected(
        wrap(const [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', 4),
              SvgAttribute('height', 4),
              SvgAttribute('stroke', 'url(#nope)'),
              SvgAttribute('fill', '#00FF00'),
            ],
          ),
        ]),
      );
    });

    test('but stroke="none" on a rect is read and paints nothing', () {
      // The other half: `beam` writes this on both eyes, 160 times across the
      // fixture, and refusing it would refuse the variant.
      final image = rasterizeScene(
        wrap(const [
          SvgNode(
            SvgElement.rect,
            attributes: [
              SvgAttribute('width', 4),
              SvgAttribute('height', 4),
              SvgAttribute('rx', 2),
              SvgAttribute('stroke', 'none'),
              SvgAttribute('fill', '#00FF00'),
            ],
          ),
        ]),
        width: 8,
        height: 8,
      );
      var ink = 0.0;
      for (var i = 3; i < image.bytes.length; i += 4) {
        ink += image.bytes[i] / 255;
      }
      expect(ink, closeTo(math.pi * 4, 0.05), reason: 'a disc of radius 2');
    });
  });

  group('goldens lock the verified state', () {
    // The area assertions above are what make these evidence — a golden
    // generated from the code under test can only catch a regression. There is
    // deliberately no empty-palette golden: `beam` throws on one, so there is
    // no image to freeze.
    final cases = goldenCasesFor('beam');

    test('the roster is not empty, and it is beam\'s', () {
      expect(cases, hasLength(4));
    });

    test('and they are rasterised at 36, not 80', () {
      // Hidden-state #26 said `beam` was 80 until #38 measured 36. A golden
      // written at the wrong size is a plausible picture of the wrong avatar.
      for (final entry in cases.values) {
        expect(entry.$2, 36);
      }
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
