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

  /// An attribute value as it exists **after XML parsing**, which is the form a
  /// browser matches on. The emitted bytes carry `&#x27;`; the DOM carries `'`.
  String unescapeXml(String value) => value
      .replaceAll('&#x27;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  /// Resolves a reference the way a browser does: undo `%XX`, leave the rest.
  ///
  /// `Uri.decodeComponent` is the wrong tool twice over — it rejects strings
  /// this port never produces but the corpus does contain, and it is stricter
  /// than the fragment matching a browser actually performs. Written out so it
  /// undoes exactly what `sunsetUrlReference` does and nothing more.
  ///
  /// The literal runs are encoded **as whole substrings**. Doing it character by
  /// character splits a surrogate pair — the emoji names came back as `��`.
  String decodeReference(String reference) {
    final bytes = <int>[];
    var literalStart = 0;
    for (var i = 0; i < reference.length; i++) {
      if (reference[i] != '%' || i + 2 >= reference.length) continue;
      bytes.addAll(utf8.encode(reference.substring(literalStart, i)));
      bytes.add(int.parse(reference.substring(i + 1, i + 3), radix: 16));
      i += 2;
      literalStart = i + 1;
    }
    bytes.addAll(utf8.encode(reference.substring(literalStart)));
    return utf8.decode(bytes, allowMalformed: true);
  }

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
                title: true,
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

    /// The names whose reference upstream writes in a form a browser cannot
    /// read, and where this port therefore diverges **on purpose**.
    ///
    /// Ruled by the user on 2026-07-29 and recorded in the divergence ledger.
    /// Listed by name rather than detected, so the set can only grow by someone
    /// editing this line — a repair that started firing on a name nobody
    /// intended would fail here rather than pass quietly.
    const repaired = {'punctuation'};

    for (final n in names) {
      final id = n['id'] as String;
      test(
        '$id — ids match upstream, and references diverge only if listed',
        () {
          final expected = sunset[id] as Map<String, dynamic>;
          final svg = emitSvg(
            buildSunsetScene(
              title: true,
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
          ).allMatches(svg).map((m) => m.group(1)!).toList();

          // **The ids are byte-identical to upstream for every name.** That is
          // what makes the repair as small as it is: only the reference moves.
          expect(ids, expected['ids'], reason: 'ids for $id');

          if (!repaired.contains(id)) {
            expect(references, expected['references'], reason: 'refs for $id');
            return;
          }

          // For a repaired name the reference must differ from upstream's — and
          // differ *only* by percent-decoding back to it, so the repair cannot
          // quietly become something else.
          expect(
            references,
            isNot(expected['references']),
            reason: '$id is listed as repaired but nothing was repaired',
          );
          expect(
            references.map((r) => decodeReference(unescapeXml(r))).toList(),
            (expected['references'] as List)
                .map((r) => unescapeXml(r as String))
                .toList(),
            reason: 'the repair must be exactly a percent-encoding of upstream',
          );
        },
      );
    }

    test('every reference resolves to an id that is actually declared', () {
      // A reference that points at nothing makes a browser draw *nothing* —
      // measured, 0,0,0,0 at every pixel. This is the assertion the repair
      // exists to satisfy, so it models both steps a browser takes: parse the
      // XML — which turns `&#x27;` back into `'` on **both** sides — then
      // percent-decode the fragment and match it against the id.
      for (final n in names) {
        final svg = emitSvg(
          buildSunsetScene(
            title: true,
            name: n['value'] as String,
            colors: const ['#FF0000'],
            size: matrixSize,
          ),
        );
        final ids = RegExp(
          ' id="([^"]*)"',
        ).allMatches(svg).map((m) => unescapeXml(m.group(1)!)).toSet();
        final references = RegExp(r'url\(#([^)]*)\)').allMatches(svg);
        expect(references, isNotEmpty, reason: '${n['id']}');
        for (final match in references) {
          expect(
            ids,
            contains(decodeReference(unescapeXml(match.group(1)!))),
            reason: '${n['id']}',
          );
        }
      }
    });

    test('the repair fires only where a browser needs it', () {
      // Korean and emoji resolve as they stand — measured in Chrome — so a
      // repair that encoded them would change bytes for nothing.
      for (final safe in ['ClaraBarton', '박기현', '🎨', 'a-b_c.d~e']) {
        expect(sunsetUrlReference(safe), safe, reason: safe);
      }
      // These end a CSS url token, or start an escape when it is resolved.
      expect(sunsetUrlReference("O'Brien"), 'O%27Brien');
      expect(sunsetUrlReference('a"b'), 'a%22b');
      expect(sunsetUrlReference('f(x)'), 'f%28x%29');
      expect(sunsetUrlReference(r'a\b'), 'a%5Cb');
      // `%` itself, or a name already containing `%27` would decode into a
      // different id than the one declared. Measured: unencoded, blank.
      expect(sunsetUrlReference('a%27b'), 'a%2527b');
    });

    test('whitespace is stripped from the id but not from the title', () {
      // The id uses `name.replace(/\s/g, '')`; `<title>` uses the raw name.
      // Measured: Dart's `\s` matches exactly the same 25 code points as
      // JavaScript's, so the port is a straight translation — both follow
      // ECMAScript's WhiteSpace plus LineTerminator.
      final svg = emitSvg(
        buildSunsetScene(
          title: true,
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
            title: true,
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
        buildSunsetScene(
          title: true,
          name: 'Clara Barton',
          colors: const [],
          size: 80,
        ),
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
                title: true,
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
          title: true,
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
