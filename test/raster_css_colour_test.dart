// #63 — named colours and the colour functions.
//
// A conformance item under ADR-0001, after #62 finished hex. **Every expected
// value here was rendered in Chrome**, because the routing table sends this
// layer to the spec first and to a real browser where the spec is silent — and
// because a colour table is the one kind of data where being wrong is silent:
// a mistyped entry is wrong only for the palette that names it, so no golden
// moves and nothing else fails.
//
// The 148 names are **generated** from the raw CSS Color 4 §6.1 table and then
// **cross-checked** against Chrome — 148 of 148 agree. Either source alone
// would have been weaker: generating from Chrome and asserting against Chrome
// is the tautology the bindings warn about, and transcribing the spec by hand
// is the typo this ticket exists to avoid.

import 'package:boring_avatars/src/raster/named_colours.dart';
import 'package:boring_avatars/src/raster/raster.dart';
import 'package:flutter_test/flutter_test.dart';

List<int>? _rgba(String value) {
  final c = parseCssColour(value);
  return c == null ? null : [c.r, c.g, c.b, c.a];
}

void main() {
  group('the 148 names came from the specification', () {
    test('there are exactly 148, and transparent is not one of them', () {
      // The count is the cheapest guard on a generated file: an entry lost to a
      // bad extraction, or `transparent` folded in by hand, both move it.
      // CSS Color 4 §6.2 defines `transparent` apart from the named colours,
      // as `rgb(0 0 0 / 0)`, and `parseCssColour` answers it separately.
      expect(namedColours.length, 148);
      expect(namedColours.containsKey('transparent'), isFalse);
      expect(namedColours.containsKey('currentcolor'), isFalse);
    });

    test('including the one Colors 3 did not have', () {
      // `rebeccapurple` is CSS Color 4's own addition — 147 names plus this one
      // is where 148 comes from. Its presence is what says the table was taken
      // from Color 4 and not from an older list.
      expect(namedColours['rebeccapurple'], 0x663399);
    });

    test('and the values are the spec hex, not something adjacent', () {
      // Four picked to be unforgiving: two whose names invite a swap, one whose
      // value is not what the name suggests, and one at the end of the table.
      expect(_rgba('aliceblue'), [240, 248, 255, 255]);
      expect(_rgba('darkgray'), [169, 169, 169, 255]);
      expect(_rgba('gray'), [128, 128, 128, 255]);
      // Measured in Chrome, and the classic trap: `green` is not `#00FF00`.
      expect(_rgba('green'), [0, 128, 0, 255]);
      expect(_rgba('yellowgreen'), [154, 205, 50, 255]);
    });

    test('every entry is a colour this parser can produce', () {
      // A structural sweep over the generated file rather than 148 literals:
      // it catches a row that survived generation with an unparseable key.
      for (final name in namedColours.keys) {
        final packed = namedColours[name]!;
        expect(_rgba(name), [
          (packed >> 16) & 0xFF,
          (packed >> 8) & 0xFF,
          packed & 0xFF,
          255,
        ], reason: name);
      }
    });
  });

  group('keywords are ASCII case-insensitive and tolerate padding', () {
    test('a name in any case', () {
      for (final form in ['red', 'RED', 'Red', ' red ', 'red\n', '\tred']) {
        expect(_rgba(form), [255, 0, 0, 255], reason: form);
      }
    });

    test('and so is `none`, which #63 was named as the place to settle', () {
      // Measured before changing it: Chrome paints nothing for `NONE`, `None`
      // and ` none ` exactly as it does for `none`. The strict match this
      // replaces was recorded as a validity condition rather than a contract.
      for (final form in ['none', 'NONE', 'None', ' none ']) {
        expect(readColourDeclaration(form), isA<NoneColour>(), reason: form);
      }
    });

    test('but the folding is ASCII, not Unicode', () {
      // U+212A KELVIN SIGN lower-cases to `k` under Unicode rules, so a
      // Unicode-aware fold would match `black` here and match nothing in a
      // browser. Nothing in a palette will ever contain one; the point is that
      // the parser's rule is the same rule CSS states.
      expect(parseCssColour('blac\u{212A}'), isNull);
    });

    test('and the padding is CSS whitespace, not Dart whitespace', () {
      // `String.trim()` removes U+00A0, which CSS does not. Trimming it would
      // make this parser accept what a browser refuses — the direction that
      // produces a wrong picture rather than a refusal.
      expect(parseCssColour('\u{00A0}red'), isNull);
    });
  });

  group('transparent and currentColor', () {
    test('transparent is a colour with alpha zero, not a failure', () {
      // It drew nothing before #63 too, by not parsing. #64 needs the two
      // apart: one is a colour, the other is garbage.
      expect(_rgba('transparent'), [0, 0, 0, 0]);
      expect(readColourDeclaration('transparent'), isA<ParsedColour>());
    });

    test('currentColor is black, and that is measured', () {
      // Rendered in a document where no ancestor declares `color`: Chrome
      // paints 0,0,0,255 — `color`'s initial value, reached by the same
      // inheritance ADR-0001's R2 uses. Nothing this package emits declares
      // `color`, which is the condition this answer rests on.
      expect(_rgba('currentColor'), [0, 0, 0, 255]);
      expect(_rgba('currentcolor'), [0, 0, 0, 255]);
    });
  });

  group('rgb() and rgba()', () {
    test('either separator, either value form, either alpha form', () {
      for (final form in [
        'rgb(255,0,0)',
        'rgb(255, 0, 0)',
        'rgb(255 0 0)',
        'rgb( 255 , 0 , 0 )',
        'rgb(100%,0%,0%)',
        'rgb(100% 0% 0%)',
        'RGB(255,0,0)',
      ]) {
        expect(_rgba(form), [255, 0, 0, 255], reason: form);
      }
      for (final form in [
        'rgb(255,0,0,0.5)',
        'rgba(255,0,0,0.5)',
        'rgb(255 0 0 / 0.5)',
        'rgb(255 0 0 / 50%)',
      ]) {
        expect(_rgba(form), [255, 0, 0, 128], reason: form);
      }
    });

    test('a percentage is 0-255 of the range, and rounds up at the half', () {
      // 50% of 255 is 127.5, and Chrome renders 128. A parser that read the
      // percentage as a 0-255 value would give 50 here — one of the mutations
      // #63 asks for.
      expect(_rgba('rgb(50%,50%,50%)'), [128, 128, 128, 255]);
      expect(_rgba('rgb(128,128,128)'), [128, 128, 128, 255]);
    });

    test('out-of-range values clamp rather than refuse', () {
      expect(_rgba('rgb(300,-20,0)'), [255, 0, 0, 255]);
      expect(_rgba('rgb(255.5,0,0)'), [255, 0, 0, 255]);
      expect(_rgba('rgb(255,0,0,-1)'), [255, 0, 0, 0]);
      expect(_rgba('rgb(255,0,0,150%)'), [255, 0, 0, 255]);
    });

    test(
      'numbers and percentages do not mix, and Chrome refuses the mixture',
      () {
        expect(parseCssColour('rgb(100%,0,0)'), isNull);
        expect(parseCssColour('rgb(255,0%,0)'), isNull);
      },
    );
  });

  group('hsl() and hsla()', () {
    test('either separator, and an alpha either way', () {
      for (final form in [
        'hsl(0,100%,50%)',
        'hsl(0 100% 50%)',
        'hsl(0deg 100% 50%)',
        'hsl(0, 100%, 50%)',
        'HSL(0,100%,50%)',
      ]) {
        expect(_rgba(form), [255, 0, 0, 255], reason: form);
      }
      for (final form in ['hsla(0,100%,50%,0.5)', 'hsl(0 100% 50% / 50%)']) {
        expect(_rgba(form), [255, 0, 0, 128], reason: form);
      }
    });

    test('the sextants, each measured', () {
      expect(_rgba('hsl(30deg 100% 50%)'), [255, 128, 0, 255]);
      expect(_rgba('hsl(90 100% 50%)'), [128, 255, 0, 255]);
      expect(_rgba('hsl(120,100%,25%)'), [0, 128, 0, 255]);
      expect(_rgba('hsl(150deg 100% 50%)'), [0, 255, 128, 255]);
      expect(_rgba('hsl(210deg 100% 50%)'), [0, 128, 255, 255]);
      expect(_rgba('hsl(240,100%,50%)'), [0, 0, 255, 255]);
      expect(_rgba('hsl(0,0%,50%)'), [128, 128, 128, 255]);
    });

    test('the hue wraps rather than clamping', () {
      // -120 is 240 and 480 is 120 — measured, and the mutation guard for a
      // reversed rotation, which would send -120 to 120 instead.
      expect(_rgba('hsl(-120,100%,50%)'), [0, 0, 255, 255]);
      expect(_rgba('hsl(480,100%,50%)'), [0, 255, 0, 255]);
    });

    test('all four angle units', () {
      // `grad` must be recognised before `rad`, since it ends with it.
      expect(_rgba('hsl(3.14159rad 100% 50%)'), [0, 255, 255, 255]);
      expect(_rgba('hsl(200grad 100% 50%)'), [0, 255, 255, 255]);
      expect(_rgba('hsl(0.5turn 100% 50%)'), [0, 255, 255, 255]);
      expect(_rgba('hsl(0turn 100% 50%)'), [255, 0, 0, 255]);
      expect(_rgba('hsl(0.25turn 100% 50%)'), [128, 255, 0, 255]);
    });

    test('a hue a shade past the boundary lands on the other side', () {
      // The case that separates a wrong unit conversion from a rounding
      // difference, and the one that caught an arithmetic slip while #63 was
      // being read: 1.5708 is *larger* than pi/2, so it is 90.0002 degrees and
      // not 89.9997. Chrome gives 127 for the first and 128 for the second.
      expect(_rgba('hsl(1.5708rad 100% 50%)'), [127, 255, 0, 255]);
      expect(_rgba('hsl(1.57079632679rad 100% 50%)'), [128, 255, 0, 255]);
      expect(_rgba('hsl(90.00031deg 100% 50%)'), [127, 255, 0, 255]);
      expect(_rgba('hsl(89.99969deg 100% 50%)'), [128, 255, 0, 255]);
    });

    test('saturation and lightness must be percentages', () {
      // Measured: Chrome refuses `hsl(0,100,50)`. Accepting it would draw a
      // colour where a browser draws the invalid-value answer instead.
      expect(parseCssColour('hsl(0,100,50)'), isNull);
      expect(parseCssColour('hsl(0,100%,50)'), isNull);
    });
  });

  group('what is still not a colour', () {
    test('shapes that look like a function and are not', () {
      for (final form in [
        'zzz',
        'rgb(255,0)',
        'rgb(255,0,0,)',
        'rgb(255,0,0',
        'rgb 255 0 0',
        'hsv(0,100%,50%)',
        'rgb(255 0 0, 0.5)',
        'rgb(255,0,0 / 0.5)',
        '',
        'rgb(NaN,0,0)',
        'rgb(Infinity,0,0)',
      ]) {
        expect(parseCssColour(form), isNull, reason: form);
      }
    });

    test('and they stay unreadable rather than becoming a guess', () {
      expect(readColourDeclaration('zzz'), isA<UnreadableColour>());
      expect((readColourDeclaration('zzz') as UnreadableColour).text, 'zzz');
    });
  });
}
