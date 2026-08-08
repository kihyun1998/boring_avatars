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
  final sizePassthroughStrings =
      svgFixture['sizePassthroughStrings'] as Map<String, dynamic>;
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
      // `compared` increments in both branches, so it can only catch a loop
      // that ran short — not a section covering five variants. The key sweep
      // below is what answers that, and `dispatched[parts[0]]!` cannot: it
      // throws on an *unknown* prefix and says nothing about a missing one.
      expect(compared, squareRenders.length);
      expect(squareRenders, hasLength(60));
      expect(
        squareRenders.keys.map((k) => k.split('|').first).toSet(),
        dispatched.keys.toSet(),
        reason: 'every variant, not a subset',
      );
    });
  });

  group('size is injected policy and reaches nothing but width/height', () {
    test('every variant × name × square, at both sizes, against upstream', () {
      // **Two axes, and the second one took two passes to earn.** The section
      // covered `marble` alone until #59, so hardcoding `size: 80` on any of
      // the other five arms passed all 677 tests. Widening it per variant
      // closed that and left the next one open, which the completeness pass
      // then measured: with one name and `square: false`, an arm honouring
      // `size` only for `Clara Barton` — or dropping it whenever `square` is
      // set — was *still* invisible. Both of those now go red.
      //
      // The rule underneath, twice over: a prop is not covered because it
      // varies somewhere, it is covered where it varies on a path something
      // else varies on too.
      final palette = (palettes.first['value'] as List).cast<String>();
      var compared = 0;
      for (final variant in BoringAvatarsVariant.renderable) {
        for (final id in <String>['upstream-default', 'empty']) {
          final name =
              names.firstWhere((n) => n['id'] == id)['value'] as String;
          for (final size in sizes) {
            for (final square in <bool>[false, true]) {
              final key =
                  '${variant.upstreamName}|$id|$size|${square ? 'sq' : 'rd'}';
              expect(
                render(variant, name, palette, size: size, square: square),
                sizePassthrough[key] as String,
                reason: key,
              );
              compared++;
            }
          }
        }
      }
      expect(
        compared,
        BoringAvatarsVariant.renderable.length * 2 * sizes.length * 2,
        reason: 'a slice that matched nothing would pass the loop above',
      );
      expect(sizePassthrough, hasLength(compared));
    });

    test('a string size passes through verbatim, on every variant', () {
      // The other half of the public parameter's type. Until #59's
      // completeness pass this was a *throwaway probe* — run once, deleted —
      // plus a comparison of the package against its own 80-render, on
      // `marble` alone. Both halves of that are things this repo has written
      // rules against: a claim whose evidence cannot be re-run, and a fixture
      // that agrees with itself.
      //
      // `a"b` is here because an unrecognised attribute value still goes
      // through React's escaping: upstream writes `width="a&quot;b"`, so this
      // is the case where passthrough and serialisation meet.
      var compared = 0;
      for (final entry in sizePassthroughStrings.entries) {
        final parts = entry.key.split('|');
        final variant = dispatched[parts[0]]!;
        expect(
          render(
            variant,
            names.first['value'] as String,
            (palettes.first['value'] as List).cast<String>(),
            size: parts.sublist(1).join('|'),
          ),
          entry.value as String,
          reason: entry.key,
        );
        compared++;
      }
      expect(compared, sizePassthroughStrings.length);
      expect(
        sizePassthroughStrings.keys.map((k) => k.split('|').first).toSet(),
        dispatched.keys.toSet(),
        reason: 'every variant, not a subset',
      );
    });

    test('anything that is not a number or a string is rejected', () {
      // The scene's own guard is an `assert`, which is stripped in release —
      // so the seam a caller reaches has to reject rather than mis-serialise.
      //
      // **`.name`, not just the type.** A bare `isA<ArgumentError>()` is
      // satisfied by any rejection this function makes, including `beam`'s
      // palette refusal three groups below — so it cannot tell a guard that
      // names the wrong argument from one that names the right one. Measured:
      // changing `'size'` to `'colors'` here survived the whole suite.
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
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'size')),
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
