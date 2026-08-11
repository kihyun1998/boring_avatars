import 'package:boring_avatars/src/raster/raster.dart';
import 'package:boring_avatars/src/raster/system_colours.dart';
import 'package:flutter_test/flutter_test.dart';

// #95 — the CSS Color 4 notations #63 left unlearned: hwb(), lab()/lch(),
// oklab()/oklch(), color(), and the system colours.
//
// **Every byte below is a Chrome measurement, not a derivation.** A 73-swatch
// strip was rendered through headless Chrome 151.0.7922.108 (the calibrate
// harness's own renderer) and read back pixel by pixel; the system colours
// were additionally resolved through `getComputedStyle` on macOS in light
// mode, which returns the exact channel values with no PNG rounding in the
// way. The two sources agree on every overlapping entry. The routing table
// sends this layer to the spec first and a real render where the spec is
// silent — and for system colours the values are UA discretion, so the
// *measurement is the specification* (see system_colours.dart for the
// validity condition that freezing them implies).
//
// The strip carried two controls (#41's rule — a probe needs a discrimination
// control): `#FF0000` came back red and `zzz` came back as the refusal
// baseline, so a swatch matching its expectation is a measurement and not a
// misaligned read.
void main() {
  List<int>? rgba(String value) {
    final c = parseCssColour(value);
    return c == null ? null : [c.r, c.g, c.b, c.a];
  }

  group('hwb()', () {
    test('the axes: pure hue, whitened and blackened, achromatic', () {
      // hwb(120 0% 0%) is the pure hue; adding whiteness and blackness mixes
      // toward the two poles: rgb = hsl(h,100%,50%) * (1-w-b) + w.
      expect(rgba('hwb(120 0% 0%)'), [0, 255, 0, 255]);
      expect(rgba('hwb(120 30% 20%)'), [77, 204, 77, 255]);
      // 90deg via turn, and the half-value channels land on Dart's
      // half-away-from-zero round: 127.5 -> 128, 25.5 -> 26.
      expect(rgba('hwb(0.25turn 10% 10%)'), [128, 230, 26, 255]);
    });

    test('w + b at or past 100% is achromatic gray w/(w+b)', () {
      expect(rgba('hwb(120 60% 60%)'), [128, 128, 128, 255]);
    });

    test('hue wraps and alpha rides after a slash', () {
      expect(rgba('hwb(-240 30% 20%)'), [77, 204, 77, 255]);
      expect(rgba('hwb(120 30% 20% / 0.5)'), [77, 204, 77, 128]);
    });

    test('there is no legacy comma form — Chrome refuses it', () {
      expect(rgba('hwb(120, 30%, 20%)'), isNull);
    });
  });

  group('oklab() / oklch()', () {
    test('oklab, and L as number or percentage identically', () {
      expect(rgba('oklab(0.7 0.1 0.1)'), [229, 127, 78, 255]);
      expect(rgba('oklab(70% 0.1 0.1)'), [229, 127, 78, 255]);
      expect(rgba('oklab(1 0 0)'), [255, 255, 255, 255]);
    });

    test('oklab a/b percentages scale to ±0.4', () {
      expect(rgba('oklab(70% 25% -25%)'), [191, 129, 218, 255]);
    });

    test('oklch, both L forms, and chroma percentage to 0.4', () {
      expect(rgba('oklch(0.7 0.15 200)'), [0, 185, 195, 255]);
      expect(rgba('oklch(70% 0.15 200)'), [0, 185, 195, 255]);
      expect(rgba('oklch(0.7 37.5% 30)'), [237, 118, 101, 255]);
    });

    test('an out-of-gamut chroma clips to the sRGB face', () {
      // The gamut model this package implements is per-channel clip, because
      // that is what Chrome was measured doing — see colour_spaces.dart.
      expect(rgba('oklch(0.7 0.35 30)'), [255, 0, 0, 255]);
      expect(rgba('oklch(0.628 0.2577 29.23)'), [255, 0, 0, 255]);
    });
  });

  group('lab() / lch()', () {
    test('lab, and L as number or percentage identically', () {
      expect(rgba('lab(50% 40 59.5)'), [191, 87, 0, 255]);
      expect(rgba('lab(50 40 59.5)'), [191, 87, 0, 255]);
      expect(rgba('lab(29.2345% 39.3825 20.0664)'), [125, 35, 41, 255]);
      expect(rgba('lab(100 0 0)'), [255, 255, 255, 255]);
      expect(rgba('lab(0 0 0)'), [0, 0, 0, 255]);
    });

    test('lab a/b percentages scale to ±125', () {
      expect(rgba('lab(50% 50% -50%)'), [176, 67, 228, 255]);
    });

    test('lab alpha as a percentage', () {
      expect(rgba('lab(50% 40 59.5 / 30%)'), [191, 87, 0, 77]);
    });

    test('lch, hue in degrees bare, suffixed, and as a turn', () {
      expect(rgba('lch(52.2% 72.2 50)'), [205, 86, 26, 255]);
      expect(rgba('lch(52.2% 72.2 50deg)'), [205, 86, 26, 255]);
      expect(rgba('lch(52.2% 72.2 0.139turn)'), [205, 86, 26, 255]);
      expect(rgba('lch(29.2345% 44.2 27)'), [125, 35, 41, 255]);
    });

    test('lch chroma percentage scales to 150', () {
      expect(rgba('lch(50% 50% 50)'), [201, 78, 13, 255]);
    });

    test('out of gamut clips', () {
      expect(rgba('lab(50% 100 0)'), [255, 0, 124, 255]);
      expect(rgba('lch(50% 150 0)'), [255, 0, 128, 255]);
    });

    test('there is no comma form here either', () {
      expect(rgba('lab(50%, 40, 59.5)'), isNull);
    });
  });

  group('color()', () {
    test('srgb takes its values as already gamma-encoded', () {
      expect(rgba('color(srgb 1 0 0)'), [255, 0, 0, 255]);
      // 0.5*255 = 127.5 -> 128: the same half-away round every other path
      // takes, and Chrome's — measured, not assumed.
      expect(rgba('color(srgb 0.5 0.25 0.75)'), [128, 64, 191, 255]);
      expect(rgba('color(srgb 50% 25% 75%)'), [128, 64, 191, 255]);
      expect(rgba('color(srgb 1 0 0 / 0.5)'), [255, 0, 0, 128]);
    });

    test('out-of-range srgb components clip', () {
      expect(rgba('color(srgb 2 0 0)'), [255, 0, 0, 255]);
      expect(rgba('color(srgb -0.5 0.5 0.5)'), [0, 128, 128, 255]);
    });

    test('srgb-linear is the same space before the transfer function', () {
      expect(rgba('color(srgb-linear 0.5 0.5 0.5)'), [188, 188, 188, 255]);
    });

    test('the wide-gamut RGB spaces, through XYZ', () {
      expect(rgba('color(display-p3 1 0 0)'), [255, 0, 0, 255]);
      expect(rgba('color(display-p3 0 1 0)'), [0, 255, 0, 255]);
      expect(rgba('color(a98-rgb 1 0 0)'), [255, 0, 0, 255]);
      expect(rgba('color(prophoto-rgb 1 0 0)'), [255, 0, 0, 255]);
      expect(rgba('color(rec2020 1 0 0)'), [255, 0, 0, 255]);
    });

    test('xyz is xyz-d65, and xyz-d50 adapts through Bradford', () {
      expect(rgba('color(xyz 0.2 0.3 0.4)'), [0, 167, 164, 255]);
      expect(rgba('color(xyz-d65 0.2 0.3 0.4)'), [0, 167, 164, 255]);
      expect(rgba('color(xyz-d50 0.2 0.3 0.4)'), [0, 168, 189, 255]);
    });

    test('a colour space nobody defined is refused', () {
      expect(rgba('color(notaspace 1 0 0)'), isNull);
    });
  });

  group('system colours', () {
    test('the current §6.2 keywords, as this Chrome resolves them', () {
      expect(rgba('canvas'), [255, 255, 255, 255]);
      expect(rgba('canvastext'), [0, 0, 0, 255]);
      expect(rgba('linktext'), [0, 0, 238, 255]);
      expect(rgba('visitedtext'), [85, 26, 139, 255]);
      expect(rgba('accentcolor'), [0, 117, 255, 255]);
      expect(rgba('graytext'), [128, 128, 128, 255]);
    });

    test('Highlight is the one translucent entry, and keeps its alpha', () {
      // getComputedStyle: rgba(128, 188, 254, 0.6). The pixel strip read
      // 253 for the blue channel, which is the PNG's premultiply rounding
      // (hidden-state #29) — the computed style is the authoritative value.
      expect(rgba('highlight'), [128, 188, 254, 153]);
    });

    test('keywords are ASCII case-insensitive like every other keyword', () {
      expect(rgba('AccentColor'), [0, 117, 255, 255]);
      expect(rgba('CANVAS'), [255, 255, 255, 255]);
    });

    test('the deprecated keywords resolve to their Color 4 mappings', () {
      expect(rgba('activeborder'), [0, 0, 0, 255]); // ButtonBorder
      expect(rgba('threedface'), [239, 239, 239, 255]); // ButtonFace
      expect(rgba('windowtext'), [0, 0, 0, 255]); // CanvasText
      expect(rgba('background'), [255, 255, 255, 255]); // Canvas
    });

    test('there are exactly 42, split 19 current and 23 deprecated', () {
      // The count is what catches an accidental addition or a dropped row —
      // the same guard named_colours.dart carries at 148.
      expect(systemColours.length, 42);
    });

    test('all 42 parse to their table value, and only highlight has alpha', () {
      // The named-colours sibling sweeps all 148 through the parser; this is
      // the same guard for the 42. Reading the table back is only half of it
      // — the non-tautological half is the alpha pin, because the 0xAARRGGBB
      // format invites exactly one slip: an entry generated without its 0xFF
      // prefix would render invisibly transparent, and only a per-entry
      // sweep names which one.
      for (final entry in systemColours.entries) {
        final c = parseCssColour(entry.key);
        expect(c, isNotNull, reason: entry.key);
        expect(
          [c!.r, c.g, c.b, c.a],
          [
            (entry.value >> 16) & 0xFF,
            (entry.value >> 8) & 0xFF,
            entry.value & 0xFF,
            (entry.value >> 24) & 0xFF,
          ],
          reason: entry.key,
        );
        if (entry.key != 'highlight') {
          expect(c.a, 255, reason: '${entry.key} must be opaque');
        }
      }
      expect(parseCssColour('highlight')!.a, 153);
    });
  });

  group('the completeness pass\'s discriminators, confirmed on Chrome 151', () {
    // The #95 lens measured these on a cached Chrome 149 first; every byte
    // below was then re-confirmed on the reference Chrome 151 through the
    // committed strip (tool/colour4) before the fixes were frozen.

    test('huge components clamp to the float range instead of crashing', () {
      // CSS clamps a number to float range at parse; unclamped, the cube of
      // 1e300 is Infinity and `.round()` throws — a crash on the very
      // surface #64 promises degrades (S-4's failure mode). The second case
      // is the Inf−Inf NaN the clamp also removes.
      expect(rgba('lab(50 1e300 0)'), [255, 0, 255, 255]);
      expect(rgba('lab(50 1e300 -1e300)'), [0, 0, 255, 255]);
      expect(rgba('color(srgb 1e308 0 0)'), [255, 0, 0, 255]);
      // A huge angle times `turn`'s 360 would overflow past the clamp's
      // reach if the clamp sat after the unit multiply; the exact hue of a
      // 1e41-degree angle is float noise on both sides, so the pin is only
      // that it parses and draws.
      expect(rgba('hwb(1e300turn 10% 10%)'), isNotNull);
    });

    test('a bare fourth component is not an alpha — Chrome refuses these', () {
      // The modern grammar's alpha requires the slash. The last case is the
      // legacy *space* form, where the same rule holds and the same hole had
      // sat unrecorded since #63.
      expect(rgba('hwb(120 30% 20% 10%)'), isNull);
      expect(rgba('lab(50 40 59.5 30)'), isNull);
      expect(rgba('color(srgb 1 0 0 0)'), isNull);
      expect(rgba('rgb(255 0 0 0.5)'), isNull);
    });

    test('the space form takes number or percentage per component', () {
      // Color 4's modern syntax is per-component independent — unlike the
      // legacy comma form, which keeps all-or-none for rgb and requires
      // percentages for hsl (the refusals #63 measured and pinned).
      expect(rgba('rgb(100% 0 0)'), [255, 0, 0, 255]);
      expect(rgba('rgb(255 0% 0)'), [255, 0, 0, 255]);
      expect(rgba('hsl(120 50 50)'), [64, 191, 64, 255]);
      expect(rgba('hsl(120, 50, 50)'), isNull);
      expect(rgba('rgb(100%, 0, 0)'), isNull);
    });

    test('a number token needs a digit after its dot', () {
      expect(rgba('rgb(255. 0 0)'), isNull);
      expect(rgba('lab(50. 40 59.5)'), isNull);
      // The forms the token grammar does admit stay admitted.
      expect(rgba('rgb(+255 0 0)'), [255, 0, 0, 255]);
      expect(rgba('rgba(255 0 0 / .5)'), [255, 0, 0, 128]);
    });

    test('calc() is valid CSS this package deliberately skips', () {
      // The lens measured Chrome drawing `rgb(calc(255) 0 0)`. Out of scope
      // the same way none-components are — upstream never writes it and a
      // palette author has no reason to — and now recorded rather than
      // implicit. It stays unreadable and takes #64's answers.
      expect(rgba('rgb(calc(255) 0 0)'), isNull);
      expect(rgba('color(srgb calc(1) 0 0)'), isNull);
    });
  });

  group('what stays outside the grammar stays refused', () {
    test('the #64 witnesses do not start parsing by accident', () {
      expect(rgba('zzz'), isNull);
      expect(rgba(''), isNull);
      expect(rgba('rgb(255,0)'), isNull);
    });

    test('none components are valid CSS this package deliberately skips', () {
      // Measured: Chrome accepts `lab(none 50 0)` and `hsl(none 100% 50%)`
      // (the latter renders red). #95 scoped them out — upstream never writes
      // them and a palette author has no reason to — so they stay unreadable
      // and take #64's answers. Recorded in the ticket; this test is the
      // scope boundary made visible, not a claim that the values are invalid.
      expect(rgba('lab(none 50 0)'), isNull);
      expect(rgba('hsl(none 100% 50%)'), isNull);
    });
  });
}
