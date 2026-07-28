import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:boring_avatars/src/variants/ring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layer-2 parity for `ring`, against what upstream actually rendered.
///
/// Every render of this variant in the fixture — 20 names × 5 palettes — is
/// rebuilt from a name and a palette and compared **byte for byte**.
///
/// This is also the layer-1 proof. Upstream exports no per-variant generator,
/// so the nine slot colours are only observable as the `fill` attributes they
/// land in, and every one of them is in this string.
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

  /// The nine `fill`s in DOM order, `null` where the attribute is absent.
  ///
  /// Read out of the *rendered* string rather than out of our own builder — a
  /// slot mapping asserted against the constant that produced it would be a
  /// tautology.
  List<String?> fillsOf(String svg) {
    final shapes = RegExp(r'<(?:path|circle)\b([^>]*)>').allMatches(svg);
    return [
      for (final s in shapes)
        RegExp('fill="([^"]*)"').firstMatch(s.group(1)!)?.group(1),
    ];
  }

  group('ring reproduces upstream byte for byte', () {
    for (final n in names) {
      test('${n['id']}', () {
        for (final p in palettes) {
          final expected = renders['ring|${n['id']}|${p['id']}'] as String;
          final actual = normalise(
            emitSvg(
              buildRingScene(
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
      final covered = renders.keys.where((k) => k.startsWith('ring|')).length;
      expect(covered, names.length * palettes.length);
    });

    test('the mask id and its reference are upstream\'s literals', () {
      // `normalise` erases `id="…"`, `url(#…)` and `mask="…"` on both sides, so
      // the byte comparison above says nothing about either. That exclusion is
      // right for the ids 1.8.0 generates with `useId` and buys nothing here,
      // where they are literals in the JSX — mutating `mask__ring` to
      // `mask__pixel`, or the group's reference to a dangling one, left the
      // whole suite green. The harness records them unnormalised for this.
      final identifiers =
          (svgFixture['maskIdentifiers'] as Map<String, dynamic>)['ring']
              as Map<String, dynamic>;
      final svg = emitSvg(
        buildRingScene(
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
      // And they must agree, or the group references a mask that is not there.
      expect(identifiers['references'], identifiers['ids']);
    });
  });

  group('the nine slots are drawn from five colours by a fixed remap', () {
    test('upstream\'s own output shows slots 1=2, 3=4, 5=6 and 0=7', () {
      // The remap is `[0, 1, 1, 2, 2, 3, 3, 0, 4]`, so four pairs of slots must
      // carry the same colour in *every* render — and slot 8 is the only one
      // that can never repeat slot 0. Asserted against the fixture, so this
      // fails if our constant is wrong rather than agreeing with itself.
      for (final n in names) {
        for (final p in palettes) {
          final fills = fillsOf(
            renders['ring|${n['id']}|${p['id']}'] as String,
          );
          final where = '${n['id']}/${p['id']}';
          expect(fills, hasLength(9), reason: where);
          expect(fills[1], fills[2], reason: 'slots 1 and 2 — $where');
          expect(fills[3], fills[4], reason: 'slots 3 and 4 — $where');
          expect(fills[5], fills[6], reason: 'slots 5 and 6 — $where');
          expect(fills[0], fills[7], reason: 'slots 0 and 7 — $where');
        }
      }
    });

    test('and the five draws are consecutive from the same hash', () {
      // `getRandomColor(numFromName + i, …)` for i in 0..4 — not five
      // independent draws. With a palette bigger than five, consecutive slots
      // therefore walk the palette by one, which pins the `+ i` rather than
      // just the remap.
      const palette = [
        '#000000',
        '#111111',
        '#222222',
        '#333333',
        '#444444',
        '#555555',
        '#666666',
      ];
      final slots = ringColors('Clara Barton', palette);
      final shuffle = [slots[0], slots[1], slots[3], slots[5], slots[8]];
      final first = palette.indexOf(shuffle.first!);
      expect(shuffle, [
        for (var i = 0; i < 5; i++) palette[(first + i) % palette.length],
      ]);
    });

    test('an empty palette leaves every slot unfilled, and does not throw', () {
      expect(ringColors('Clara Barton', const []), List.filled(9, null));
    });
  });

  group('square drops the corner radius rather than defaulting it', () {
    // Until #37 this group asserted only *self-consistency* — that `rx` is
    // there when square is false and gone when it is true — and a golden was
    // committed for the square render. Neither had ever been compared to
    // upstream, because the fixture matrix ran at `square: false` only. The
    // harness now emits a square matrix, so the claim is measured.
    final squareRenders = svgFixture['squareRenders'] as Map<String, dynamic>;

    test('every square render matches upstream byte for byte', () {
      final keys = squareRenders.keys.where((k) => k.startsWith('ring|'));
      expect(
        keys,
        isNotEmpty,
        reason: 'the fixture has no ring square renders',
      );
      for (final key in keys) {
        final parts = key.split('|');
        final name = names.firstWhere((n) => n['id'] == parts[1]);
        final palette = palettes.firstWhere((p) => p['id'] == parts[2]);
        expect(
          normalise(
            emitSvg(
              buildRingScene(
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
        buildRingScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: 80,
          square: square,
        ),
      );
      expect(svgFor(square: false), contains('rx="180"'));
      expect(svgFor(square: true), isNot(contains('rx=')));
      expect(
        svgFor(square: true).replaceAll(' rx="180"', ''),
        svgFor(square: false).replaceAll(' rx="180"', ''),
      );
    });
  });

  group('size is a passthrough, and the viewBox is not 80', () {
    test('size reaches width and height and nothing else', () {
      String svgFor(int size) => emitSvg(
        buildRingScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: size,
        ),
      );
      String strip(String s) =>
          s.replaceAll(RegExp(r'(width|height)="(40|80)"'), r'$1="_"');
      expect(strip(svgFor(40)), strip(svgFor(80)));
    });

    test('the drawing space is 90 wide, whatever the display size', () {
      // `ring` is the first variant whose viewBox is not its display size, and
      // the rasterizer refuses a target that does not match the viewBox — so
      // this constant is the one that decides what "a ring golden" is.
      expect(
        emitSvg(
          buildRingScene(
            name: 'Clara Barton',
            colors: const ['#FF0000'],
            size: 40,
          ),
        ),
        contains('viewBox="0 0 90 90"'),
      );
    });
  });
}
