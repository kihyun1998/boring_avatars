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
/// * **unreadable** — `red`, `#F00`, `rgb(…)`. The caller's palette, in a
///   notation a browser reads and this rasterizer has not learned
///   (hidden-state #20). #64 changes this answer; this file pins today's.
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
        // function, a padded string, and nothing at all. #64 is where those
        // answers change; `raster_alpha_test.dart` holds the ones that moved.
        // **`red`, `rgb(255,0,0)` and ` #FF0000` left this list in #63**, which
        // finished the `<color>` grammar: 148 names, the four functions,
        // `transparent`, `currentColor`, and CSS's own trimming. What is left
        // is what no grammar admits — a shape that looks like a function and
        // is not, a name that is not a name, and nothing at all. #64 decides
        // what these *draw*; this only says they were not read.
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

    test('unreadable draws nothing — today', () {
      // #64 is where this answer changes: Chrome paints nothing for an
      // unreadable `fill`, so the answer is already right, but it is right
      // for the wrong reason until the notation is actually learned.
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

    test('unreadable draws nothing — today', () {
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
    SvgNode scene(List<SvgAttribute> stopAttributes) => SvgNode(
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
                const SvgNode(
                  SvgElement.stop,
                  attributes: [
                    SvgAttribute('offset', 1),
                    SvgAttribute('stop-color', '#000000'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    List<int> topLeft(List<SvgAttribute> stopAttributes) {
      final image = rasterizeScene(scene(stopAttributes), width: 8, height: 8);
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

    test('`none` is refused — it is not in stop-color\'s grammar', () {
      expect(
        () => rasterizeScene(
          scene(const [SvgAttribute('stop-color', 'none')]),
          width: 8,
          height: 8,
        ),
        throwsA(isA<UnsupportedSceneError>()),
      );
    });

    test('unreadable is refused — today', () {
      // Chrome paints black here, not nothing, and #64 is where that answer
      // is taken. Until then the seam refuses rather than guessing, which is
      // the rule the whole rasterizer is built on.
      //
      // `red` was the witness until #63 taught the parser its 148 names; the
      // value has to be one no grammar admits now.
      expect(
        () => rasterizeScene(
          scene(const [SvgAttribute('stop-color', 'zzz')]),
          width: 8,
          height: 8,
        ),
        throwsA(isA<UnsupportedSceneError>()),
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
