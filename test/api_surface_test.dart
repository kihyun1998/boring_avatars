import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoringAvatarsVersion', () {
    test('declares the 17 distinct upstream algorithm states', () {
      expect(BoringAvatarsVersion.values, hasLength(17));
    });

    test(
      'covers every upstream release from 1.2.0 with no gaps or repeats',
      () {
        final covered = <String>[
          for (final v in BoringAvatarsVersion.values) ...v.upstreamVersions,
        ];
        expect(
          covered.toSet(),
          hasLength(covered.length),
          reason: 'an upstream version is claimed by two states',
        );
        expect(
          covered,
          containsAll(<String>[
            '1.2.0',
            '1.3.0',
            '1.3.1',
            '1.4.0',
            '1.4.1',
            '1.4.2',
            '1.5.3',
            '1.5.4',
            '1.5.5',
            '1.5.6',
            '1.5.7',
            '1.5.8',
            '1.6.0',
            '1.6.1',
            '1.6.2',
            '1.6.3',
            '1.7.0',
            '1.8.0',
            '1.9.0',
            '1.10.0',
            '1.10.1',
            '1.10.2',
            '1.11.0',
            '1.11.1',
            '1.11.2',
            '2.0.0',
            '2.0.1',
            '2.0.2',
            '2.0.3',
            '2.0.4',
          ]),
        );
      },
    );

    test('latest is the 2.0.x state', () {
      expect(BoringAvatarsVersion.latest, BoringAvatarsVersion.v2_0_0);
      expect(BoringAvatarsVersion.latest.upstreamVersions, contains('2.0.4'));
    });

    test('v1.11.1 and v1.11.2 are one state — defaults did not change', () {
      expect(BoringAvatarsVersion.v1_11_1.upstreamVersions, <String>[
        '1.11.1',
        '1.11.2',
      ]);
    });
  });

  group('BoringAvatarsVariant', () {
    test('declares the 11 reachable variants and never turbulence', () {
      expect(BoringAvatarsVariant.values, hasLength(11));
      expect(
        BoringAvatarsVariant.values.map((v) => v.upstreamName),
        isNot(contains('turbulence')),
      );
    });

    test('carries the upstream string, including the reserved word', () {
      expect(BoringAvatarsVariant.abstractStyle.upstreamName, 'abstract');
      expect(BoringAvatarsVariant.marble.upstreamName, 'marble');
    });
  });

  group('variant resolution mirrors upstream avatar.js', () {
    test('v1.2.0 defaults to geometric, every later state to marble', () {
      expect(
        BoringAvatarsVersion.v1_2_0.defaultVariant,
        BoringAvatarsVariant.geometric,
      );
      for (final v in BoringAvatarsVersion.values.skip(1)) {
        expect(v.defaultVariant, BoringAvatarsVariant.marble, reason: '$v');
      }
    });

    test('eye is reachable only at v1.2.0', () {
      expect(
        BoringAvatarsVersion.v1_2_0.reachableVariants,
        contains(BoringAvatarsVariant.eye),
      );
      for (final v in BoringAvatarsVersion.values.skip(1)) {
        expect(
          v.reachableVariants,
          isNot(contains(BoringAvatarsVariant.eye)),
          reason: '$v',
        );
      }
    });

    test('dome is reachable across v1.3.0 and the v1.4.x states only', () {
      const withDome = <BoringAvatarsVersion>{
        BoringAvatarsVersion.v1_3_0,
        BoringAvatarsVersion.v1_4_0,
        BoringAvatarsVersion.v1_4_1,
        BoringAvatarsVersion.v1_4_2,
      };
      for (final v in BoringAvatarsVersion.values) {
        expect(
          v.reachableVariants.contains(BoringAvatarsVariant.dome),
          withDome.contains(v),
          reason: '$v',
        );
      }
    });

    test('geometric means three different things across the eras', () {
      // v1.2.0 — a variant in its own right.
      expect(
        BoringAvatarsVersion.v1_2_0.resolveVariant(
          BoringAvatarsVariant.geometric,
        ),
        BoringAvatarsVariant.geometric,
      );
      // v1.3.0–v1.4.2 — neither dispatched nor aliased, so it falls back.
      expect(
        BoringAvatarsVersion.v1_3_0.resolveVariant(
          BoringAvatarsVariant.geometric,
        ),
        BoringAvatarsVariant.marble,
      );
      expect(
        BoringAvatarsVersion.v1_4_2.resolveVariant(
          BoringAvatarsVariant.geometric,
        ),
        BoringAvatarsVariant.marble,
      );
      // v1.5.3 onward — a deprecated alias for beam.
      expect(
        BoringAvatarsVersion.v1_5_3.resolveVariant(
          BoringAvatarsVariant.geometric,
        ),
        BoringAvatarsVariant.beam,
      );
      expect(
        BoringAvatarsVersion.latest.resolveVariant(
          BoringAvatarsVariant.geometric,
        ),
        BoringAvatarsVariant.beam,
      );
    });

    test('abstract aliases to bauhaus only from v1.5.3', () {
      expect(
        BoringAvatarsVersion.v1_2_0.resolveVariant(
          BoringAvatarsVariant.abstractStyle,
        ),
        BoringAvatarsVariant.abstractStyle,
      );
      expect(
        BoringAvatarsVersion.v1_4_0.resolveVariant(
          BoringAvatarsVariant.abstractStyle,
        ),
        BoringAvatarsVariant.marble,
      );
      expect(
        BoringAvatarsVersion.latest.resolveVariant(
          BoringAvatarsVariant.abstractStyle,
        ),
        BoringAvatarsVariant.bauhaus,
      );
    });

    test('an unreachable variant never throws — it degrades like upstream', () {
      for (final version in BoringAvatarsVersion.values) {
        for (final variant in BoringAvatarsVariant.values) {
          final resolved = version.resolveVariant(variant);
          expect(
            version.reachableVariants,
            contains(resolved),
            reason: '$version.resolveVariant($variant) left the reachable set',
          );
        }
      }
    });

    test(
      'resolution is idempotent — a resolved variant resolves to itself',
      () {
        for (final version in BoringAvatarsVersion.values) {
          for (final variant in BoringAvatarsVariant.values) {
            final once = version.resolveVariant(variant);
            expect(
              version.resolveVariant(once),
              once,
              reason: '$version/$variant',
            );
          }
        }
      },
    );
  });
}
