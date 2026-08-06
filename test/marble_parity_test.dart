import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/src/js/utilities.dart';
import 'package:boring_avatars/src/svg/emitter.dart';
import 'package:boring_avatars/src/variants/marble.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layer-2 parity for `marble`, against what upstream actually rendered.
///
/// Every render of this variant in the fixture — 20 names × 5 palettes — is
/// rebuilt from a name and a palette and compared **byte for byte**. That is
/// also the layer-1 proof: upstream exports no per-variant generator, so the
/// three elements' colours, translations, rotations and scales are only
/// observable as the attributes they land in.
///
/// **Three layer-1 facts are not fully observable that way**, and each has its
/// own group below:
///
/// * the first path's `scale` comes from `properties[2]`, not `properties[1]`;
/// * `properties[0]`'s placement and `properties[1]`'s scale are computed and
///   never read, so a mutation to either survives the whole sweep;
/// * the `filter` reference is erased by `normalise` on both sides, so the
///   sweep says nothing about whether the two paths point at a filter that
///   exists.
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

  group('marble reproduces upstream byte for byte', () {
    for (final n in names) {
      test('${n['id']}', () {
        for (final p in palettes) {
          final expected = renders['marble|${n['id']}|${p['id']}'] as String;
          final actual = normalise(
            emitSvg(
              buildMarbleScene(
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
      final covered = renders.keys.where((k) => k.startsWith('marble|')).length;
      expect(covered, names.length * palettes.length);
    });
  });

  group('the identifiers the byte sweep erases', () {
    // `normalise` replaces `id="…"`, `url(#…)` and `mask="…"` on both sides, so
    // a port that named its filter anything at all — or pointed both paths at a
    // filter that does not exist — passes all 100 renders. `marble` is the
    // first variant with **two** kinds of reference, and the second one is the
    // whole picture: an unresolvable `filter` is ignored by a browser, which
    // draws the blobs unblurred rather than erroring.
    // Recorded **per name**, because for `sunset` the ids genuinely vary by
    // name (hidden-state #38). For `marble` they do not, and the group below
    // asserts that rather than assuming it.
    final perName =
        (svgFixture['derivedIdentifiers'] as Map<String, dynamic>)['marble']
            as Map<String, dynamic>;
    final identifiers = perName['upstream-default'] as Map<String, dynamic>;

    String svgFor(String name) => emitSvg(
      buildMarbleScene(
        name: name,
        colors: const ['#FF0000', '#00FF00'],
        size: matrixSize,
      ),
    );

    test('every id upstream declares is declared here, spelled the same', () {
      final svg = svgFor('Clara Barton');
      final ids = (identifiers['ids'] as List).cast<String>();
      // A count first: the fixture holding one id where we emit two would
      // otherwise satisfy a loop that only checks the ones it was given.
      expect(ids, ['mask__marble', 'prefix__filter0_f']);
      expect(svg, contains('<mask id="mask__marble"'));
      expect(svg, contains('<filter id="prefix__filter0_f"'));
    });

    test('and every reference resolves to one of them', () {
      final svg = svgFor('Clara Barton');
      final references = (identifiers['references'] as List).cast<String>();
      // Three, not two: the mask is referenced once and the filter twice, once
      // per path. A port that dropped the filter from either path still emits
      // valid markup and still renders — just not blurred.
      expect(references, [
        'mask__marble',
        'prefix__filter0_f',
        'prefix__filter0_f',
      ]);
      expect(svg, contains('mask="url(#mask__marble)"'));
      expect(
        RegExp(r'filter="url\(#prefix__filter0_f\)"').allMatches(svg),
        hasLength(2),
      );
      // The relation that actually matters, stated as a relation rather than
      // as two literals: nothing may be referenced that is not declared.
      final declared = RegExp(
        'id="([^"]*)"',
      ).allMatches(svg).map((m) => m.group(1)!).toSet();
      final referenced = RegExp(
        r'url\(#([^)]*)\)',
      ).allMatches(svg).map((m) => m.group(1)!).toSet();
      expect(referenced.difference(declared), isEmpty);
    });

    test('the ids do not vary with the name — only `sunset` does that', () {
      // Hidden-state #38: `sunset` builds an id from the caller's name, so its
      // ids are recorded per name and really do differ. `marble`'s are
      // literals in the JSX, and upstream's own 20 records agree on that —
      // asserted from the fixture rather than from our reading of the source.
      expect(perName, hasLength(names.length));
      expect(
        perName.values.map((v) => jsonEncode(v)).toSet(),
        hasLength(1),
        reason: 'upstream emits the same ids for every name',
      );
      // And ours do too, including for a name that would need escaping if it
      // ever reached an id.
      expect(
        RegExp(
          'id="([^"]*)"',
        ).allMatches(svgFor("O'Brien")).map((m) => m.group(1)).toList(),
        RegExp(
          'id="([^"]*)"',
        ).allMatches(svgFor('Clara Barton')).map((m) => m.group(1)).toList(),
      );
    });
  });

  group('both paths are scaled by properties[2], not by their own element', () {
    /// The two `scale(…)` factors upstream wrote, read out of the fixture in
    /// document order.
    List<double> fixtureScales(String nameId) {
      final svg = renders['marble|$nameId|single'] as String;
      final matches = RegExp(
        r'scale\(([0-9.]+)\)',
      ).allMatches(svg).map((m) => double.parse(m.group(1)!)).toList();
      expect(matches, hasLength(2), reason: nameId);
      return matches;
    }

    test('upstream writes the same factor on both paths, for every name', () {
      // This is the observation, straight from the reference's own output —
      // stated before any claim about *which* element it came from.
      for (final n in names) {
        final scales = fixtureScales(n['id'] as String);
        expect(scales[0], scales[1], reason: n['id'] as String);
      }
    });

    test('and that factor is properties[2].scale', () {
      for (final n in names) {
        final properties = marbleProperties(n['value'] as String, const [
          '#FF0000',
        ]);
        expect(fixtureScales(n['id'] as String), [
          properties[2].scale,
          properties[2].scale,
        ], reason: n['id'] as String);
      }
    });

    test(
      'which is a different number from properties[1].scale on 11 of 20',
      () {
        // The discriminating power of the sweep above depends on this count. If
        // it were 0 the whole 100-render comparison would be blind to the swap,
        // the way `bauhaus`'s `isSquare` sweep is blind to a threaded `i` — so
        // the number is asserted, not assumed.
        final differing = names
            .where((n) {
              final p = marbleProperties(n['value'] as String, const [
                '#FF0000',
              ]);
              return p[1].scale != p[2].scale;
            })
            .map((n) => n['id'] as String);

        expect(differing, hasLength(11));
        expect(
          differing,
          containsAll(<String>[
            'upstream-default', // 1.4 vs 1.3
            'single-char', // 1.4 vs 1.5
            'punctuation', // 1.2 vs 1.4
            'high-codeunits', // 1.2 vs 1.4
          ]),
        );
      },
    );

    test(
      'and 11 of 20 is not a corpus accident — it is 3 in 4 by derivation',
      () {
        // The two scales are `getUnit(2h, 4)` and `getUnit(3h, 4)`, and with no
        // index `getUnit` is a plain remainder on a non-negative number. So:
        //
        //   2h mod 4  is 0 when h is even and 2 when h is odd  — never odd
        //   3h mod 4  cycles 0, 3, 2, 1 over h mod 4           — all four
        //
        // Element 1's scale can therefore only ever be 1.2 or 1.4, for **any**
        // name. They differ whenever h is odd (element 2 is then odd and element
        // 1 cannot be) and additionally when h ≡ 2 (mod 4) — which is 1/2 + 1/4.
        //
        // This matters because a count measured over 20 names is a fact about
        // those 20 names. The derivation says the sweep stays discriminating
        // whatever the corpus becomes.
        var differ = 0;
        for (var h = 0; h < 4000; h++) {
          final one = 1.2 + jsGetUnit(h * 2, 4) / 10;
          final two = 1.2 + jsGetUnit(h * 3, 4) / 10;
          expect(one, anyOf(1.2, 1.4), reason: 'h=$h');
          if (one != two) differ++;
        }
        expect(differ, 3000);

        // And every name is odd-or-not by its hash, so the rule reaches the
        // corpus rather than only the synthetic sweep.
        for (final n in names) {
          final hash = jsHashCode(n['value'] as String);
          final p = marbleProperties(n['value'] as String, const ['#FF0000']);
          expect(
            p[1].scale != p[2].scale,
            hash.isOdd || hash % 4 == 2,
            reason: '${n['id']} (hash $hash)',
          );
        }
      },
    );

    test('the scale takes all four of its reachable values over the corpus', () {
      // Otherwise the assertions above could hold with `scale` pinned to a
      // constant. `1.2 + getUnit(n, 4) / 10` can only be these four.
      final seen = {
        for (final n in names)
          marbleProperties(n['value'] as String, const ['#FF0000'])[2].scale,
      };
      expect(seen, {1.2, 1.3, 1.4, 1.5});
      // `properties[1]` reaches only two of the four over this corpus, which
      // is a fact about the corpus and not about the formula: `getUnit(h*2, 4)`
      // is `2h mod 4`, always even. So element 1's scale can **only** ever be
      // 1.2 or 1.4, for any name — while element 2's `3h mod 4` reaches all
      // four. That asymmetry is why the swap is visible so often.
      final fromElementOne = {
        for (final n in names)
          marbleProperties(n['value'] as String, const ['#FF0000'])[1].scale,
      };
      expect(fromElementOne, {1.2, 1.4});
    });

    test(
      'the sum lands exactly on the literal, so no long decimal is emitted',
      () {
        // `1.2 + u / 10` is a float64 addition and its result is *not* obviously
        // the double nearest the decimal. Measured in Node and here: all four
        // reachable values are bit-identical to the literal, so `jsNum` prints
        // two significant digits. A range wider than 4 would need re-measuring.
        for (var u = 0; u < 4; u++) {
          expect(1.2 + u / 10, [1.2, 1.3, 1.4, 1.5][u]);
        }
        final svg = emitSvg(
          buildMarbleScene(
            name: 'Clara Barton',
            colors: const ['#FF0000'],
            size: matrixSize,
          ),
        );
        expect(svg, isNot(contains(RegExp(r'scale\([0-9]+\.[0-9]{2,}\)'))));
      },
    );
  });

  group('the values upstream computes and never reads', () {
    // Three of fifteen generated numbers reach nothing: `properties[0]`'s
    // translateX / translateY / rotate / scale, and `properties[1]`'s scale.
    // They are computed because upstream's `Array.from` callback is a single
    // expression and special-casing an index would invent a structure the
    // reference does not have — the same judgement `bauhaus` records for its
    // element 0.
    //
    // The consequence is that a mutation to either **survives the entire
    // suite**, so these tests pin the formula directly. That is the third
    // answer from the lessons file: not "strengthen the test", not "delete the
    // code", but record that the value is unreachable and freeze its shape.
    test('element 0 contributes a colour and nothing else', () {
      final svg = emitSvg(
        buildMarbleScene(
          name: 'Clara Barton',
          colors: const ['#111111', '#222222', '#333333'],
          size: matrixSize,
        ),
      );
      final properties = marbleProperties('Clara Barton', const [
        '#111111',
        '#222222',
        '#333333',
      ]);
      // Its colour is the background rect's fill …
      expect(
        svg,
        contains('<rect width="80" height="80" fill="${properties[0].color}">'),
      );
      // … and its placement appears nowhere. Guard against a coincidence by
      // requiring the value to be one that would be visible if it were used.
      expect(properties[0].rotate, isNot(0));
      expect(svg, isNot(contains('rotate(${properties[0].rotate} 40 40)')));
    });

    test('element 1 supplies a placement but not a scale', () {
      final properties = marbleProperties('Clara Barton', const ['#FF0000']);
      final svg = emitSvg(
        buildMarbleScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: matrixSize,
        ),
      );
      expect(
        svg,
        contains(
          'translate(${properties[1].translateX} ${properties[1].translateY}) '
          'rotate(${properties[1].rotate} 40 40) '
          'scale(${properties[2].scale})',
        ),
      );
      // The witness: element 1's own scale is a different number here, so this
      // assertion fails on a port that used it.
      expect(properties[1].scale, isNot(properties[2].scale));
      expect(svg, isNot(contains('scale(${properties[1].scale})')));
    });

    test('the generator still produces three complete elements', () {
      // A port that stopped computing the unread fields would pass everything
      // above. This is what says the loop is upstream's shape.
      final properties = marbleProperties('Clara Barton', const ['#FF0000']);
      expect(properties, hasLength(3));
      for (final p in properties) {
        expect(p.scale, inInclusiveRange(1.2, 1.5));
        expect(p.translateX.abs(), lessThan(8));
        expect(p.translateY.abs(), lessThan(8));
        expect(p.rotate.abs(), lessThan(360));
      }
    });
  });

  group('the second path blends and the first does not', () {
    test('mix-blend-mode is an inline style on exactly one path', () {
      final svg = emitSvg(
        buildMarbleScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: matrixSize,
        ),
      );
      expect(
        RegExp('style="mix-blend-mode:overlay"').allMatches(svg),
        hasLength(1),
      );
      // And it is the *second* one — the order decides what blends against
      // what, so a style on the first path is a different picture.
      final paths = RegExp(r'<path\b([^>]*)>').allMatches(svg).toList();
      expect(paths, hasLength(2));
      expect(paths[0].group(1), isNot(contains('style=')));
      expect(paths[1].group(1), contains('style="mix-blend-mode:overlay"'));
    });

    test('the filter declares sRGB interpolation, not the default', () {
      // The SVG default for `color-interpolation-filters` is **linearRGB**, so
      // a blur that ignored this attribute would work in the wrong space and
      // come out visibly different. It is an attribute whose absence changes
      // the picture, which is why it is asserted rather than assumed.
      final svg = emitSvg(
        buildMarbleScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: matrixSize,
        ),
      );
      expect(svg, contains('color-interpolation-filters="sRGB"'));
      expect(svg, contains('<feGaussianBlur stdDeviation="7"'));
      // No x/y/width/height on the filter — the region is the spec's default,
      // and a port that wrote them out would be inventing numbers upstream
      // does not emit.
      final filter = RegExp(r'<filter\b([^>]*)>').firstMatch(svg)!.group(1)!;
      expect(filter, isNot(contains('x=')));
      expect(filter, isNot(contains('width=')));
      expect(filter, contains('filterUnits="userSpaceOnUse"'));
    });
  });

  group('an empty palette degrades — it does not throw', () {
    test('all three fills are dropped, and nothing falls back to black', () {
      // Hidden-state #8 is per call site: five variants degrade and `beam`
      // throws. `marble` degrades, on all three of its coloured elements.
      final svg = emitSvg(
        buildMarbleScene(name: 'Clara Barton', colors: const [], size: 80),
      );
      // Two `fill`s survive and neither comes from the palette: the root
      // `<svg fill="none">` and the mask's literal `#FFFFFF`. Counting them is
      // what makes this fail if a palette colour reappears from a default.
      expect('fill='.allMatches(svg), hasLength(2));
      expect(svg, contains('<svg viewBox="0 0 80 80" fill="none"'));
      expect(svg, contains('fill="#FFFFFF"'));
      // The paths are still there, still placed, still filtered — only the
      // paint is gone.
      expect(RegExp(r'<path\b').allMatches(svg), hasLength(2));
    });
  });

  group('square drops the corner radius rather than defaulting it', () {
    final squareRenders = svgFixture['squareRenders'] as Map<String, dynamic>;

    test('every square render matches upstream byte for byte', () {
      final keys = squareRenders.keys.where((k) => k.startsWith('marble|'));
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
              buildMarbleScene(
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
        buildMarbleScene(
          name: 'Clara Barton',
          colors: const ['#FF0000'],
          size: size,
        ),
      );
      // Only the root `<svg>`'s pair may be normalised. `marble` carries three
      // more `width="80" height="80"` pairs — the mask's region, the mask's
      // rect and the background rect — and erasing those would hide a mask
      // region built from the caller's `size`.
      String strip(String s) => s.replaceFirst(
        RegExp(r'width="(40|80)" height="(40|80)"'),
        'width="_" height="_"',
      );
      expect(strip(svgFor(40)), strip(svgFor(80)));
    });
  });
}
