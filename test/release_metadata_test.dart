import 'dart:io';

import 'package:boring_avatars/boring_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two release facts that can drift silently, and nothing else.
///
/// **Why this file is deliberately small.** The obvious version of it parses
/// README's tables and compares them to the enum — and then goes red when
/// somebody rewords a sentence, which is the failure mode that gets a test
/// weakened or deleted along with whatever it was protecting. So neither check
/// here reads prose: one compares two exact strings, the other asks only
/// whether a version *appears* in the document at all. Reword freely; move the
/// table; both still hold.
///
/// **What it does not cover, on purpose.** That README's prose is *accurate* —
/// that its divergence section still matches the ledger, that its claims are
/// still true — is the Step 6 sweep's job, not a test's. #42 added this file
/// precisely because that sweep had already missed one (S-4 landed in the
/// ledger on 2026-08-08 and README still said "exactly one exception"), but
/// counting rows in a markdown table to catch the next one buys a brittle
/// parser for a check a human has to make anyway.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final readme = File('README.md').readAsStringSync();

  group('the published version is one fact, not two', () {
    test('pubspec version and the newest CHANGELOG heading agree', () {
      final declared = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      final released = RegExp(
        r'^##\s+(\S+)\s*$',
        multiLine: true,
      ).firstMatch(changelog)?.group(1);

      // Both `null`s would compare equal and pass, so a regex that stopped
      // matching would take this check with it silently.
      expect(declared, isNotNull, reason: 'pubspec.yaml declares no version');
      expect(
        released,
        isNotNull,
        reason: 'CHANGELOG.md opens with no `## <version>` heading',
      );

      expect(
        declared,
        released,
        reason:
            'pubspec.yaml says $declared, CHANGELOG.md says $released — '
            'pub.dev snapshots the changelog at publish, so a mismatch ships',
      );
    });
  });

  group('README names every upstream release this package claims', () {
    test('each supported upstream version appears in the document', () {
      final claimed = [
        for (final v in BoringAvatarsVersion.values) ...v.upstreamVersions,
      ];

      // An empty list makes the loop below vacuous, and a vacuous loop is a
      // green that asserts nothing.
      expect(claimed, isNotEmpty);

      for (final version in claimed) {
        expect(
          readme.contains(version),
          isTrue,
          reason:
              'README.md never mentions upstream $version, which '
              'BoringAvatarsVersion claims to reproduce',
        );
      }
    });

    test('the selector names are there too, so the list is reachable', () {
      // The versions alone can be satisfied by a sentence that lists tags
      // without saying which selector value yields them — which is the half a
      // caller actually needs.
      for (final v in BoringAvatarsVersion.values) {
        expect(
          readme.contains(v.name),
          isTrue,
          reason: 'README.md never mentions the selector ${v.name}',
        );
      }
    });
  });
}
