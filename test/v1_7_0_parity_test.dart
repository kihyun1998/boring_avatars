import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// `v1_7_0` against what upstream 1.7.0 actually rendered.
///
/// The sibling `avatar_svg_test.dart` does this for `v1_6_1`. This file is not
/// a copy of it with one identifier changed: the two selectors are asked
/// different questions, because 1.7.0 added a prop and the fixture has two
/// sides where `v1_6_1`'s has one.
///
/// * `renders` — the full 6 × 20 × 5 matrix at upstream's **defaults**, which
///   from 1.7.0 means `title` off. That is what a caller who does not mention
///   the argument must get.
/// * `titleRenders` — every variant × every name with `title: true`. Without
///   it, a port that ignored the argument entirely would pass this whole file.
///
/// **What a full revert would survive: nothing.** Emitting the title when it
/// should be absent breaks the matrix; omitting it when asked breaks
/// `titleRenders`; emitting it in the wrong place breaks both, since these are
/// byte comparisons and not `contains` checks.
void main() {
  final corpus =
      jsonDecode(File('test/fixtures/corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final names = (corpus['names'] as List).cast<Map<String, dynamic>>();
  final palettes = (corpus['palettes'] as List).cast<Map<String, dynamic>>();

  final fixture =
      jsonDecode(File('test/fixtures/v1_7_0/svg.json').readAsStringSync())
          as Map<String, dynamic>;
  final renders = fixture['renders'] as Map<String, dynamic>;
  final titleRenders = fixture['titleRenders'] as Map<String, dynamic>;
  final squareRenders = fixture['squareRenders'] as Map<String, dynamic>;
  final matrixSize = fixture['matrixSize'] as int;

  /// Generated ids are internal references, erased on **both** sides — the same
  /// three rules every sibling parity test uses. At 1.7.0 there is in fact
  /// nothing generated to erase (every id is still a literal in the JSX); the
  /// normalisation is kept identical to the siblings' so that a difference
  /// between this file and them can only ever come from the port.
  String normalise(String svg) => svg
      .replaceAll(RegExp('id="[^"]*"'), 'id="_"')
      .replaceAll(RegExp(r'url\(#[^)]*\)'), 'url(#_)')
      .replaceAll(RegExp('mask="[^"]*"'), 'mask="_"');

  final dispatched = {
    for (final v in BoringAvatarsVariant.renderable) v.upstreamName: v,
  };

  String render(
    BoringAvatarsVariant variant,
    String name,
    List<String> colors, {
    Object size = 80,
    bool square = false,
    bool? title,
  }) => normalise(
    boringAvatarSvg(
      name: name,
      colors: colors,
      size: size,
      version: BoringAvatarsVersion.v1_7_0,
      variant: variant,
      square: square,
      title: title,
    ),
  );

  group('upstream defaults — the title is off and nobody asked', () {
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
              // `beam` × the empty palette — upstream produces no document at
              // all (hidden-state #8, ruling S-2), and 1.7.0 does not change
              // that. The throw is the comparison.
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
        // A sweep that silently matched nothing would pass without this.
        expect(
          compared + refused,
          names.length * palettes.length,
          reason: 'the sweep covered every name and palette, not a subset',
        );
      });
    }
  });

  group('title: true — the prop upstream added here', () {
    final palette = (palettes.first['value'] as List).cast<String>();

    for (final entry in dispatched.entries) {
      test('${entry.key} — every corpus name', () {
        var compared = 0;
        for (final n in names) {
          final expected = titleRenders['${entry.key}|${n['id']}'];
          final name = n['value'] as String;

          if (expected is Map) {
            expect(expected['__throws'], 'TypeError');
            expect(
              () => render(
                entry.value,
                name,
                palette,
                size: matrixSize,
                title: true,
              ),
              throwsA(isA<ArgumentError>()),
              reason: '${entry.key}/${n['id']}',
            );
            compared++;
            continue;
          }

          expect(
            render(entry.value, name, palette, size: matrixSize, title: true),
            expected as String,
            reason: '${entry.key}/${n['id']}',
          );
          compared++;
        }
        expect(compared, names.length);
      });
    }

    test(
      'the fixture really does carry titles, or this group proves nothing',
      () {
        // The group above compares strings. If the fixture happened to hold
        // title-less documents, every comparison would still pass and the prop
        // would be untested — the "golden that agrees with itself" trap wearing
        // upstream's clothes.
        final titled = titleRenders.values.whereType<String>();
        expect(titled, isNotEmpty);
        expect(
          titled.where((s) => s.contains('<title>')),
          hasLength(titled.length),
        );
      },
    );
  });

  group('square still reaches exactly one attribute', () {
    for (final entry in dispatched.entries) {
      test('${entry.key} — the two square names', () {
        var compared = 0;
        for (final key in squareRenders.keys.where(
          (k) => k.startsWith('${entry.key}|'),
        )) {
          final parts = key.split('|');
          final n = names.firstWhere((n) => n['id'] == parts[1]);
          final p = palettes.firstWhere((p) => p['id'] == parts[2]);
          final expected = squareRenders[key];
          final colors = (p['value'] as List).cast<String>();

          if (expected is Map) {
            expect(
              () => render(
                entry.value,
                n['value'] as String,
                colors,
                size: matrixSize,
                square: true,
              ),
              throwsA(isA<ArgumentError>()),
              reason: key,
            );
            compared++;
            continue;
          }

          expect(
            render(
              entry.value,
              n['value'] as String,
              colors,
              size: matrixSize,
              square: true,
            ),
            expected as String,
            reason: key,
          );
          compared++;
        }
        expect(
          compared,
          greaterThan(0),
          reason: 'no square renders for ${entry.key}',
        );
      });
    }
  });

  group('the group this selector claims', () {
    test('four upstream releases, and the fixture measured all four', () {
      // The selector's own claim, checked against the harness's record rather
      // than against a sentence in a ticket. `fixtures_test.dart` proves the
      // record is a clean sweep; this proves the record is about *these* four.
      expect(BoringAvatarsVersion.v1_7_0.upstreamVersions, [
        '1.7.0',
        '1.8.0',
        '1.9.0',
        '1.10.0',
      ]);
      final proof = fixture['groupProof'] as Map<String, dynamic>;
      expect(proof['renderedFrom'], '1.7.0');
      expect(
        (proof['rendered'] as Map<String, dynamic>)['1.10.0'],
        isNotNull,
        reason: '1.10.0 is renderable and has to be compared, not assumed',
      );
      // 1.8.0 and 1.9.0 shipped npm tarballs containing no JavaScript, so the
      // only evidence they can ever have is that their source is 1.10.0's.
      final trees = (proof['bySourceTree'] as Map<String, dynamic>);
      expect(trees.keys, containsAll(['1.8.0', '1.9.0', '1.10.0']));
      expect(trees.values.toSet(), hasLength(1));
    });

    test(
      'the mask id really does differ, and normalisation is why we may ignore it',
      () {
        // The one thing that is *not* byte-identical across the group, recorded
        // unnormalised so the exclusion is visible rather than implied. A future
        // reader who wonders whether "byte-identical" was doing quiet work here
        // gets the answer from the fixture instead of from a comment.
        final raw =
            (fixture['groupProof'] as Map<String, dynamic>)['rawIdSamples']
                as Map<String, dynamic>;
        expect(raw['1.7.0'], 'mask__marble');
        expect(raw['1.10.0'], startsWith(':R'));
        expect(raw['1.7.0'], isNot(raw['1.10.0']));
      },
    );

    test('from 1.8.0 there is no such thing as "the" bytes for an avatar', () {
      // The measurement that decides what reproducing 1.8.0 could even mean.
      // `useId()` is the component's **path in the render tree**, so the same
      // name, palette and variant come out differently depending on what sits
      // beside them — and two of the same avatar in one document get two
      // different ids. A byte sequence that *is* 1.8.0's output for an avatar
      // therefore does not exist, and no implementation could emit one.
      final positions =
          (fixture['groupProof'] as Map<String, dynamic>)['idPositions']
              as Map<String, dynamic>;

      final stable = (positions['1.7.0'] as Map<String, dynamic>).values
          .expand((v) => (v as List).cast<String>())
          .toSet();
      expect(stable, {
        'mask__marble',
      }, reason: '1.7.0 writes a literal, so position cannot move it');

      final generated = positions['1.10.0'] as Map<String, dynamic>;
      String at(String key) => (generated[key] as List).first as String;
      expect(at('alone'), isNot(at('thirdChild')));
      expect(at('alone'), isNot(at('afterSpan')));
      // The decisive one: one document, two identical avatars, two ids.
      final twice = (generated['twiceInOneDocument'] as List).cast<String>();
      expect(twice, hasLength(2));
      expect(twice.first, isNot(twice.last));
    });
  });
}
