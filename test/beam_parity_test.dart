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
              () =>
                  buildBeamScene(name: name, colors: colors, size: matrixSize),
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
      for (final entry in squareRenders.entries) {
        if (!entry.key.startsWith('beam|')) continue;
        final parts = entry.key.split('|');
        final name = names.firstWhere((n) => n['id'] == parts[1]);
        final palette = palettes.firstWhere((p) => p['id'] == parts[2]);
        final colors = (palette['value'] as List).cast<String>();

        if (entry.value is Map) {
          expect(
            () => buildBeamScene(
              name: name['value'] as String,
              colors: colors,
              size: matrixSize,
              square: true,
            ),
            throwsA(isA<ArgumentError>()),
            reason: entry.key,
          );
          continue;
        }
        expect(
          render(name['value'] as String, colors, square: true),
          entry.value as String,
          reason: entry.key,
        );
      }
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
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 320,
        ),
      );
      expect(svg, startsWith('<svg viewBox="0 0 36 36" fill="none"'));
      expect(svg, contains('width="320" height="320"'));
    });
  });

  group('an empty palette fails, and only for beam', () {
    test(
      'the failure names the palette rather than leaking an index error',
      () {
        // The user's ruling was "throw, in a Dart-idiomatic way" — so what a
        // caller sees has to be about *their* input, not about a null slice.
        expect(
          () =>
              buildBeamScene(name: 'Clara Barton', colors: const [], size: 80),
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
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 80,
        ),
        returnsNormally,
      );
    });
  });
}
