import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:boring_avatars/src/variants/sunset.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layer-2 parity for `sunset`, against what upstream actually rendered.
///
/// Two things this variant carries that no earlier one did: the drawing is
/// painted by gradients declared in a `<defs>` *outside* the masked group, and
/// the gradients' ids are derived from the **name**. The second is invisible to
/// the byte sweep — the harness normalises ids away on both sides — so it is
/// asserted separately against ids the harness recorded unnormalised.
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

  group('sunset reproduces upstream byte for byte', () {
    for (final n in names) {
      test('${n['id']}', () {
        for (final p in palettes) {
          final expected = renders['sunset|${n['id']}|${p['id']}'] as String;
          final actual = normalise(
            emitSvg(
              buildSunsetScene(
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
      final covered = renders.keys.where((k) => k.startsWith('sunset|')).length;
      expect(covered, names.length * palettes.length);
    });
  });

  group('the gradient ids the byte sweep cannot see', () {
    // `normalise` erases `id="…"` and `url(#…)` on both sides, so every
    // assertion above holds for a port that named its gradients anything at
    // all. Upstream derives them from the name — and strips whitespace out of
    // it — which is a real derivation with real edge cases.
    final derived = svgFixture['derivedIdentifiers'] as Map<String, dynamic>;
    final sunset = derived['sunset'] as Map<String, dynamic>;

    for (final n in names) {
      test('${n['id']} — ids and references match upstream exactly', () {
        final expected = sunset[n['id']] as Map<String, dynamic>;
        final svg = emitSvg(
          buildSunsetScene(
            name: n['value'] as String,
            colors: (palettes.first['value'] as List).cast<String>(),
            size: matrixSize,
          ),
        );
        final ids = RegExp(
          ' id="([^"]*)"',
        ).allMatches(svg).map((m) => m.group(1)).toList();
        final references = RegExp(
          r'url\(#([^)]*)\)',
        ).allMatches(svg).map((m) => m.group(1)).toList();
        expect(ids, expected['ids'], reason: 'ids for ${n['id']}');
        expect(
          references,
          expected['references'],
          reason: 'references for ${n['id']}',
        );
      });
    }

    test('every reference names an id that is actually declared', () {
      // A reference that points at nothing makes a browser draw *nothing* —
      // measured, 0,0,0,0 at every pixel. So a derivation that drifted between
      // the two sites would blank the avatar without erroring.
      for (final n in names) {
        final svg = emitSvg(
          buildSunsetScene(
            name: n['value'] as String,
            colors: const ['#FF0000'],
            size: matrixSize,
          ),
        );
        final ids = RegExp(
          ' id="([^"]*)"',
        ).allMatches(svg).map((m) => m.group(1)!).toSet();
        for (final match in RegExp(r'url\(#([^)]*)\)').allMatches(svg)) {
          expect(ids, contains(match.group(1)), reason: '${n['id']}');
        }
      }
    });

    test('whitespace is stripped from the id but not from the title', () {
      // The id uses `name.replace(/\s/g, '')`; `<title>` uses the raw name.
      // Measured: Dart's `\s` matches exactly the same 25 code points as
      // JavaScript's, so the port is a straight translation — both follow
      // ECMAScript's WhiteSpace plus LineTerminator.
      final svg = emitSvg(
        buildSunsetScene(
          name: 'a b\tc\nd',
          colors: const ['#FF0000'],
          size: 80,
        ),
      );
      expect(svg, contains('<title>a b\tc\nd</title>'));
      expect(svg, contains('id="gradient_paint0_linear_abcd"'));
      expect(svg, contains('url(#gradient_paint0_linear_abcd)'));
    });

    test('and the whitespace class is JavaScript\'s, not just ASCII', () {
      // The corpus only ever puts U+0020, U+0009 and U+000A in a name, so a
      // port that stripped `[ \t\n]` instead of `\s` passed the whole suite.
      // JavaScript's `\s` is 25 code points; these four are the ones a name is
      // most likely to actually carry — a non-breaking space from a paste, and
      // the ideographic space Korean and Japanese input produces.
      for (final space in [' ', '　', ' ', '﻿']) {
        final svg = emitSvg(
          buildSunsetScene(
            name: 'a${space}b',
            colors: const ['#FF0000'],
            size: 80,
          ),
        );
        expect(
          svg,
          contains('id="gradient_paint0_linear_ab"'),
          reason: 'U+${space.codeUnitAt(0).toRadixString(16).toUpperCase()}',
        );
      }
    });
  });

  group('what an empty palette does here', () {
    test('the stops lose their colour rather than the shapes losing fill', () {
      // Every other variant answers an empty palette by dropping `fill`, which
      // draws nothing. `sunset` drops `stop-color` instead — and SVG's initial
      // value for that is **black**, so the avatar comes out solid black.
      // Confirmed in Chrome. Reproducing the markup reproduces the behaviour.
      final svg = emitSvg(
        buildSunsetScene(name: 'Clara Barton', colors: const [], size: 80),
      );
      expect(svg, contains('<stop></stop>'));
      expect(svg, contains('<stop offset="1"></stop>'));
      expect(svg, isNot(contains('stop-color')));
      // The paths keep their gradient fill; it is the stops that go bare.
      expect(svg, contains('fill="url(#gradient_paint0_linear_ClaraBarton)"'));
    });
  });

  group('square drops the corner radius rather than defaulting it', () {
    final squareRenders = svgFixture['squareRenders'] as Map<String, dynamic>;

    test('every square render matches upstream byte for byte', () {
      final keys = squareRenders.keys.where((k) => k.startsWith('sunset|'));
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
              buildSunsetScene(
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
        buildSunsetScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: size,
        ),
      );
      // The strip must not erase the *mask's* width and height, which are also
      // 80. Erasing them hid a real leak: a mask region built from the caller's
      // `size` instead of the variant's constant passed the entire suite,
      // because the whole fixture renders at 80 — where the two are equal — and
      // the strip normalised away the difference at 40. Only the root `<svg>`'s
      // pair may be normalised, and `replaceFirst` is what keeps it to that one.
      String strip(String s) => s.replaceFirst(
        RegExp(r'width="(40|80)" height="(40|80)"'),
        'width="_" height="_"',
      );
      expect(strip(svgFor(40)), strip(svgFor(80)));
    });
  });
}
