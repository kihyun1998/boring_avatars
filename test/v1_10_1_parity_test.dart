import 'dart:convert';
import 'dart:io';

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// `v1_10_1` against what upstream 1.10.1 actually rendered.
///
/// The selector's one claim beyond `v1_7_0` is a moved colour index in
/// `pixel` — the only drawing change in the whole supported range. So this
/// file is asked two questions the siblings are not:
///
/// * the **fixture sweep** proves the new drawing against upstream's own
///   renders, byte for byte;
/// * the **cross-selector group** proves the change is confined to `pixel` —
///   the other five variants must be byte-identical to `v1_7_0` for the same
///   arguments, or the release changed more than it claims.
void main() {
  final corpus =
      jsonDecode(File('test/fixtures/corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final names = (corpus['names'] as List).cast<Map<String, dynamic>>();
  final palettes = (corpus['palettes'] as List).cast<Map<String, dynamic>>();

  /// Generated ids are internal references, erased on **both** sides — the
  /// same three rules every sibling parity test uses. From 1.10.1 every mask
  /// id is React's `useId()`, so the erasure is load-bearing here the way it
  /// already is for `v1_7_0`'s 1.8.0–1.10.0 half.
  String normalise(String svg) => svg
      .replaceAll(RegExp('id="[^"]*"'), 'id="_"')
      .replaceAll(RegExp(r'url\(#[^)]*\)'), 'url(#_)')
      .replaceAll(RegExp('mask="[^"]*"'), 'mask="_"');

  String render(
    BoringAvatarsVersion version,
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
      version: version,
      variant: variant,
      square: square,
      title: title,
    ),
  );

  const defaultPalette = [
    '#92A1C6',
    '#146A7C',
    '#F0AB3D',
    '#C271B4',
    '#C20D90',
  ];

  final fixture =
      jsonDecode(File('test/fixtures/v1_10_1/svg.json').readAsStringSync())
          as Map<String, dynamic>;
  final renders = fixture['renders'] as Map<String, dynamic>;
  final titleRenders = fixture['titleRenders'] as Map<String, dynamic>;
  final squareRenders = fixture['squareRenders'] as Map<String, dynamic>;
  final matrixSize = fixture['matrixSize'] as int;

  final dispatched = {
    for (final v in BoringAvatarsVariant.renderable) v.upstreamName: v,
  };

  group('upstream defaults — the full matrix, title off', () {
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
              // `beam` × the empty palette — upstream produces no document
              // (hidden-state #8, ruling S-2), and 1.10.1 does not change it.
              expect(expected['__throws'], 'TypeError');
              expect(
                () => render(
                  BoringAvatarsVersion.v1_10_1,
                  entry.value,
                  name,
                  colors,
                  size: matrixSize,
                ),
                throwsA(isA<ArgumentError>()),
                reason: '${entry.key}/${n['id']}/${p['id']}',
              );
              refused++;
              continue;
            }

            expect(
              render(
                BoringAvatarsVersion.v1_10_1,
                entry.value,
                name,
                colors,
                size: matrixSize,
              ),
              expected as String,
              reason: '${entry.key}/${n['id']}/${p['id']}',
            );
            compared++;
          }
        }
        expect(
          compared + refused,
          names.length * palettes.length,
          reason: 'the sweep covered every name and palette, not a subset',
        );
      });
    }
  });

  group('title: true — the other side of the prop', () {
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
                BoringAvatarsVersion.v1_10_1,
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
            render(
              BoringAvatarsVersion.v1_10_1,
              entry.value,
              name,
              palette,
              size: matrixSize,
              title: true,
            ),
            expected as String,
            reason: '${entry.key}/${n['id']}',
          );
          compared++;
        }
        expect(compared, names.length);
      });
    }
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
                BoringAvatarsVersion.v1_10_1,
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
              BoringAvatarsVersion.v1_10_1,
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
        // Two names × five palettes, exactly — `greaterThan(0)` would let a
        // partially regenerated fixture shrink the coverage in silence (the
        // #45 refuting lens's observation).
        expect(compared, 10, reason: 'square coverage for ${entry.key}');
      });
    }
  });

  group('the group this selector claims', () {
    test('nine upstream releases, every one measured by rendering', () {
      expect(BoringAvatarsVersion.v1_10_1.upstreamVersions, [
        '1.10.1',
        '1.10.2',
        '1.11.1',
        '1.11.2',
        '2.0.0',
        '2.0.1',
        '2.0.2',
        '2.0.3',
        '2.0.4',
      ]);
      final proof = fixture['groupProof'] as Map<String, dynamic>;
      expect(proof['renderedFrom'], '1.10.1');
      final rendered = proof['rendered'] as Map<String, dynamic>;
      // No `bySourceTree` half here on purpose: unlike 1.8.0/1.9.0, every
      // release in this group ships runnable JavaScript, so every one of the
      // other eight carries the strong kind of evidence — a full-matrix render
      // compared to 1.10.1's. The nine source trees are *not* one tree (the
      // destructuring rework and the TypeScript rewrite are real diffs), which
      // is exactly why the grouping criterion is output and not source.
      expect(
        rendered.keys.toSet(),
        BoringAvatarsVersion.v1_10_1.upstreamVersions.skip(1).toSet(),
      );
      for (final e in rendered.entries) {
        final row = e.value as Map<String, dynamic>;
        expect(row['mismatches'], isEmpty, reason: e.key);
        // variant × name × palette × title × square — the last axis added by
        // the #45 completeness pass. Until then sibling equivalence under
        // `square` was read off the components' unchanged text, not rendered
        // (the #59 lesson's shape, inherited from the v1_7_0 precedent).
        expect(row['compared'], 2400, reason: e.key);
      }
    });

    test('2.0.3 and 2.0.4 are covered from npm, not from a tag', () {
      // Upstream's tags stop at v2.0.2 while npm's latest is 2.0.4 — the
      // fact #45 and the watcher's rationale both record. The fixture proves
      // the two tag-less releases were still resolved to upstream's own
      // history: npm records the commit each was published from, and both
      // commits resolve in the reference tree to one `src/lib` — measured,
      // `master`'s tree at generation time.
      final provenance =
          (fixture['groupProof'] as Map<String, dynamic>)['npmProvenance']
              as Map<String, dynamic>;
      final tagless = ['2.0.3', '2.0.4'];
      for (final release in tagless) {
        final row = provenance[release] as Map<String, dynamic>;
        expect(row['tagCommit'], isNull, reason: '$release has no git tag');
        expect(row['tagTree'], isNull, reason: release);
        expect(
          row['npmHeadTree'],
          isNotNull,
          reason: '$release\'s gitHead must resolve in upstream history',
        );
      }
      // One source tree for both — 2.0.4 is a version bump, not a code change.
      expect(
        (provenance['2.0.3'] as Map<String, dynamic>)['npmHeadTree'],
        (provenance['2.0.4'] as Map<String, dynamic>)['npmHeadTree'],
      );
      // **The tag-less set is exactly these two, pinned.** The generic gate
      // in `fixtures_test.dart` classifies a row as tag-less by `tagTree ==
      // null`, which is also what a reference checkout missing its tags
      // would produce — regenerating there would silently demote all seven
      // tagged releases to the weaker evidence class. Found by the #45
      // completeness pass; this is the assertion that catches it.
      for (final release in BoringAvatarsVersion.v1_10_1.upstreamVersions) {
        final row = provenance[release] as Map<String, dynamic>;
        if (tagless.contains(release)) continue;
        expect(
          row['tagTree'],
          isNotNull,
          reason:
              '$release is tagged upstream — a null tagTree means the '
              'reference tree lost its tags, not that the evidence class '
              'changed',
        );
        expect(row['npmHeadTree'], row['tagTree'], reason: release);
      }
    });

    test(
      'every mask id in this group is generated — no release writes one',
      () {
        // At v1_7_0 the ruling was "emit 1.7.0's literal at every position",
        // because 1.7.0 wrote literals and the useId releases have no fixed
        // bytes to reproduce. Here every covered release's **mask** id is
        // `useId()` (rawIdSamples: nine `:R0:`s), so the same ruling covers the
        // whole group and the literal this package emits is the pre-useId one.
        final proof = fixture['groupProof'] as Map<String, dynamic>;
        final raw = (proof['rawIdSamples'] as Map<String, dynamic>);
        expect(raw, hasLength(9));
        for (final e in raw.entries) {
          expect(e.value as String, startsWith(':R'), reason: e.key);
        }
        // The measurement that makes "reproduce the bytes" impossible even for
        // upstream itself: the same avatar's id depends on its render position,
        // and two copies in one document get two different ids.
        final positions =
            (proof['idPositions'] as Map<String, dynamic>)['1.10.1']
                as Map<String, dynamic>;
        String at(String key) => (positions[key] as List).first as String;
        expect(at('alone'), isNot(at('thirdChild')));
        final twice = (positions['twiceInOneDocument'] as List).cast<String>();
        expect(twice, hasLength(2));
        expect(twice.first, isNot(twice.last));
      },
    );

    test('marble\'s filter id is the one literal left in the group', () {
      // Scoped deliberately: the sentence above is about mask ids. Marble's
      // filter id is still the literal `prefix__filter0_f` at 1.10.1 — the
      // release this fixture renders from — and `filter_${useId}` from
      // 1.10.2 onward. The port emits 1.10.1's literal; for the other eight
      // releases that is the same unreproducibility as the mask id, covered
      // by the same ruling, and this is the committed witness that the
      // divergence exists (the byte sweep normalises it away on both sides).
      final raw =
          (fixture['groupProof'] as Map<String, dynamic>)['rawFilterIdSamples']
              as Map<String, dynamic>;
      expect(raw, hasLength(9));
      expect(raw['1.10.1'], 'prefix__filter0_f');
      for (final e in raw.entries.where((e) => e.key != '1.10.1')) {
        expect(e.value as String, startsWith('filter_:R'), reason: e.key);
      }
    });

    test('the raw literals this port emits on the v1_10_1 path', () {
      // Every byte gate above normalises `id="…"`, `url(#…)` and `mask="…"`
      // away, the golden is id-blind, and `buildPixelScene` is the one
      // builder that receives version information — so until this test, a
      // port that renamed its ids *only for the new selector* passed the
      // whole suite (measured by the #45 refuting lens: a colourIndex-
      // conditional mask id + reference survived everything). The literals
      // are the pre-useId ones, per the #43 ruling extended to this group.
      final pixel = boringAvatarSvg(
        name: 'Clara Barton',
        colors: defaultPalette,
        size: 80,
        version: BoringAvatarsVersion.v1_10_1,
        variant: BoringAvatarsVariant.pixel,
      );
      expect(pixel, contains('<mask id="mask__pixel"'));
      expect(pixel, contains('mask="url(#mask__pixel)"'));

      final marble = boringAvatarSvg(
        name: 'Clara Barton',
        colors: defaultPalette,
        size: 80,
        version: BoringAvatarsVersion.v1_10_1,
        variant: BoringAvatarsVariant.marble,
      );
      expect(marble, contains('<filter id="prefix__filter0_f"'));
      expect(marble, contains('filter="url(#prefix__filter0_f)"'));
      expect(marble, contains('<mask id="mask__marble"'));
    });
  });

  group('the change is confined to pixel', () {
    final unchanged = [
      BoringAvatarsVariant.marble,
      BoringAvatarsVariant.beam,
      BoringAvatarsVariant.sunset,
      BoringAvatarsVariant.ring,
      BoringAvatarsVariant.bauhaus,
    ];

    for (final variant in unchanged) {
      test('${variant.name} — byte-identical to v1_7_0 on the full corpus', () {
        var compared = 0;
        for (final n in names) {
          for (final p in palettes) {
            final name = n['value'] as String;
            final colors = (p['value'] as List).cast<String>();
            if (variant == BoringAvatarsVariant.beam && colors.isEmpty) {
              // Both selectors throw here (hidden-state #8, ruling S-2);
              // there is no document on either side to compare.
              compared++;
              continue;
            }
            for (final title in [null, true]) {
              expect(
                render(
                  BoringAvatarsVersion.v1_10_1,
                  variant,
                  name,
                  colors,
                  title: title,
                ),
                render(
                  BoringAvatarsVersion.v1_7_0,
                  variant,
                  name,
                  colors,
                  title: title,
                ),
                reason: '${variant.name}/${n['id']}/${p['id']}/title=$title',
              );
            }
            compared++;
          }
        }
        expect(compared, names.length * palettes.length);
      });
    }

    test('pixel — differs from v1_7_0 on every corpus name', () {
      // The other half of the claim above, and the discriminator for the
      // whole selector: if the drawing switch collapsed the two eras, this
      // group is what goes red. Every name, because the change is per tile
      // and a single name could in principle collide.
      for (final n in names) {
        final name = n['value'] as String;
        expect(
          render(
            BoringAvatarsVersion.v1_10_1,
            BoringAvatarsVariant.pixel,
            name,
            defaultPalette,
          ),
          isNot(
            render(
              BoringAvatarsVersion.v1_7_0,
              BoringAvatarsVariant.pixel,
              name,
              defaultPalette,
            ),
          ),
          reason: n['id'] as String,
        );
      }
    });

    test('pixel — tile 0 is filled with colors[0], measured upstream', () {
      // Through the public seam, not the builder: this is the path a caller
      // takes, and the one the version dispatch has to get right. Upstream
      // 1.10.1 gives Clara Barton's tile 0 `hash % 1 == 0` → colors[0]
      // (probe recorded in #45); the old era leaves the attribute off.
      final svg = boringAvatarSvg(
        name: 'Clara Barton',
        colors: defaultPalette,
        size: 80,
        version: BoringAvatarsVersion.v1_10_1,
        variant: BoringAvatarsVariant.pixel,
      );
      final firstTile = RegExp(
        '<rect width="10" height="10"[^>]*>',
      ).firstMatch(svg)!.group(0)!;
      expect(firstTile, contains('fill="#92A1C6"'));

      final old = boringAvatarSvg(
        name: 'Clara Barton',
        colors: defaultPalette,
        size: 80,
        version: BoringAvatarsVersion.v1_7_0,
        variant: BoringAvatarsVariant.pixel,
      );
      expect(
        RegExp('<rect width="10" height="10"[^>]*>').firstMatch(old)!.group(0),
        isNot(contains('fill=')),
        reason: 'the old era leaves tile 0 unfilled (hidden-state #17)',
      );
    });
  });

  group('title behaves as 1.10.1 does — prop present, defaulting off', () {
    test('no title by default, title when asked', () {
      final silent = render(
        BoringAvatarsVersion.v1_10_1,
        BoringAvatarsVariant.pixel,
        'Clara Barton',
        defaultPalette,
      );
      expect(silent, isNot(contains('<title>')));
      final asked = render(
        BoringAvatarsVersion.v1_10_1,
        BoringAvatarsVariant.pixel,
        'Clara Barton',
        defaultPalette,
        title: true,
      );
      expect(asked, contains('<title>Clara Barton</title>'));
      expect(
        render(
          BoringAvatarsVersion.v1_10_1,
          BoringAvatarsVariant.pixel,
          'Clara Barton',
          defaultPalette,
          title: false,
        ),
        silent,
        reason: 'title: false is the default made explicit, not an error',
      );
    });
  });
}
