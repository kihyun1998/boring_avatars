import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:boring_avatars/src/js/js_number.dart';
import 'package:boring_avatars/src/js/utilities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every assertion here is measured against the real upstream implementation.
///
/// `test/fixtures/v1_6_1/utilities.json` was produced by importing upstream's
/// own `utilities.js` from the pinned reference tree and calling it — so what
/// these tests encode is what upstream *does*, not what this port's author
/// believed it does.
void main() {
  final corpus =
      jsonDecode(File('test/fixtures/corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final names = (corpus['names'] as List).cast<Map<String, dynamic>>();
  final palettes = (corpus['palettes'] as List).cast<Map<String, dynamic>>();

  final fixture =
      jsonDecode(File('test/fixtures/v1_6_1/utilities.json').readAsStringSync())
          as Map<String, dynamic>;
  final hashes = (fixture['hashCode'] as Map<String, dynamic>)
      .cast<String, int>();
  final contrasts = (fixture['getContrast'] as Map<String, dynamic>)
      .cast<String, String>();
  final derived = fixture['derived'] as Map<String, dynamic>;

  group('hashCode matches upstream on every corpus name', () {
    for (final n in names) {
      test('${n['id']}', () {
        expect(jsHashCode(n['value'] as String), hashes[n['id']]);
      });
    }

    test('Math.abs of the most negative 32-bit hash leaves int32 range', () {
      // The one input where `Math.abs(hash)` cannot fit back into an int32:
      // the raw accumulator lands on exactly -2^31, so the result is 2^31.
      // A port that narrows again after abs() answers -2147483648 here.
      //
      // No corpus name reaches it — this one was constructed for the purpose
      // and its value measured from upstream's own module.
      final name = String.fromCharCodes(const [
        90,
        113,
        92,
        73,
        111,
        68,
        110,
        821,
      ]);
      expect(jsHashCode(name), 2147483648);
    });

    test('the corpus actually exercises the traps, not just easy names', () {
      // A name long enough to overflow 32 bits many times over, and one whose
      // code units differ from its code points. If these ever produced the same
      // answer under a naive port, the suite above would prove nothing.
      expect(hashes['long-200-mixed'], isNot(0));
      expect(hashes['emoji-zwj'], isNot(0));
      expect(hashes['empty'], 0);
    });
  });

  // Fixture keys carry an optional `@m` suffix: the number fed in is the
  // hash times m. bauhaus and marble pass `hash * (i + 1)`, so without the
  // multiples nothing above 2^31 ever reaches getDigit or getUnit.
  int numberFor(int hash, String key) =>
      key.contains('@') ? hash * int.parse(key.split('@')[1]) : hash;
  String argsOf(String key) => key.split('@')[0];

  group('getDigit matches upstream', () {
    for (final n in names) {
      test('${n['id']}', () {
        final expected = (derived[n['id']]['getDigit'] as Map<String, dynamic>)
            .cast<String, int>();
        final hash = hashes[n['id']]!;
        for (final entry in expected.entries) {
          expect(
            jsGetDigit(
              numberFor(hash, entry.key),
              int.parse(argsOf(entry.key)),
            ),
            entry.value,
            reason: 'key=${entry.key}',
          );
        }
      });
    }

    test('the fixture reaches past 2^31, where a 64-bit port could drift', () {
      final keys = (derived['upstream-default']['getDigit'] as Map).keys;
      expect(keys.where((k) => (k as String).contains('@')), isNotEmpty);
    });
  });

  group('getDigit — what the float division does and does not buy', () {
    test(
      'integer division would give the same answer for every reachable input',
      () {
        // Recorded, not covered. Upstream writes `number / Math.pow(10, ntn)`,
        // a float division, and hidden-state #4 warns against `~/`. Swapping in
        // `~/` does not break a single fixture assertion — and it cannot, for
        // non-negative input: writing n = q·10^k + r with q = n ~/ 10^k, the
        // float quotient is q + f for 0 <= f < 1, and floor((q + f) % 10) is
        // q % 10 whenever q % 10 <= 9. Which is always.
        //
        // So the mutation survives because the distinction is unobservable
        // here, not because the suite is weak.
        for (final n in names) {
          final hash = hashes[n['id']]!;
          expect(hash, greaterThanOrEqualTo(0), reason: 'the premise');
          for (var ntn = 0; ntn <= 4; ntn++) {
            final viaInt = (hash ~/ math.pow(10, ntn).toInt()) % 10;
            expect(
              jsGetDigit(hash, ntn),
              viaInt,
              reason: '${n['id']} ntn=$ntn',
            );
          }
        }
      },
    );

    test('the two diverge the moment a negative number reaches it', () {
      // The validity condition, made executable. getDigit only ever sees
      // hashCode output and multiples of it, all non-negative — but if that
      // stops being true, the float division is the correct one.
      //
      // These four are measured from upstream's own utilities.js, not derived
      // here: importing it and calling getDigit directly.
      expect(jsGetDigit(-15, 1), -2);
      expect(jsGetDigit(-7, 0), -7);
      expect(jsGetDigit(-123, 1), -3);
      expect(jsGetDigit(-123, 2), -2);

      expect(
        (-15 ~/ 10) % 10,
        isNot(-2),
        reason: 'integer division would answer differently',
      );
    });
  });

  group('getBoolean matches upstream', () {
    for (final n in names) {
      test('${n['id']}', () {
        final expected =
            (derived[n['id']]['getBoolean'] as Map<String, dynamic>)
                .cast<String, bool>();
        final hash = hashes[n['id']]!;
        for (final entry in expected.entries) {
          expect(
            jsGetBoolean(
              numberFor(hash, entry.key),
              int.parse(argsOf(entry.key)),
            ),
            entry.value,
            reason: 'key=${entry.key}',
          );
        }
      });
    }
  });

  group('getUnit matches upstream, with and without the index argument', () {
    for (final n in names) {
      test('${n['id']}', () {
        final expected = (derived[n['id']]['getUnit'] as Map<String, dynamic>)
            .cast<String, int>();
        final hash = hashes[n['id']]!;
        for (final entry in expected.entries) {
          final parts = argsOf(entry.key).split(',');
          final range = int.parse(parts[0]);
          final index = parts.length > 1 ? int.parse(parts[1]) : null;
          expect(
            jsGetUnit(numberFor(hash, entry.key), range, index),
            entry.value,
            reason: entry.key,
          );
        }
      });
    }

    test('the fixture covers both the indexed and unindexed branch', () {
      final keys = (derived['upstream-default']['getUnit'] as Map).keys;
      expect(keys.where((k) => (k as String).contains(',')), isNotEmpty);
      expect(keys.where((k) => !(k as String).contains(',')), isNotEmpty);
    });

    test('the fixture covers every range the six components actually pass', () {
      // Derived from the call sites, not chosen: bauhaus 20-23 and 360,
      // marble 4, 8 and 360, beam 3, 5, 7, 8, 10 and 360. An earlier fixture
      // claimed to be this union and omitted 4, 7 and 20-23.
      final keys = (derived['upstream-default']['getUnit'] as Map).keys
          .cast<String>()
          .map((k) => int.parse(k.split('@')[0].split(',')[0]))
          .toSet();
      expect(keys, containsAll(<int>[3, 4, 5, 7, 8, 10, 20, 21, 22, 23, 360]));
    });
  });

  group('getRandomColor matches upstream', () {
    for (final n in names) {
      test('${n['id']}', () {
        final expected =
            (derived[n['id']]['getRandomColor'] as Map<String, dynamic>)
                .cast<String, String?>();
        final hash = hashes[n['id']]!;
        for (final entry in expected.entries) {
          // Keys are `<palette>` or `<palette>|<numberForm>`. The number forms
          // are the ones the components actually pass, not just the bare hash.
          final parts = entry.key.split('|');
          final colours =
              (palettes.firstWhere((p) => p['id'] == parts[0])['value'] as List)
                  .cast<String>();
          final number = parts.length == 1
              ? hash
              : switch (parts[1]) {
                  'h+1' => hash + 1,
                  'h+2' => hash + 2,
                  'h+3' => hash + 3,
                  'h+4' => hash + 4,
                  'h+13' => hash + 13,
                  'h%0' => null, // NaN upstream — see below
                  'h%1' => jsMod(hash, 1),
                  'h%2' => jsMod(hash, 2),
                  'h%63' => jsMod(hash, 63),
                  _ => throw StateError('unknown form ${parts[1]}'),
                };

          if (number == null) {
            // pixel's i == 0. Upstream evaluates colors[NaN] and gets nothing,
            // on every render — the port has to reach the same absence through
            // jsModOrNull rather than by dividing by zero.
            expect(entry.value, isNull, reason: entry.key);
            expect(jsModOrNull(hash, 0), isNull);
            continue;
          }
          expect(
            jsGetRandomColor(number, colours, colours.length),
            entry.value,
            reason: entry.key,
          );
        }
      });
    }

    test('an empty palette yields null rather than throwing', () {
      // hidden-state #8: upstream computes colors[n % 0] = colors[NaN] =
      // undefined and carries on. Dart's own `%` would throw here.
      expect(jsGetRandomColor(12345, const [], 0), isNull);
      expect(
        (derived['upstream-default']['getRandomColor'] as Map)['empty'],
        isNull,
        reason: 'the fixture must record the absence explicitly',
      );
    });

    test("pixel's first tile is unfilled for every name and palette", () {
      // A second, unrelated route to colors[NaN]: pixel indexes with
      // `hash % i` from i == 0. Unlike the empty palette this is not an edge —
      // it happens on 100% of pixel renders with the default palette, and a
      // port that fills tile 0 is byte-wrong every single time.
      for (final n in names) {
        for (final p in palettes) {
          expect(
            (derived[n['id']]['getRandomColor'] as Map)['${p['id']}|h%0'],
            isNull,
            reason: '${n['id']}/${p['id']}',
          );
        }
      }
    });
  });

  group('getContrast matches upstream', () {
    for (final entry in contrasts.entries) {
      test(entry.key, () {
        expect(jsGetContrast(entry.key), entry.value);
      });
    }

    test('accepts a colour with no leading hash, as upstream does', () {
      expect(jsGetContrast('FFFFFF'), jsGetContrast('#FFFFFF'));
      expect(jsGetContrast('000000'), jsGetContrast('#000000'));
    });

    test('a malformed colour yields #FFFFFF, because NaN >= 128 is false', () {
      // parseInt returns NaN on non-hex input; the comparison is then false and
      // upstream falls through to the light face colour. It does not throw.
      for (final bad in <String>['', '#', 'zzzzzz', '#GG', 'nope']) {
        expect(jsGetContrast(bad), '#FFFFFF', reason: bad);
      }
    });

    test(
      'parseInt semantics — every one of these is measured from upstream',
      () {
        // `beam` hands getContrast a palette entry verbatim, and the palette is
        // consumer policy, so malformed input is reachable by construction. A
        // hand-rolled "scan leading hex digits" gets four of these wrong.
        const upstream = <String, String>{
          // A 0x prefix is *stripped* at radix 16, leaving no digits — so the
          // shape a Dart author is most likely to reach for contrasts as white.
          '0xFF0000': '#FFFFFF',
          '0XABCDEF': '#FFFFFF',
          '0x808080': '#FFFFFF',
          '0x': '#FFFFFF',
          // Leading whitespace and a sign are consumed, so these DO parse.
          '\tFF0000': '#000000',
          ' FF0000': '#000000',
          ' FF0000': '#000000',
          '　FF0000': '#000000',
          '+FF0000': '#000000',
          '-FF0000': '#000000',
          // The hash is only stripped when it is the very first character, so a
          // space before it leaves '#' where a digit was wanted.
          '  #00FF00': '#FFFFFF',
          '#FF0000': '#FFFFFF',
          'FF0000': '#FFFFFF',
          'FFF': '#FFFFFF',
          '#8': '#FFFFFF',
        };
        for (final entry in upstream.entries) {
          expect(
            jsGetContrast(entry.key),
            entry.value,
            reason: jsonEncode(entry.key),
          );
        }
      },
    );

    test('a hex string shorter than six digits clamps instead of throwing', () {
      // substr(2,2) and substr(4,2) run off the end of a short colour, and
      // JavaScript returns what is left rather than raising. Nothing in the
      // palette corpus is short, so this branch had no coverage until a
      // mutation removing the clamp survived the suite.
      //
      // Measured from upstream.
      const upstream = <String, String>{
        '#f': '#FFFFFF',
        '#8': '#FFFFFF',
        '#ff': '#FFFFFF',
        '#fff': '#FFFFFF',
        '#ffff': '#FFFFFF',
        '#fffff': '#000000',
        '#abcde': '#000000',
      };
      for (final entry in upstream.entries) {
        expect(jsGetContrast(entry.key), entry.value, reason: entry.key);
      }
    });

    test('jsParseIntHex is parseInt(s, 16), not a hex scanner', () {
      expect(jsParseIntHex('0x'), isNaN, reason: 'prefix stripped, no digits');
      expect(jsParseIntHex('0xFF'), 255);
      expect(jsParseIntHex('\tF'), 15, reason: 'whitespace skipped');
      expect(jsParseIntHex('-F'), -15, reason: 'sign consumed');
      expect(jsParseIntHex('+F'), 15);
      expect(jsParseIntHex('FFzz'), 255, reason: 'trailing junk ignored');
      expect(jsParseIntHex('zz'), isNaN);
      expect(jsParseIntHex(''), isNaN);
    });

    test('the exact YIQ boundary lands on #000000, not below it', () {
      // yiq >= 128 is the upstream predicate. #808080 sits above it and
      // #7F7F7F below, so this pins the comparison direction.
      expect(jsGetContrast('#808080'), '#000000');
      expect(jsGetContrast('#7F7F7F'), '#FFFFFF');
    });
  });

  group('JS number semantics', () {
    test('jsMod keeps the sign of the dividend, unlike Dart %', () {
      expect(jsMod(-7, 5), -2);
      expect(-7 % 5, 3, reason: 'Dart disagrees — this is why jsMod exists');
      expect(jsMod(7, 5), 2);
      expect(jsMod(-7, -5), -2);
    });

    test('toSigned32 wraps the way a JS bitwise op does', () {
      expect(toSigned32(2147483647), 2147483647);
      expect(toSigned32(2147483648), -2147483648);
      expect(toSigned32(4294967296), 0);
      expect(toSigned32(-2147483649), 2147483647);
    });

    test('jsNum prints an integral value without a decimal point', () {
      expect(jsNum(4), '4');
      expect(jsNum(4.0), '4');
      expect(jsNum(-0.0), '0', reason: 'JS String(-0) is "0"');
      expect(jsNum(1.2), '1.2');
      expect(jsNum(1.5), '1.5');
      expect(jsNum(0.1 + 0.2), '0.30000000000000004');
      expect(jsNum(-3), '-3');
    });

    test('jsNum prints large integral values in full, not saturated', () {
      // `toInt()` clamps at 2^63, which would print 1e19 as
      // 9223372036854775807. JavaScript prints every digit up to 1e21 and only
      // then switches to exponential. Reachable: `size` is consumer policy and
      // goes straight into the svg width and height.
      expect(jsNum(1e18), '1000000000000000000');
      expect(jsNum(9.3e18), '9300000000000000000');
      expect(jsNum(1e19), '10000000000000000000');
      expect(jsNum(1e20), '100000000000000000000');
      expect(jsNum(1e21), '1e+21', reason: 'JS switches here, not before');
      expect(jsNum(1e300), '1e+300');
      expect(jsNum(-1e19), '-10000000000000000000');
    });

    test('jsNum handles the non-finite values String() names', () {
      expect(jsNum(double.infinity), 'Infinity');
      expect(jsNum(double.negativeInfinity), '-Infinity');
      expect(jsNum(double.nan), 'NaN');
    });

    test('jsModOrNull expresses the NaN that jsMod cannot', () {
      // `pixel` computes `hash % i` from i = 0, where JavaScript answers NaN
      // and the colour ends up undefined. An int-typed modulo cannot say that,
      // so the variant needs this form.
      expect(jsModOrNull(645088871, 0), isNull);
      expect(jsModOrNull(645088871, 5), jsMod(645088871, 5));
      expect(
        () => jsMod(645088871, 0),
        throwsA(anything),
        reason: 'the non-nullable form is documented as rejecting zero',
      );
    });
  });

  group('the utilities upstream never reaches are not ported', () {
    test('getModulus and getAngle have no declaration in this package', () {
      // Both are exported by upstream's utilities.js and imported by no
      // component at v1.6.1 — getModulus is not even called by the other
      // utilities. Porting them would be porting code no caller can reach,
      // the same judgement that dropped the turbulence variant.
      //
      // This reads the source rather than asserting over a literal list. An
      // earlier version compared a hard-coded list of names to its own length
      // and stayed green no matter what the library contained — a tripwire
      // that cannot trip is worse than none, because it reads as coverage.
      final source = File('lib/src/js/utilities.dart').readAsStringSync();
      for (final absent in <String>['jsGetModulus', 'jsGetAngle']) {
        expect(source, isNot(contains('$absent(')), reason: absent);
      }
      // And the ones that must be present, so the test fails if the file is
      // moved or emptied rather than quietly passing on a missing string.
      for (final present in <String>[
        'int jsHashCode(',
        'int jsGetDigit(',
        'bool jsGetBoolean(',
        'int jsGetUnit(',
        'String? jsGetRandomColor(',
        'String jsGetContrast(',
      ]) {
        expect(source, contains(present), reason: present);
      }
    });
  });
}
