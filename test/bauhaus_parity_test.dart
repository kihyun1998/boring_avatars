import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/js/utilities.dart';
import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:boring_avatars/src/variants/bauhaus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layer-2 parity for `bauhaus`, against what upstream actually rendered.
///
/// Every render of this variant in the fixture — 20 names × 5 palettes — is
/// rebuilt from a name and a palette and compared **byte for byte**. That is
/// also the layer-1 proof: upstream exports no per-variant generator, so the
/// four elements' colours, translations and rotations are only observable as
/// the attributes they land in, and every one of them is in this string.
///
/// **One layer-1 fact is not observable that way**, and it has its own group
/// below. `isSquare` is computed four times from `getBoolean(numFromName, 2)` —
/// with no `i` in it — and only `properties[1]` ever reads the result. A port
/// that threaded `i` through it renders identically for all 20 corpus names:
/// measured, by applying the mutation and watching the sweep's 22 tests stay
/// green.
///
/// The reason is **not** that the moved values are unread — element 1's would
/// move too. It is that `getDigit(n, 2)` reads the hundreds digit, so `n + 1`
/// changes it only when `hash ≡ 99 (mod 100)`. A corpus of 20 names expects 0.2
/// such hits and has none, so the blindness is contingent on the corpus rather
/// than on the port: **one more name in that class would close it at layer 2.**
/// `aaK` is such a name (hash 96299), and the group below uses it and two
/// siblings so the tripwire trips by construction instead of by luck.
void main() {
  final corpus =
      jsonDecode(File('test/fixtures/corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final names = (corpus['names'] as List).cast<Map<String, dynamic>>();
  final palettes = (corpus['palettes'] as List).cast<Map<String, dynamic>>();

  final svgFixture =
      jsonDecode(File('test/fixtures/v1_6_1/svg.json').readAsStringSync())
          as Map<String, dynamic>;
  final renders = svgFixture['renders'] as Map<String, dynamic>;
  final matrixSize = svgFixture['matrixSize'] as int;

  String normalise(String svg) => svg
      .replaceAll(RegExp('id="[^"]*"'), 'id="_"')
      .replaceAll(RegExp(r'url\(#[^)]*\)'), 'url(#_)')
      .replaceAll(RegExp('mask="[^"]*"'), 'mask="_"');

  group('bauhaus reproduces upstream byte for byte', () {
    for (final n in names) {
      test('${n['id']}', () {
        for (final p in palettes) {
          final expected = renders['bauhaus|${n['id']}|${p['id']}'] as String;
          final actual = normalise(
            emitSvg(
              buildBauhausScene(
                name: n['value'] as String,
                colors: (p['value'] as List).cast<String>(),
                size: matrixSize,
              ),
            ),
          );
          expect(actual, expected, reason: '${n['id']}/${p['id']}');
        }
      });
    }

    test('the sweep covered every name and palette, not a subset', () {
      final covered = renders.keys
          .where((k) => k.startsWith('bauhaus|'))
          .length;
      expect(covered, names.length * palettes.length);
    });

    test('the mask id and its reference are upstream\'s literals', () {
      // `normalise` erases `id="…"`, `url(#…)` and `mask="…"` on both sides, so
      // the byte comparison above says nothing about either — a port that named
      // its mask `mask__ring` would pass all 100. The harness records them
      // unnormalised for exactly this.
      final identifiers =
          (svgFixture['maskIdentifiers'] as Map<String, dynamic>)['bauhaus']
              as Map<String, dynamic>;
      final svg = emitSvg(
        buildBauhausScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: matrixSize,
        ),
      );
      for (final id in (identifiers['ids'] as List).cast<String>()) {
        expect(svg, contains('<mask id="$id"'), reason: 'mask id');
      }
      for (final ref in (identifiers['references'] as List).cast<String>()) {
        expect(svg, contains('mask="url(#$ref)"'), reason: 'mask reference');
      }
      expect(identifiers['references'], identifiers['ids']);
    });
  });

  group('isSquare is one value shared by all four elements', () {
    /// The `height` upstream wrote on the second rect, read out of the fixture.
    ///
    /// `properties[1].isSquare` decides between `SIZE` and `SIZE / 8`, so this
    /// is the only place the flag reaches the output.
    int fixtureHeight(String nameId, String paletteId) {
      final svg = renders['bauhaus|$nameId|$paletteId'] as String;
      final match = RegExp(
        r'<rect x="10" y="30" width="80" height="(\d+)"',
      ).firstMatch(svg);
      expect(match, isNotNull, reason: '$nameId/$paletteId');
      return int.parse(match!.group(1)!);
    }

    test('upstream\'s own height agrees with the flag we compute', () {
      // Ties the flag to the reference rather than to our own reading of it.
      for (final n in names) {
        final properties = bauhausProperties(n['value'] as String, const [
          '#FF0000',
        ]);
        expect(
          properties[1].isSquare,
          fixtureHeight(n['id'] as String, 'single') == 80,
          reason: n['id'] as String,
        );
      }
    });

    test('and the corpus exercises both branches, not just one', () {
      // Without this the assertion above could hold on a constant `false`.
      final heights = {
        for (final n in names) fixtureHeight(n['id'] as String, 'single'),
      };
      expect(heights, {80, 10});
    });

    test('all four elements carry the same flag — upstream omits `i`', () {
      // `getBoolean(numFromName, 2)` is inside the `Array.from` callback and
      // does not use its index, so the four values are equal.
      //
      // **Two different conditions live near this test and they are not the
      // same number.** An earlier revision of this comment conflated them.
      //
      // * The 100-render byte sweep above is blind to a threaded `i` when
      //   element *1*'s flag does not move, which needs `hash ≢ 99 (mod 100)`
      //   — `getDigit(n, 2)` is the hundreds digit. Over 20 names that is 0.2
      //   expected and **0 observed**, so the sweep is in fact blind: measured
      //   by applying the mutation and watching its 22 tests stay green.
      // * This test trips when *any* of `hash…hash+3` crosses a hundred, which
      //   needs `hash mod 100 ∈ {97, 98, 99}` — 0.6 expected, **2 observed**
      //   (`single-char`, hash 97; `punctuation`, hash 218314798).
      //
      // So its power over the corpus is membership, not construction: drop
      // those two names and it goes green and silent. The constructed names
      // below are what make it a tripwire rather than a coincidence — one per
      // residue, so it trips whatever the corpus becomes.
      const constructed = {
        'aaI': 97, // flags 1110 — element 3 alone moves
        'aaJ': 98, // flags 1100
        'aaK': 99, // flags 1000 — **element 1 moves**, so layer 2 would see it
      };
      for (final entry in constructed.entries) {
        final flags = bauhausProperties(entry.key, const [
          '#FF0000',
        ]).map((e) => e.isSquare).toSet();
        expect(flags, hasLength(1), reason: entry.key);
        // The witness has to actually be in its residue class, or it is not
        // exercising anything and this test is decoration.
        expect(
          jsHashCode(entry.key) % 100,
          entry.value,
          reason: '${entry.key} is no longer a witness',
        );
      }

      for (final n in names) {
        final flags = bauhausProperties(n['value'] as String, const [
          '#FF0000',
        ]).map((e) => e.isSquare).toSet();
        expect(flags, hasLength(1), reason: n['id'] as String);
      }
    });

    test('and this pins the flag\'s shape, where the fixture pins its value', () {
      // The test above asserts only that the four agree — `getBoolean(hash, 3)`
      // satisfies it and is wrong. What kills that is the fixture-height
      // comparison at the top of this group. Neither test is "the only thing
      // standing between the port and a wrong flag"; they cover different
      // halves, and saying so is cheaper than someone deleting one.
      // Stated over the corpus, not over one name: `Clara Barton`'s hundreds
      // and thousands digits happen to agree, so it alone could not tell the
      // two apart. What matters is that *some* name does — otherwise the
      // fixture-height test is satisfied by the wrong digit and the pair of
      // tests covers one half twice.
      final distinguishing = names.where((n) {
        final hash = jsHashCode(n['value'] as String);
        return jsGetBoolean(hash, 3) != jsGetBoolean(hash, 2);
      }).toList();
      expect(
        distinguishing,
        isNotEmpty,
        reason:
            'no corpus name separates getDigit(_, 2) from getDigit(_, 3), so '
            'the fixture-height test cannot pin which digit is read',
      );
      for (final n in distinguishing) {
        expect(
          bauhausProperties(n['value'] as String, const [
            '#FF0000',
          ])[1].isSquare,
          jsGetBoolean(jsHashCode(n['value'] as String), 2),
          reason: n['id'] as String,
        );
      }
    });
  });

  group('the line is painted by stroke, not by fill', () {
    test('a palette gives it a stroke and never a fill', () {
      final svg = emitSvg(
        buildBauhausScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 80,
        ),
      );
      final line = RegExp(r'<line\b([^>]*)>').firstMatch(svg)!.group(1)!;
      expect(line, contains('stroke="#FF0000"'));
      expect(line, contains('stroke-width="2"'));
      expect(line, isNot(contains('fill=')));
    });

    test('an empty palette drops stroke, the way the others drop fill', () {
      // Hidden-state #8 is per call site: five variants degrade and `beam`
      // throws. `bauhaus` degrades — but the attribute it loses on the line is
      // `stroke`, and a port that emitted `stroke=""` or fell back to black
      // would draw a line upstream does not.
      final svg = emitSvg(
        buildBauhausScene(name: 'Clara Barton', colors: const [], size: 80),
      );
      expect(svg, isNot(contains('stroke="')));
      expect(svg, contains('stroke-width="2"'));
      // And the other three lose `fill`. Two `fill`s survive and neither comes
      // from the palette: the root `<svg fill="none">` and the mask's literal
      // `#FFFFFF`. Counting them is what makes this fail if a palette colour
      // reappears from a default rather than being omitted.
      expect('fill='.allMatches(svg), hasLength(2));
      expect(svg, contains('<svg viewBox="0 0 80 80" fill="none"'));
      expect(svg, contains('fill="#FFFFFF"'));
    });
  });

  group('square drops the corner radius rather than defaulting it', () {
    final squareRenders = svgFixture['squareRenders'] as Map<String, dynamic>;

    test('every square render matches upstream byte for byte', () {
      final keys = squareRenders.keys.where((k) => k.startsWith('bauhaus|'));
      // A count, not just non-emptiness: nine of the ten could vanish from the
      // fixture and a non-empty check would stay green.
      expect(keys, hasLength(2 * palettes.length));
      for (final key in keys) {
        final parts = key.split('|');
        final name = names.firstWhere((n) => n['id'] == parts[1]);
        final palette = palettes.firstWhere((p) => p['id'] == parts[2]);
        expect(
          normalise(
            emitSvg(
              buildBauhausScene(
                name: name['value'] as String,
                colors: (palette['value'] as List).cast<String>(),
                size: matrixSize,
                square: true,
              ),
            ),
          ),
          squareRenders[key],
          reason: key,
        );
      }
    });
  });

  group('size is a passthrough', () {
    test('it reaches width and height and nothing else', () {
      String svgFor(int size) => emitSvg(
        buildBauhausScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: size,
        ),
      );
      // Only the root `<svg>`'s pair may be normalised. `bauhaus` carries three
      // more `width="80" height="80"` pairs — the mask's region, the mask's rect
      // and the background rect — and erasing those would hide a mask region
      // built from the caller's `size`, which is the leak this test exists for.
      String strip(String s) => s.replaceFirst(
        RegExp(r'width="(40|80)" height="(40|80)"'),
        'width="_" height="_"',
      );
      expect(strip(svgFor(40)), strip(svgFor(80)));
    });
  });
}
