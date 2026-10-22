# Selector coverage copies

## The fact
Which upstream releases each selector covers is **one fact**. `CLAUDE.md`
principle 3's table is its declared single source. The fact is nevertheless
held in several artifacts, and each one must name the same releases per
selector:

| Copy | What keeps it in line |
|---|---|
| `CLAUDE.md` principle 3 table | the source |
| `BoringAvatarsVersion.upstreamVersions` (`lib/src/version.dart`) and its doc-comments | `api_surface_test.dart` pins the literal lists. **Nothing compares them to `CLAUDE.md`.** |
| README's selector table | `release_metadata_test.dart`, which checks only that every `upstreamVersions` entry and selector name *appears* in README |
| GitHub milestone descriptions | `tool/milestones/sync.mjs` renders them from `CLAUDE.md`; drift is reported when it is run |
| `tool/parity/dump.mjs`'s per-selector map and `tool/parity/package.json`'s installs | `fixtures_test.dart` asserts the fixture claims `containsAll(upstreamVersions)` |
| `tool/versions/package.json` and `group.mjs`'s `VERSIONS` (every in-scope release, plus 1.11.0) | none. It is the measurement, not a claim |
| `tool/crosscheck/crosscheck.mjs`'s `UPSTREAM_FOR` (which release each selector is compared against) | it throws on an unmapped selector, which catches a new selector but not a changed grouping |
| `test/widget_test.dart`'s mapping of `-second-index` golden keys to `v1_10_1` | none |
| `docs/fidelity.md` prose | none (the Step 6 sweep) |

## Why it is cross-cutting
`tool/milestones` reads `CLAUDE.md`, and the tests read `version.dart`. Nothing
reads both. The two sources a person edits, `CLAUDE.md` and `version.dart`,
therefore have no gate between them, and each downstream copy hangs off one of
the two. A new upstream release that joins an existing selector touches every
row above. Missing one gives a selector that claims a release in one place and
not in another.

## Territories it holds in
- [version-selectors](../territory/version-selectors.md) — `upstreamVersions`
- [release-and-publishing](../territory/release-and-publishing.md) — README table, CHANGELOG, `release_metadata_test.dart`
- [milestones-sync](../territory/milestones-sync.md) — renders from `CLAUDE.md`
- [parity-harness](../territory/parity-harness.md) — per-selector installs and the fixture claim
- [version-grouping](../territory/version-grouping.md) — the measurement behind the grouping
- [crosscheck](../territory/crosscheck.md) — `UPSTREAM_FOR`
- [public-svg-surface](../territory/public-svg-surface.md) — the selector a caller names is this mapping's key
- [pixel](../territory/pixel.md) — the one variant whose drawing differs between selectors, so the mapping decides which picture it is
- [widget-lifecycle](../territory/widget-lifecycle.md) — `widget_test.dart`'s hand-written golden-key mapping

## What a violation looks like
A pub.dev reader, a GitHub milestone and `CLAUDE.md` give three different
answers to "does `v1_10_1` cover 2.0.4?". The case the tests catch is a README
that omits a release `upstreamVersions` names. The case nothing catches is
`CLAUDE.md` and `version.dart` disagreeing.

## Discovery history
- #42 added `release_metadata_test.dart` after the Step 6 sweep had already
  missed a README update (S-4, 2026-08-08). It deliberately checks presence, not
  table structure (the test's header says why).
- `tool/milestones/sync.mjs` exists because a milestone description has to carry
  the list itself. "See CLAUDE.md" is useless to someone browsing GitHub, so
  the mapping lives in two surfaces whether or not anyone wants it to
  (theflow.md Step 7 @ 0593e28).
- A README written with a range (`2.0.0 – 2.0.4`) read fine and failed the
  presence test, which is how the "every version by name, never a range" rule
  for README was learned.

## Where it will recur
Every new upstream release. The upstream watcher
([upstream-watch](../territory/upstream-watch.md)) files the issue. Whoever
works it either adds the release to an existing selector, which edits every
row of the table above, or adds a selector, which adds a new value everywhere
and a new arm in [version-selectors](../territory/version-selectors.md)'s
`_Drawing`.
