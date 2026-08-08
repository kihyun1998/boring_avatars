import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// The public surface, against what upstream actually rendered.
///
/// The five sibling `*_parity_test.dart` files each prove one variant's scene
/// builder. This one proves the thing a caller can actually reach: the barrel's
/// [boringAvatarSvg], including the **dispatch** it goes through — which is the
/// only new mechanism here and the only one those files cannot see.
///
/// The fixture is the right expectation for it without any adaptation: every
/// entry in `renders` was produced by rendering upstream's `Avatar` *component*
/// — the dispatch itself — with a `variant` string, so `renders['ring|…']` is
/// literally "what upstream returns when asked for `ring`".
///
/// **What a full revert would survive.** Almost nothing here: routing `ring` to
/// `marble`'s builder, dropping `.resolved` so `geometric` falls through to the
/// default, or emitting the scene of the wrong version all move bytes in this
/// sweep. The two assertions that would *not* discriminate are called out where
/// they appear.
void main() {
  final corpus =
      jsonDecode(File('test/fixtures/corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final names = (corpus['names'] as List).cast<Map<String, dynamic>>();
  final palettes = (corpus['palettes'] as List).cast<Map<String, dynamic>>();
  final sizes = (corpus['sizes'] as List).cast<int>();

  final svgFixture =
      jsonDecode(File('test/fixtures/v1_6_1/svg.json').readAsStringSync())
          as Map<String, dynamic>;
  final renders = svgFixture['renders'] as Map<String, dynamic>;
  final squareRenders = svgFixture['squareRenders'] as Map<String, dynamic>;
  final sizePassthrough = svgFixture['sizePassthrough'] as Map<String, dynamic>;
  final matrixSize = svgFixture['matrixSize'] as int;

  /// Generated ids are internal references, erased on **both** sides — see
  /// `tool/parity/dump.mjs`. Same three rules as every sibling parity test.
  String normalise(String svg) => svg
      .replaceAll(RegExp('id="[^"]*"'), 'id="_"')
      .replaceAll(RegExp(r'url\(#[^)]*\)'), 'url(#_)')
      .replaceAll(RegExp('mask="[^"]*"'), 'mask="_"');

  /// The six variants upstream dispatches, keyed by the string the fixture uses.
  final dispatched = {
    for (final v in BoringAvatarsVariant.renderable) v.upstreamName: v,
  };

  String render(
    BoringAvatarsVariant variant,
    String name,
    List<String> colors, {
    Object size = 80,
    bool square = false,
  }) => normalise(
    boringAvatarSvg(
      name: name,
      colors: colors,
      size: size,
      version: BoringAvatarsVersion.v1_6_1,
      variant: variant,
      square: square,
    ),
  );

  group('every render upstream produced, through the public function', () {
    for (final entry in dispatched.entries) {
      test('${entry.key} — 20 names × 5 palettes', () {
        var compared = 0;
        var refused = 0;
        for (final n in names) {
          for (final p in palettes) {
            final expected = renders['${entry.key}|${n['id']}|${p['id']}'];
            final name = n['value'] as String;
            final colors = (p['value'] as List).cast<String>();

            if (expected is Map) {
              // Upstream produced no document at all — `beam` × the empty
              // palette (hidden-state #8, ruling S-2). There are no bytes to
              // compare, so the throw *is* the comparison.
              expect(expected['__throws'], 'TypeError');
              expect(
                () => render(entry.value, name, colors, size: matrixSize),
                throwsA(isA<ArgumentError>()),
                reason: '${entry.key}/${n['id']}/${p['id']}',
              );
              refused++;
              continue;
            }

            expect(
              render(entry.value, name, colors, size: matrixSize),
              expected as String,
              reason: '${entry.key}/${n['id']}/${p['id']}',
            );
            compared++;
          }
        }
        // A loop over a fixture slice that silently matched nothing would pass.
        expect(
          compared + refused,
          names.length * palettes.length,
          reason: 'the sweep covered every name and palette, not a subset',
        );
      });
    }

    test('the six sweeps above account for the whole fixture', () {
      // If a variant gained a fixture section without gaining a sweep, the six
      // tests above would all still pass while nobody compared it.
      expect(renders, hasLength(6 * names.length * palettes.length));
      expect(
        renders.keys.map((k) => k.split('|').first).toSet(),
        dispatched.keys.toSet(),
      );
    });

    test('and only `beam` × the empty palette refuses', () {
      final refusals = renders.entries
          .where((e) => e.value is Map)
          .map((e) => e.key.split('|'))
          .toList();
      expect(refusals, hasLength(names.length));
      expect(refusals.map((k) => k[0]).toSet(), {'beam'});
      expect(refusals.map((k) => k[2]).toSet(), {'empty'});
    });
  });

  group('square reaches the public function too', () {
    test('every square render upstream produced', () {
      var compared = 0;
      for (final e in squareRenders.entries) {
        final parts = e.key.split('|');
        final variant = dispatched[parts[0]]!;
        final name = names.firstWhere((n) => n['id'] == parts[1]);
        final palette = palettes.firstWhere((p) => p['id'] == parts[2]);
        final colors = (palette['value'] as List).cast<String>();

        if (e.value is Map) {
          expect(
            () => render(
              variant,
              name['value'] as String,
              colors,
              size: matrixSize,
              square: true,
            ),
            throwsA(isA<ArgumentError>()),
            reason: e.key,
          );
          compared++;
          continue;
        }

        expect(
          render(
            variant,
            name['value'] as String,
            colors,
            size: matrixSize,
            square: true,
          ),
          e.value as String,
          reason: e.key,
        );
        compared++;
      }
      expect(compared, squareRenders.length);
      expect(squareRenders, hasLength(60));
    });
  });

  group('size is injected policy and reaches nothing but width/height', () {
    test('upstream renders the same marble at 40 and at 80', () {
      var compared = 0;
      for (final size in sizes) {
        expect(
          render(
            BoringAvatarsVariant.marble,
            names.first['value'] as String,
            (palettes.first['value'] as List).cast<String>(),
            size: size,
          ),
          sizePassthrough['$size'] as String,
          reason: 'size $size',
        );
        compared++;
      }
      expect(compared, sizes.length);
    });

    test('a string size passes through verbatim', () {
      // Measured against upstream 1.6.1 with a throwaway probe (#59): `'100%'`,
      // `'2rem'` and `'40px'` all land in `width`/`height` unchanged and leave
      // every other byte identical to `size: 80`. The corpus renders only
      // numbers, so the *comparison* below is against our own 80 render — what
      // the probe supplies is the upstream half of the claim.
      const numeric = 80;
      final control = render(BoringAvatarsVariant.marble, 'Clara Barton', [
        '#92A1C6',
        '#146A7C',
      ]);
      for (final size in <String>['100%', '2rem', '40px', '80']) {
        final actual = render(BoringAvatarsVariant.marble, 'Clara Barton', [
          '#92A1C6',
          '#146A7C',
        ], size: size);
        expect(actual, contains('width="$size" height="$size"'));
        expect(
          actual.replaceFirst('width="$size" height="$size"', 'width="§"'),
          control.replaceFirst(
            'width="$numeric" height="$numeric"',
            'width="§"',
          ),
          reason: 'a string size moved something other than width/height',
        );
      }
    });

    test('anything that is not a number or a string is rejected', () {
      // The scene's own guard is an `assert`, which is stripped in release —
      // so the seam a caller reaches has to reject rather than mis-serialise.
      for (final bad in <Object>[
        true,
        <int>[80],
        #size,
      ]) {
        expect(
          () => boringAvatarSvg(
            name: 'Clara Barton',
            colors: const ['#92A1C6'],
            size: bad,
            version: BoringAvatarsVersion.v1_6_1,
          ),
          throwsA(isA<ArgumentError>()),
          reason: '$bad',
        );
      }
    });
  });

  group('the dispatch mirrors upstream avatar.js', () {
    test('a deprecated alias renders its replacement, byte for byte', () {
      // Upstream's `deprecatedVariants` is checked *before* the real six
      // (`avatar.js:22-30`), and the fixture has no `geometric|…` entry because
      // the harness renders the six — so the expectation is the replacement's
      // own upstream render, not our own output for it.
      final name = names.first['value'] as String;
      final colors = (palettes.first['value'] as List).cast<String>();
      final id = names.first['id'];
      final palette = palettes.first['id'];

      expect(
        render(BoringAvatarsVariant.geometric, name, colors, size: matrixSize),
        renders['beam|$id|$palette'] as String,
      );
      expect(
        render(
          BoringAvatarsVariant.abstractStyle,
          name,
          colors,
          size: matrixSize,
        ),
        renders['bauhaus|$id|$palette'] as String,
      );
    });

    test('an unrecognised variant name degrades to marble, never throws', () {
      final name = names.first['value'] as String;
      final colors = (palettes.first['value'] as List).cast<String>();
      expect(
        render(
          BoringAvatarsVariant.fromUpstreamName('nonsense'),
          name,
          colors,
          size: matrixSize,
        ),
        renders['marble|${names.first['id']}|${palettes.first['id']}']
            as String,
      );
    });

    test('the default variant is marble, as upstream defaults it', () {
      expect(
        normalise(
          boringAvatarSvg(
            name: names.first['value'] as String,
            colors: (palettes.first['value'] as List).cast<String>(),
            size: matrixSize,
            version: BoringAvatarsVersion.v1_6_1,
          ),
        ),
        renders['marble|${names.first['id']}|${palettes.first['id']}']
            as String,
      );
    });

    test('every declared version renders every dispatched variant', () {
      // Today this is one version, so it cannot fail — it is here for the
      // release that adds the second selector value, where a missing dispatch
      // arm would otherwise surface as a runtime throw in a caller's app.
      for (final version in BoringAvatarsVersion.values) {
        for (final variant in BoringAvatarsVariant.values) {
          expect(
            boringAvatarSvg(
              name: 'Clara Barton',
              colors: const ['#92A1C6', '#146A7C'],
              size: 80,
              version: version,
              variant: variant,
            ),
            startsWith('<svg '),
            reason: '$version/$variant',
          );
        }
      }
    });
  });

  group(
    'the empty palette splits by variant, and the split is upstream\'s',
    () {
      // hidden-state #8 and ruling S-2, asserted at the public seam rather than
      // at the builder: this is the surface a caller actually meets.
      test('beam refuses and names the palette', () {
        expect(
          () => boringAvatarSvg(
            name: 'Clara Barton',
            colors: const [],
            size: 80,
            version: BoringAvatarsVersion.v1_6_1,
            variant: BoringAvatarsVariant.beam,
          ),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'colors')),
        );
      });

      test('the other five render, and a one-colour palette never refuses', () {
        for (final variant in BoringAvatarsVariant.renderable) {
          if (variant == BoringAvatarsVariant.beam) continue;
          expect(
            render(variant, 'Clara Barton', const []),
            startsWith('<svg '),
            reason: '$variant',
          );
        }
        for (final variant in BoringAvatarsVariant.renderable) {
          expect(
            render(variant, 'Clara Barton', const ['#92A1C6']),
            startsWith('<svg '),
            reason: '$variant with one colour',
          );
        }
      });
    },
  );
}
