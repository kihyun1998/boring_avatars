// #62 — a colour carries its own alpha, and every hex notation is read.
//
// A conformance item under [ADR-0001](../docs/adr/0001-what-a-colour-declaration-means.md).
// The record's R1 says what is *valid* is decided by the property's grammar,
// not by what this parser happens to read — so the four hex forms are not a
// convenience, they are the difference between "the caller wrote a colour" and
// "the caller wrote garbage", and #64 cannot define the second until this
// ticket has finished the first.
//
// **Every number below was measured in Chrome**, not derived. The routing table
// sends this layer to the spec first and to a real render where the spec is
// silent, and CSS Color 4 §5.2 defines the 4- and 8-digit forms that SVG 1.1
// does not. Two of the measurements changed the design:
//
//  * `#FF00` is **valid** — `#RGBA`, expanding to `#FFFF0000`, yellow at alpha
//    zero. #62's own acceptance criteria list it beside `#GG0000` as invalid.
//    It draws nothing either way, which is exactly why it could sit in the
//    wrong cell unnoticed; putting it there would contradict R1 and would hand
//    #64 a value that is not garbage to treat as garbage.
//  * a gradient between two stops of **different alpha** interpolates
//    **straight**, not premultiplied. Measured `#FF000000` → `#0000FFFF` over
//    white: the midpoint is `191,128,191`, where premultiplied interpolation
//    gives `127,127,255`. Nothing upstream writes such a gradient, so a
//    premultiplied implementation would have left every golden green and been
//    wrong only in a caller's palette.

import 'package:boring_avatars/src/raster/raster.dart';
import 'package:flutter_test/flutter_test.dart';

/// The straight RGBA at (0, 0).
List<int> _at(RasterImage image) => image.bytes.sublist(0, 4);

/// A one-pixel image already painted opaque white, which is the backdrop the
/// Chrome measurements used.
RasterImage _white() =>
    RasterImage(1, 1)..blend(0, 0, const RasterColour(255, 255, 255), 1);

void main() {
  group('every hex notation CSS Color 4 defines', () {
    test('three digits double, and case does not matter', () {
      for (final form in ['#F00', '#f00']) {
        final c = parseHexColour(form)!;
        expect([c.r, c.g, c.b, c.a], [255, 0, 0, 255], reason: form);
      }
    });

    test('eight digits carry the alpha', () {
      for (final form in ['#FF000080', '#ff000080']) {
        final c = parseHexColour(form)!;
        expect([c.r, c.g, c.b, c.a], [255, 0, 0, 128], reason: form);
      }
    });

    test('four digits double all four, alpha included', () {
      // Chrome: `#F008` renders 255,0,0,136 — 0x88, not 0x80. A parser that
      // doubled the colour digits and left the alpha digit alone would land on
      // 8/255 here and be invisible in every other case.
      final c = parseHexColour('#F008')!;
      expect([c.r, c.g, c.b, c.a], [255, 0, 0, 136]);
    });

    test('an explicit FF alpha is the same colour as six digits', () {
      final six = parseHexColour('#FF0000')!;
      final eight = parseHexColour('#FF0000FF')!;
      expect(
        [eight.r, eight.g, eight.b, eight.a],
        [six.r, six.g, six.b, six.a],
      );
    });

    test('a fully transparent four-digit colour is READ, not rejected', () {
      // The discriminating case, and the one #62's own acceptance criteria got
      // wrong. Chrome renders `#FF00` as nothing — but by painting yellow at
      // alpha zero, not by ignoring an invalid declaration. The visible result
      // is identical and the *state* is not, which is the whole reason
      // `ColourDeclaration` has more than two cases.
      final c = parseHexColour('#FF00');
      expect(c, isNotNull, reason: '#RGBA is a valid form');
      expect([c!.r, c.g, c.b, c.a], [255, 255, 0, 0]);
      expect(readColourDeclaration('#FF00'), isA<ParsedColour>());
    });

    test('and the forms that are genuinely not colours stay unreadable', () {
      // #62 widens the notation and changes no answer for garbage — that is
      // #64's, under the same record. Seven digits is the interesting one:
      // it is hex, and it is not a form.
      // Note `#FF000` — **five** digits. Picking a short invalid form is
      // harder than it looks now that four lengths are legal: the first draft
      // of this list used `#FF0`, which is three and therefore yellow.
      for (final form in ['#GG0000', '#FF000', '#FF00000', '+123456', 'red']) {
        expect(parseHexColour(form), isNull, reason: form);
        expect(
          readColourDeclaration(form),
          isA<UnreadableColour>(),
          reason: form,
        );
      }
    });
  });

  group("a colour's alpha multiplies the shape's coverage", () {
    test('at full coverage it is the colour alpha alone', () {
      // Chrome, `#FF000080` over opaque white: 255,127,127.
      final image = _white()
        ..blend(0, 0, const RasterColour(255, 0, 0, 128), 1);
      expect(_at(image), [255, 127, 127, 255]);
    });

    test(
      'at half coverage the two multiply rather than one replacing the other',
      () {
        // The mutation guard. sa = 0.5 * 128/255 = 0.25098, so the white shows
        // through at 255 * (1 - 0.25098) = 191. A build that let coverage
        // *replace* the colour's alpha would give 127 here and pass the test
        // above; one that ignored alpha entirely would give 127 there and 127
        // here.
        final image = _white()
          ..blend(0, 0, const RasterColour(255, 0, 0, 128), 0.5);
        expect(_at(image), [255, 191, 191, 255]);
      },
    );

    test('a fully transparent colour paints nothing at any coverage', () {
      final image = _white()
        ..blend(0, 0, const RasterColour(255, 255, 0, 0), 1);
      expect(_at(image), [255, 255, 255, 255]);
    });

    test('an opaque colour is untouched by the multiplication', () {
      // What makes "no golden can move" structural rather than hopeful: every
      // colour upstream writes is six-digit, so every alpha is 255 and the new
      // factor is exactly 1.
      // 255 * (1 - 0.5) = 127.5, which rounds to 128 — the value this call
      // produced before #62 existed, unchanged because the new factor is 1.
      final image = _white()..blend(0, 0, const RasterColour(255, 0, 0), 0.5);
      expect(_at(image), [255, 128, 128, 255]);
    });
  });

  group('a gradient interpolates alpha the way Chrome does', () {
    // `#FF000000` -> `#0000FFFF`, measured over opaque white at five points:
    // 255,254,254 / 239,191,207 / 191,128,191 / 113,65,207 / 2,1,253.
    // The midpoint is what separates the two models.
    LinearGradientPaint gradient() => LinearGradientPaint(
      x1: 0,
      y1: 0,
      x2: 100,
      y2: 0,
      stops: const [
        (0.0, RasterColour(255, 0, 0, 0)),
        (1.0, RasterColour(0, 0, 255, 255)),
      ],
    );

    test('straight, not premultiplied', () {
      final c = gradient().colourAt(49, 0); // pixel centre 49.5 -> t = 0.495
      expect(c.a, closeTo(126, 2));
      expect(c.r, closeTo(129, 2));
      expect(c.b, closeTo(126, 2));
    });

    test('and composited it reproduces the measured midpoint', () {
      final image = _white()..blend(0, 0, gradient().colourAt(49, 0), 1);
      // Chrome measured 191,128,191 at the midpoint; this pixel centre is a
      // half-pixel short of it, so the bar is the same 1/255 the calibration
      // uses rather than exact equality.
      final rgba = _at(image);
      expect(rgba[0], closeTo(192, 2));
      expect(rgba[1], closeTo(129, 2));
      expect(rgba[2], closeTo(192, 2));
      expect(rgba[3], 255);
    });

    test('the endpoints keep their own alpha', () {
      final g = gradient();
      expect(g.colourAt(0, 0).a, lessThan(6));
      expect(g.colourAt(100, 0).a, 255);
    });
  });
}
