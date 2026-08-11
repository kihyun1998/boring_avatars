import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/scene_raster.dart';
import 'package:boring_avatars/src/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three ways for a colour not to be painted, and they are not the same thing.
///
/// Every case here draws nothing today, so none of it can be proved by looking
/// at pixels — an assertion on the picture is satisfied by all three at once.
/// What the vocabulary buys is that the *reason* is inspectable, so the tests
/// that pin it have to name the reason.
///
/// The three states, and what upstream does with each:
///
/// * **absent** — `<rect>` with no `fill`. Upstream's own idiom for "no paint"
///   (#17, and #8's empty palette), and 100% of `pixel` renders lead with one.
/// * **`none`** — SVG's own keyword for the same answer (11.2: "Indicates that
///   no paint is applied"). Measured across the 600-render fixture, it reaches
///   a drawn element in **`beam` only**: `<path fill="none">` on 44 of the 80
///   renders that do not throw, and `<rect stroke="none">` on 160.
/// * **unreadable** — `zzz`, `rgb(255,0)`, `""`. The caller's palette, in a
///   form no colour grammar admits (hidden-state #20). Since #64 each
///   property answers it as a browser answers an ignored declaration
///   (ADR-0001 R2): a `fill` or `stroke` paints nothing, a `stop-color`
///   paints black. This file pins those answers per property.
void main() {
  group('the three states are told apart, not collapsed', () {
    test('an attribute that was never written is absent', () {
      expect(readColourDeclaration(null), isA<AbsentColour>());
    });

    test('`none` is a value that was read, not a value that failed', () {
      // The one assertion the whole ticket turns on. `parseHexColour('none')`
      // returns null because the string is four characters long, so before
      // this vocabulary existed `none` and `red` were the same state — and
      // both drew nothing, so no picture could tell them apart.
      expect(readColourDeclaration('none'), isA<NoneColour>());
      expect(readColourDeclaration('none'), isNot(isA<UnreadableColour>()));
    });

    test('a hex colour is read', () {
      final declaration = readColourDeclaration('#FF0000');
      expect(declaration, isA<ParsedColour>());
      expect((declaration as ParsedColour).colour.r, 255);
    });

    test(
      'a notation only a browser reads is unreadable, and keeps its text',
      () {
        // **`#F00` and `#FF0000FF` left this list in #62**, which taught the
        // parser every hex form CSS Color 4 defines. They were never caller
        // garbage — a browser draws both — and keeping them here would have
        // been asserting the divergence rather than the vocabulary. What is
        // left is what a hex parser genuinely cannot read: a keyword, a
        // function, a padded string, and nothing at all.
        // **`red`, `rgb(255,0,0)` and ` #FF0000` left this list in #63**, which
        // finished the `<color>` grammar: 148 names, the four functions,
        // `transparent`, `currentColor`, and CSS's own trimming. What is left
        // is what no grammar admits — a shape that looks like a function and
        // is not, a name that is not a name, and nothing at all. #64 decided
        // what these *draw* (nothing in a `fill`, black in a `stop-color`);
        // this only says they were not read.
        for (final value in ['zzz', 'rgb(255,0)', 'hsv(0,100%,50%)', '']) {
          final declaration = readColourDeclaration(value);
          expect(declaration, isA<UnreadableColour>(), reason: value);
          expect((declaration as UnreadableColour).text, value);
        }
      },
    );

    test(
      'the keyword is matched loosely, which #63 measured before changing',
      () {
        // **The validity condition this test used to carry came due.** It said
        // matching `none` exactly was free while this package's emitter was
        // the only writer of these scenes, and named #63 as where a loose
        // match would land. #63 rendered the spellings in Chrome: `NONE`,
        // `None` and ` none ` all paint nothing, exactly as `none` does, so
        // the strict match was a divergence waiting for a caller to write one.
        //
        // The answer these spellings produce is unchanged — nothing is drawn
        // either way — which is why this could sit unresolved for four tickets
        // and why only a measurement, not a golden, could settle it.
        for (final value in ['none', 'NONE', 'None', ' none', 'none ']) {
          expect(
            readColourDeclaration(value),
            isA<NoneColour>(),
            reason: value,
          );
        }
      },
    );
  });

  group('a fill: all three draw nothing, for three different reasons', () {
    /// One 4x4 rect under a square mask, painted with [fill] — or with no
    /// `fill` attribute at all when [fill] is null.
    SvgNode scene(String? fill) => SvgNode(
      SvgElement.svg,
      attributes: const [SvgAttribute('viewBox', '0 0 4 4')],
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
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                const SvgAttribute('width', 4),
                const SvgAttribute('height', 4),
                if (fill != null) SvgAttribute('fill', fill),
              ],
            ),
          ],
        ),
      ],
    );

    List<int> centre(String? fill) {
      final image = rasterizeScene(scene(fill), width: 4, height: 4);
      final i = (2 * 4 + 2) * 4;
      return image.bytes.sublist(i, i + 4);
    }

    test('a colour it can read is painted — so the rest mean something', () {
      // Without this one, every assertion below is satisfied by a rasterizer
      // that draws nothing at all.
      expect(centre('#FF0000'), [255, 0, 0, 255]);
    });

    test('absent draws nothing', () => expect(centre(null), [0, 0, 0, 0]));

    test('`none` draws nothing', () => expect(centre('none'), [0, 0, 0, 0]));

    test('unreadable draws nothing — the ruled answer since #64', () {
      // Chrome's mechanism is inheritance: the declaration is ignored (CSS
      // 2.1 §4.2) and the slot takes the root's `fill="none"`. Ours is a
      // direct "unreadable paints nothing". Same answer, different reason —
      // ADR-0001 discrepancy ②, which parts ways the day a root declares a
      // colour.
      //
      // **`red` used to stand here and no longer can** — #63 taught the parser
      // the 148 names, so it is a colour now and the witness has to be
      // something no grammar admits.
      expect(centre('zzz'), [0, 0, 0, 0]);
    });

    test('and a name the parser has learned draws that colour', () {
      // The other half, which the shortened list above cannot state: `red`
      // moved from "unreadable" to "read", and a caller gets the colour.
      expect(centre('red'), [255, 0, 0, 255]);
      expect(centre('rgb(255 0 0)'), [255, 0, 0, 255]);
      expect(centre('transparent'), [0, 0, 0, 0]);
    });
  });

  group('a stroke uses the same vocabulary as a fill', () {
    /// A `<line>` across the middle of an 8x8 canvas, stroked with [stroke].
    SvgNode scene(String? stroke) => SvgNode(
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
              SvgElement.line,
              attributes: [
                const SvgAttribute('x1', 0),
                const SvgAttribute('y1', 4),
                const SvgAttribute('x2', 8),
                const SvgAttribute('y2', 4),
                const SvgAttribute('stroke-width', 2),
                if (stroke != null) SvgAttribute('stroke', stroke),
              ],
            ),
          ],
        ),
      ],
    );

    List<int> centre(String? stroke) {
      final image = rasterizeScene(scene(stroke), width: 8, height: 8);
      final i = (4 * 8 + 4) * 4;
      return image.bytes.sublist(i, i + 4);
    }

    test('a colour it can read is painted', () {
      expect(centre('#0000FF'), [0, 0, 255, 255]);
    });

    test('absent draws nothing — SVG\'s own initial value for `stroke`', () {
      // 11.4: `stroke`'s initial value is `none`, which is why an empty
      // palette costs `bauhaus` its rule without any other declaration.
      expect(centre(null), [0, 0, 0, 0]);
    });

    test('`none` draws nothing — and `beam` writes this one 160 times', () {
      expect(centre('none'), [0, 0, 0, 0]);
    });

    test('unreadable draws nothing — `stroke`\'s initial value is `none`', () {
      // The invalid-value rule lands on the initial value here (no ancestor
      // declares a `stroke`), which is `none` — so unlike `fill`, this cell
      // does not even depend on the root's declaration (ADR-0001).
      expect(centre('zzz'), [0, 0, 0, 0]);
    });

    test('and a stroke takes a learned name like a fill does', () {
      expect(centre('red'), [255, 0, 0, 255]);
    });
  });

  group('a <stop> reads the same three states and answers differently', () {
    // `stop-color`'s grammar is `currentColor | <color> <icccolor> | inherit`
    // (SVG 1.1, 13.2.4) — **`none` is not in it**, where for `fill` and
    // `stroke` it is the first alternative of `<paint>` (11.2). So the same
    // three states legitimately get different answers here, and the shared
    // vocabulary is what makes that a decision rather than an accident.
    SvgNode scene(
      List<SvgAttribute> stopAttributes, {
      String secondStop = '#000000',
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
        const SvgNode(
          SvgElement.g,
          attributes: [SvgAttribute('mask', 'url(#m)')],
          children: [
            SvgNode(
              SvgElement.rect,
              attributes: [
                SvgAttribute('width', 8),
                SvgAttribute('height', 8),
                SvgAttribute('fill', 'url(#g)'),
              ],
            ),
          ],
        ),
        SvgNode(
          SvgElement.defs,
          children: [
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
              children: [
                SvgNode(SvgElement.stop, attributes: stopAttributes),
                SvgNode(
                  SvgElement.stop,
                  attributes: [
                    const SvgAttribute('offset', 1),
                    SvgAttribute('stop-color', secondStop),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    List<int> topLeft(
      List<SvgAttribute> stopAttributes, {
      String secondStop = '#000000',
    }) {
      final image = rasterizeScene(
        scene(stopAttributes, secondStop: secondStop),
        width: 8,
        height: 8,
      );
      return image.bytes.sublist(0, 4);
    }

    test('a colour it can read is painted', () {
      expect(
        topLeft(const [SvgAttribute('stop-color', '#FF0000')]),
        // The first stop is at offset 0 and the pixel centre is 0.5/8 along
        // the axis, so the red has already been mixed a sixteenth towards the
        // black second stop.
        [239, 0, 0, 255],
      );
    });

    test('absent is black — SVG\'s initial `stop-color`', () {
      // The answer that makes an empty palette paint `sunset` a solid black
      // disc rather than a transparent one (hidden-state #39). Not shared
      // with `fill`, whose absence paints nothing, and that difference is the
      // reason one vocabulary needs two interpretations.
      expect(topLeft(const []), [0, 0, 0, 255]);
    });

    test(
      '`none` is black — outside the grammar, so the invalid-value rule',
      () {
        // `none` is a <paint> value; stop-color's grammar
        // (`currentColor | <color> <icccolor> | inherit`, 13.2.4) does not
        // include it, so the declaration is ignored (CSS 2.1 §4.2) and the slot
        // takes the initial value — black, because `stop-color` does not
        // inherit (§6.1.1). Chrome measured black, not nothing (#64's table).
        //
        // The second stop is white so the answer discriminates: a fallback of
        // white, or a rasterizer that dropped the stop and rode the remaining
        // white one, both come out 255 here where black mixed 1/16 toward white
        // is 16.
        expect(
          topLeft(const [
            SvgAttribute('stop-color', 'none'),
          ], secondStop: '#FFFFFF'),
          [16, 16, 16, 255],
        );
      },
    );

    test('unreadable is black — the same rule, same answer', () {
      // A value no grammar admits lands in the same cell as `none`: ignored,
      // then the initial value. This seam threw here from #69 to #64, and the
      // throw was recorded as temporary the day ADR-0001 derived black —
      // hidden-state #44 is the row that carried it.
      //
      // `red` was the witness until #63 taught the parser its 148 names; the
      // value has to be one no grammar admits now.
      expect(
        topLeft(const [
          SvgAttribute('stop-color', 'zzz'),
        ], secondStop: '#FFFFFF'),
        [16, 16, 16, 255],
      );
    });

    test('`transparent` is a read colour, not an invalid one', () {
      // The row in #64's table that must NOT go through the invalid-value
      // rule: `transparent` is a valid <color> (#63), so it reaches the
      // gradient as alpha 0 rather than falling back to black. An
      // implementation that classified it invalid would print 16,16,16,255
      // here — the exact answer the two tests above require for `zzz`.
      expect(
        topLeft(const [
          SvgAttribute('stop-color', 'transparent'),
        ], secondStop: '#FFFFFF'),
        // Straight interpolation (#62, measured): every channel runs
        // 0 → 255 across the axis, alpha included, so 1/16 along it is 16.
        [16, 16, 16, 16],
      );
    });

    test('and a learned name reaches the gradient', () {
      // The path #62 widened and #63 fills: a `<stop>` now takes any CSS
      // colour, not only a hex one.
      //
      // Sampled on the **top row**, because this gradient runs down to a black
      // second stop — the first draft of this test read the middle and got
      // 112, which is the interpolation doing its job. t is 0.5/8 here, so the
      // red channel is 255 - 255/16 = 239.06.
      final image = rasterizeScene(
        scene(const [SvgAttribute('stop-color', 'red')]),
        width: 8,
        height: 8,
      );
      final i = 4 * 4;
      expect(image.bytes.sublist(i, i + 4), [239, 0, 0, 255]);
    });
  });
}
