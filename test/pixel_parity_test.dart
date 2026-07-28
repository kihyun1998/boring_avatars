import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:boring_avatars/src/variants/pixel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layer-2 parity for `pixel`, against what upstream actually rendered.
///
/// Every render of this variant in the fixture — 20 names × 5 palettes — is
/// rebuilt from a name and a palette and compared **byte for byte**. Nothing
/// here is hand-fed: the only inputs are the ones a caller would supply.
///
/// This is also the layer-1 proof. Upstream exports no per-variant generator,
/// so the values are only observable as the attributes they land in — and every
/// value that reaches the drawing is in this string.
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

  /// The harness replaces generated ids so a runtime-random one cannot make a
  /// fixture unstable. Ours is a fixed string upstream, but the comparison has
  /// to use the same normalisation or it is comparing different things.
  String normalise(String svg) => svg
      .replaceAll(RegExp('id="[^"]*"'), 'id="_"')
      .replaceAll(RegExp(r'url\(#[^)]*\)'), 'url(#_)')
      .replaceAll(RegExp('mask="[^"]*"'), 'mask="_"');

  group('pixel reproduces upstream byte for byte', () {
    for (final n in names) {
      test('${n['id']}', () {
        for (final p in palettes) {
          final expected = renders['pixel|${n['id']}|${p['id']}'] as String;
          final actual = normalise(
            emitSvg(
              buildPixelScene(
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
      final covered = renders.keys.where((k) => k.startsWith('pixel|')).length;
      expect(covered, names.length * palettes.length);
    });

    test('the mask id and its reference are upstream\'s literals', () {
      // Added in #37 — the normalisation erased both on either side, so the
      // byte comparison never checked them. See the same test in
      // `ring_parity_test.dart` for the reasoning.
      final identifiers =
          (svgFixture['maskIdentifiers'] as Map<String, dynamic>)['pixel']
              as Map<String, dynamic>;
      final svg = emitSvg(
        buildPixelScene(
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

  group('the two traps this variant carries', () {
    test('the first tile has no fill, for every name and every palette', () {
      // hidden-state #17. Upstream indexes with `hash % i` from i == 0, which
      // is NaN, so colors[NaN] is undefined and React drops the attribute.
      // A port that fills tile 0 is byte-wrong on 100% of renders.
      for (final n in names) {
        for (final p in palettes) {
          final colours = pixelColors(
            n['value'] as String,
            (p['value'] as List).cast<String>(),
          );
          expect(colours, hasLength(64));
          expect(colours.first, isNull, reason: '${n['id']}/${p['id']}');
        }
      }
    });

    test('an empty palette leaves every tile unfilled, and does not throw', () {
      final colours = pixelColors('Clara Barton', const []);
      expect(colours.where((c) => c == null), hasLength(64));
    });

    test('tiles are emitted in upstream order, not reading order', () {
      // The first row runs x = 0, 20, 40, 60, 10, 30, 50, 70. If the builder
      // walked the grid left to right, the bytes would differ while the picture
      // stayed identical — which is exactly the kind of divergence only a
      // byte-level gate can see.
      final svg = emitSvg(
        buildPixelScene(
          name: 'Clara Barton',
          colors: const ['#FF0000', '#00FF00'],
          size: 80,
        ),
      );
      final xs = RegExp(r'<rect(?: x="(\d+)")?(?: y="(\d+)")? width="10"')
          .allMatches(svg)
          .take(8)
          .map((m) => int.parse(m.group(1) ?? '0'))
          .toList();
      expect(xs, <int>[0, 20, 40, 60, 10, 30, 50, 70]);
    });
  });

  group('square drops the attribute rather than defaulting it', () {
    // Added in #37: this variant shipped in #36 with `square` asserted only
    // against itself, because the fixture matrix had no square renders. It
    // does now.
    final squareRenders = svgFixture['squareRenders'] as Map<String, dynamic>;

    test('every square render matches upstream byte for byte', () {
      final keys = squareRenders.keys.where((k) => k.startsWith('pixel|'));
      expect(
        keys,
        isNotEmpty,
        reason: 'the fixture has no pixel square renders',
      );
      for (final key in keys) {
        final parts = key.split('|');
        final name = names.firstWhere((n) => n['id'] == parts[1]);
        final palette = palettes.firstWhere((p) => p['id'] == parts[2]);
        expect(
          normalise(
            emitSvg(
              buildPixelScene(
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

    test('rx is absent when square is true, present when it is not', () {
      String svgFor({required bool square}) => emitSvg(
        buildPixelScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 80,
          square: square,
        ),
      );
      expect(svgFor(square: false), contains('rx="160"'));
      expect(svgFor(square: true), isNot(contains('rx=')));
      // And nothing else moves — upstream expresses this by passing undefined.
      expect(
        svgFor(square: true).replaceAll(' rx="160"', ''),
        svgFor(square: false).replaceAll(' rx="160"', ''),
      );
    });
  });

  group('size is a passthrough', () {
    test('it reaches width and height and nothing else', () {
      final small = emitSvg(
        buildPixelScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 40,
        ),
      );
      final large = emitSvg(
        buildPixelScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 80,
        ),
      );
      String strip(String s) =>
          s.replaceAll(RegExp(r'(width|height)="(40|80)"'), r'$1="_"');
      expect(strip(small), strip(large));
    });
  });
}
