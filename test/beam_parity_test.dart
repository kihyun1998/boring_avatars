import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/variants/beam.dart';
import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layer-2 parity for `beam`, against what upstream actually rendered.
///
/// Every render of this variant in the fixture — 20 names × 5 palettes — is
/// rebuilt from a name and a palette and compared **byte for byte**. That is
/// also the layer-1 proof: upstream exports no per-variant generator, so all
/// fourteen generated values are observable only as the attributes they land
/// in. Unlike `bauhaus`, **every one of `beam`'s fields does reach the output**
/// — there is no `isSquare`-style value computed and then ignored — so the byte
/// sweep is a complete layer-1 check and not a partial one.
///
/// **Twenty of the hundred entries are not strings.** `beam` is the only
/// variant that throws on an empty palette, and the harness records upstream's
/// crash as data: `{"__throws": "TypeError"}`. Those are asserted as throws,
/// which makes the fixture the expectation for the failure as well as for the
/// output.
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
  final squareRenders = svgFixture['squareRenders'] as Map<String, dynamic>;
  final matrixSize = svgFixture['matrixSize'] as int;

  String normalise(String svg) => svg
      .replaceAll(RegExp('id="[^"]*"'), 'id="_"')
      .replaceAll(RegExp(r'url\(#[^)]*\)'), 'url(#_)')
      .replaceAll(RegExp('mask="[^"]*"'), 'mask="_"');

  String render(String name, List<String> colors, {bool square = false}) =>
      normalise(
        emitSvg(
          buildBeamScene(
            title: true,
            name: name,
            colors: colors,
            size: matrixSize,
            square: square,
          ),
        ),
      );

  group('beam reproduces upstream byte for byte', () {
    for (final n in names) {
      test('${n['id']}', () {
        for (final p in palettes) {
          final expected = renders['beam|${n['id']}|${p['id']}'];
          final colors = (p['value'] as List).cast<String>();
          final name = n['value'] as String;

          if (expected is Map) {
            // Upstream produced no document at all for this input, so there
            // are no bytes to match — only the failure. Asserting equality
            // against "nothing" would be vacuous; asserting the throw is the
            // whole of what upstream can be compared on.
            expect(
              expected['__throws'],
              'TypeError',
              reason: 'the fixture records which failure',
            );
            expect(
              () => buildBeamScene(
                title: true,
                name: name,
                colors: colors,
                size: matrixSize,
              ),
              throwsA(isA<ArgumentError>()),
              reason: '${n['id']}/${p['id']}',
            );
            continue;
          }

          expect(
            render(name, colors),
            expected as String,
            reason: '${n['id']}/${p['id']}',
          );
        }
      });
    }

    test('the sweep covered every name and palette, not a subset', () {
      final covered = renders.keys.where((k) => k.startsWith('beam|')).length;
      expect(covered, names.length * palettes.length);
    });

    test('and exactly one palette of the five is the throwing one', () {
      // If a future corpus change made two palettes empty, or none, the loop
      // above would still pass while measuring something different.
      final throwing = renders.entries
          .where((e) => e.key.startsWith('beam|') && e.value is Map)
          .length;
      expect(throwing, names.length, reason: 'one per name, the empty palette');
    });

    test('square drops the mask radius, and upstream agrees', () {
      // `square` is varied here and nowhere in the main matrix — the #37
      // lesson: a prop the matrix never varies is a prop nobody has compared
      // to upstream.
      //
      // **A count, not just a loop.** All four sibling parity tests assert this
      // and `beam` was the one that dropped it; the refuting lens filtered the
      // loop to a prefix matching nothing and the whole suite stayed green with
      // zero square renders compared. Nine of the ten could vanish from the
      // fixture and the `for` below would still pass.
      var compared = 0;
      for (final entry in squareRenders.entries) {
        if (!entry.key.startsWith('beam|')) continue;
        final parts = entry.key.split('|');
        final name = names.firstWhere((n) => n['id'] == parts[1]);
        final palette = palettes.firstWhere((p) => p['id'] == parts[2]);
        final colors = (palette['value'] as List).cast<String>();

        if (entry.value is Map) {
          expect(
            () => buildBeamScene(
              title: true,
              name: name['value'] as String,
              colors: colors,
              size: matrixSize,
              square: true,
            ),
            throwsA(isA<ArgumentError>()),
            reason: entry.key,
          );
          compared++;
          continue;
        }
        expect(
          render(name['value'] as String, colors, square: true),
          entry.value as String,
          reason: entry.key,
        );
        compared++;
      }
      // 2 names × 5 palettes. Eight are byte comparisons and two are the empty
      // palette's throw — counted here too, because "compared" means the
      // fixture entry was checked against something, and the first draft of
      // this counter said 8 by omitting exactly the throwing pair.
      expect(compared, 10);
    });

    test('the mask id and its reference are upstream\'s literals', () {
      // `normalise` erases `id="…"`, `url(#…)` and `mask="…"` on both sides, so
      // the byte comparison above says nothing about either — a port that named
      // its mask `mask__ring` would pass all 80.
      final identifiers =
          (svgFixture['maskIdentifiers'] as Map<String, dynamic>)['beam']
              as Map<String, dynamic>;
      final svg = emitSvg(
        buildBeamScene(
          title: true,
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

    test('the drawing space is 36, whatever size the caller asked for', () {
      // Hidden-state #26 said every variant but `ring` was 80. `beam` is 36,
      // and the two numbers appear in the same element — so a port that used
      // one for both would still emit a plausible `<svg>`.
      final svg = emitSvg(
        buildBeamScene(
          title: true,
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 320,
        ),
      );
      expect(svg, startsWith('<svg viewBox="0 0 36 36" fill="none"'));
      expect(svg, contains('width="320" height="320"'));
    });
  });

  group('the two ternary thresholds, at the boundary no name reaches', () {
    // `faceTranslateX` and `faceTranslateY` each test `> SIZE / 6`, which is
    // `> 6`. The mutation `>` → `>=` differs on exactly one value of
    // `wrapperTranslate`: **6**.
    //
    // On the X axis two corpus names supply it (`emoji-single` and `long-64`,
    // both `wrapperTranslateX == 6`) and the mutant dies at layer 2. On the Y
    // axis **no corpus name does** — the twenty produce
    // `{-4,-3,-2,2,3,4,5,8,9}` — so the same mutation on the neighbouring line
    // survived the whole suite. Measured over 200 000 synthetic names,
    // `wrapperTranslateY == 6` is **9.99% of all names**: one user in ten.
    //
    // Same line of upstream source, opposite evidence, purely by corpus luck.
    // `lessons.md`'s "a tripwire's power can come from corpus membership" one
    // rung further out — not a name carrying a test, but a **boundary no name
    // reaches**. The witnesses below are one character each.
    const witnesses = <String, (int, num)>{
      // name: (wrapperTranslateY, the faceTranslateY upstream produces)
      'f': (6, 4),
      'j': (6, 1),
      'p': (6, 0),
      't': (6, 4),
    };

    witnesses.forEach((name, expected) {
      test('"$name" sits on the threshold and takes the > branch', () {
        final p = beamProperties(name, const ['#FF0000']);
        final (translateY, faceY) = expected;
        expect(
          p.wrapperTranslateY,
          translateY,
          reason: 'the witness must actually be on the boundary',
        );
        // `>` keeps `getUnit(numFromName, 7, 2)`; `>=` would halve the 6 to 3.
        expect(p.faceTranslateY, faceY);
        expect(
          p.faceTranslateY,
          isNot(3),
          reason: 'the value a >= mutant produces for every one of these',
        );
      });
    });

    test(
      'and the X axis boundary is carried by the corpus, not constructed',
      () {
        // Recorded so the asymmetry is visible: this one needs no witness today,
        // and would need one the moment those two names left the corpus.
        final carriers = names
            .map((n) => n['value'] as String)
            .where(
              (n) =>
                  beamProperties(n, const ['#FF0000']).wrapperTranslateX == 6,
            )
            .toList();
        expect(carriers, hasLength(2), reason: 'emoji-single and long-64');
        for (final name in carriers) {
          final p = beamProperties(name, const ['#FF0000']);
          expect(p.faceTranslateX, isNot(3));
        }
      },
    );
  });

  group('the corpus reaches both arms of every branch that draws', () {
    // `bauhaus_parity_test.dart` asserts its branch spread and `beam` did not.
    // Nothing here is a new fact — the numbers were measured before the goldens
    // were generated — but a corpus edit could silence a branch and, without
    // this, nothing would report it.
    List<BeamProperties> all() => names
        .map((n) => beamProperties(n['value'] as String, const ['#FF0000']))
        .toList();

    test('both mouths, both cards, and all three scales', () {
      final p = all();
      expect(p.where((e) => e.isMouthOpen).length, 11);
      expect(p.where((e) => !e.isMouthOpen).length, 9);
      expect(p.where((e) => e.isCircle).length, 10);
      expect(p.where((e) => !e.isCircle).length, 10);
      expect(p.map((e) => e.wrapperScale).toSet(), {1.0, 1.1, 1.2});
    });

    test('every eye and mouth spread the generators can produce', () {
      final p = all();
      expect(p.map((e) => e.eyeSpread).toSet(), {0, 1, 2, 3, 4});
      expect(p.map((e) => e.mouthSpread).toSet(), {0, 1, 2});
    });

    test('and both arms of the two halving ternaries', () {
      // The halved arm is the one that produces `.5` values; the other gives an
      // unrelated `getUnit`. Both have to appear or one of them is untested at
      // layer 2 whatever the byte sweep says.
      final p = all();
      expect(
        p.where((e) => e.wrapperTranslateX > 6).length,
        greaterThan(0),
        reason: 'the halving arm, X',
      );
      expect(
        p.where((e) => e.wrapperTranslateX <= 6).length,
        greaterThan(0),
        reason: 'the getUnit arm, X',
      );
      expect(p.where((e) => e.wrapperTranslateY > 6).length, greaterThan(0));
      expect(p.where((e) => e.wrapperTranslateY <= 6).length, greaterThan(0));
      // …and the `preTranslate < 5` nudge, both ways. A post-nudge value of 9
      // can only be un-nudged (the nudge caps at 8); a negative one can only be
      // nudged.
      expect(p.where((e) => e.wrapperTranslateX == 9).length, greaterThan(0));
      expect(p.where((e) => e.wrapperTranslateX < 0).length, greaterThan(0));
    });
  });

  group('an empty palette fails, and only for beam', () {
    test(
      'the failure names the palette rather than leaking an index error',
      () {
        // The user's ruling was "throw, in a Dart-idiomatic way" — so what a
        // caller sees has to be about *their* input, not about a null slice.
        expect(
          () => buildBeamScene(
            title: true,
            name: 'Clara Barton',
            colors: const [],
            size: 80,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('palette'),
            ),
          ),
        );
      },
    );

    test('a one-colour palette does not fail — the guard is the empty one', () {
      // The discriminating half: a guard that rejected any short palette would
      // pass the test above and break every single-colour caller.
      expect(
        () => buildBeamScene(
          title: true,
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 80,
        ),
        returnsNormally,
      );
    });
  });
}
