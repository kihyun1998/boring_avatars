# release-and-publishing

## What it is
How this package is cut into releases, what each release has to earn, which
surfaces describe its behaviour to readers (and so must move with it), what
reaches the pub.dev archive, and what a release obliges downstream consumers to
do. Published versions at 2026-10-22 (`curl -s
https://pub.dev/api/packages/boring_avatars`): `0.1.0` (2026-08-12), `0.2.0`
(08-13), `0.3.0` (08-14), `0.3.1` (08-18), `0.3.2` (08-19), `0.3.3` (09-07).
Query it; do not quote this line.

## Governing decisions
**None.** No ADR. Governed by maintainer rulings recorded as events below
(2026-07-29 ×2, 2026-08-11, 2026-08-13) and by `CLAUDE.md` principle 3, which
is the single home of the release → selector → covered-versions table. Adjacent
ADRs that govern *what ships* but not the release process:
[ADR-0001](../../adr/0001-what-a-colour-declaration-means.md),
[ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md).

## Design model

### One release per output state
**Decided by the maintainer on 2026-07-29**, replacing "one release per upstream
version" (2026-07-28), which replaced "batch everything into 1.0.0". A release
declares support for every upstream version that produces the same thing, and
is cut as soon as that support is verified. The unit is the output state, not
the version number. Both earlier plans are recorded so their reasoning is not
re-proposed.

**Why eight collapsed to three.** The previous plan gave `1.8.0`, `1.10.2`,
`1.11.0` and `1.11.1` releases whose stated work was "verification only" —
they existed so a caller could *name* a pinned version. The maintainer ruled
that a name that buys no different output does not earn a release; five
releases' worth of README, CHANGELOG, fixtures and publish ceremony went with
them. `1.11.0` is excluded outright (see [version-selectors](version-selectors.md)).

**What each release had to do** (the mapping itself is in `CLAUDE.md` only):

| Release | The work that earns it |
|---|---|
| `0.1.0` | everything: harness, primitives, scene, all six variants, the public SVG surface, the rasteriser's arbitrary scale (#58), the `BoringAvatar` widget (#80), the banded rasteriser that keeps it off the frame on both platforms (#80), the example (#78), and the colour vocabulary (#71 → #62 → #63 → #64, plus #95 — maintainer ruling 2026-08-11, same criterion as 2026-08-10: publishing first would put a release that refuses valid colours in people's hands). Rulings: [colour-declarations](colour-declarations.md) (colour into `0.1.0`, 2026-08-10), [widget-lifecycle](widget-lifecycle.md) and [banded-rasterisation](banded-rasterisation.md) (SVG-only reversed 2026-08-09; the widget's execution model; the web half; the asynchronous half shipping unproven) |
| `0.2.0` | the `<title>` gate (hidden-state #16) — one change |
| `0.3.0` | `pixel`'s second colour-index path — one change, the only one in scope where the drawing moves — **plus the full Chrome pixel sweep (#50), run inside this release** |
| `0.3.1` | #110 — the widget's buffer landing whole on the device pixel grid. The first release that adds no selector and moves no byte; `CLAUDE.md`'s table is untouched. A patch earns a row because the release exists, not because it is a state ([pixel-placement](pixel-placement.md)) |

`0.3.2` (#117 — stops claiming an unfiltered draw where one buffer pixel
cannot cover one device pixel; ADR-0002 R5 and R6) and `0.3.3` (documentation only — README split into
`docs/*.md`, gallery images) were cut after theflow's table was last edited;
their content is in `CHANGELOG.md`.

**The Chrome sweep runs inside `0.3.0` — maintainer ruling, 2026-08-13.** #50
counts seven combinations: five variants that draw the same in every state,
`pixel`'s existing colour index, and `pixel`'s **second** — which #45 creates.
Run first, it reaches six, and its own first acceptance criterion says "all
seven". So the sweep is a step in the release, after the code and **before the
documents** — deliberately: #50's acceptance already forbids relaxing a bar
(*"기준 미달 조합이 있으면 게이트 기준을 낮추지 말고 원인을 별도 이슈로
분리"*), and running it before README and CHANGELOG are written means the
pressure to relax never builds. An order that removes a temptation beats a rule
that resists it. Its result: [crosscheck](crosscheck.md), run #45.

**What was actually wrong was the prose, not the graph.** #45's body said it
was blocked by #50 and no such edge existed; #50's only edge was to #48, a
release the plan had deleted when eight collapsed to three. The cycle was
entirely in sentences. #50 became #45's **sub-issue** — the tracker saying
"inside" in the one place that renders it. (theflow also says "Its circular
blocked-by is still unruled and was deliberately not encoded as a dependency
edge" — attributed.)

**Kept from the earlier plan**, and mattering more now:
- **Every release re-proves the additive invariant.** A user pinned to
  `v1_6_1` must not have their avatars move because `0.3.0` touched `pixel`
  ([frozen-selector-output](../invariant/frozen-selector-output.md)).
- **Every covered version is measured; the committed fixture is per output
  state. Decided by the maintainer on 2026-07-29**, superseding "per-version
  fixtures are still generated for every covered version" — wording describing
  something the repo never did (`test/fixtures/` has held one directory per
  state since #33). *"문구까지 지킬 필요는 없고 결과가 중요함"* — the same
  criterion one level up. What they were shown (the 1.6.1/1.6.2/1.6.3
  tree/bundle/render table) is in [version-grouping](version-grouping.md); the
  per-version render and comparison is `tool/versions/group.mjs` and the
  fixture's `groupProof` ([parity-harness](parity-harness.md)). Theirs to
  reverse; collapsing the releases does not license collapsing the evidence —
  the `<title>` divergence was found because 1.6.1 and 1.7.0 were rendered
  separately.

### Behaviour-describing surfaces (the sweep list)
- **`CHANGELOG.md`** — pub.dev snapshots it at publish. Never edit a published
  entry; open a new version. `release_metadata_test.dart` (`'pubspec version
  and the newest CHANGELOG heading agree'`) holds the top heading to
  `pubspec.yaml`'s `version`.
- **`README.md`** — the selector × upstream-versions table. The one part a gate
  holds: `release_metadata_test.dart` asserts that **every** string in every
  selector's `upstreamVersions`, and every selector name, *appears somewhere* in
  the README (`readme.contains`) — it deliberately parses no table and reads no
  prose, so rewording cannot break it. Hence **every version is listed by name,
  never as a range**: a `2.0.0 – 2.0.4` shorthand reads fine and fails the test,
  which is how it was caught.
- **`docs/rendering.md`, `docs/performance.md`, `docs/colors.md`,
  `docs/fidelity.md`** — reader prose split out of the README in `0.3.3`.
  Nothing gates them. A change that moves a byte, a timing or a colour answer
  sweeps these four: `performance.md` holds measured timings (one machine's —
  re-measure, don't adjust), `fidelity.md` the parity counts and the three
  non-reproduced things, `colors.md` the grammar the rasterizer reads,
  including the deliberately-skipped list (scope, not accident).
- **`docs/images/`** — generated, never hand-edited:
  [readme-gallery](readme-gallery.md).
- **Public doc-comments** ship verbatim as the pub.dev API reference; the
  `BoringAvatarsVersion` doc-comments are the only place a user learns which
  upstream tags a selector covers.
- **The divergence ledger** — append the ruling in the change that adjudicates
  it, never in a later sweep: [upstream-divergences](../aggregate/upstream-divergences.md).
- **This map** — a ported state that changes what a note says updates the note
  in the same change.
- **`docs/adr/`** — house format `NNNN-kebab-case-title.md`, sequential.
  **Areas that already carry a record** — checked *before* proposing a spine,
  so a cluster with a home never gets a second one. A **proposed** record
  counts exactly as an accepted one.

  | Record | Status | Area it governs | Conformance items |
  |---|---|---|---|
  | [ADR-0001](../../adr/0001-what-a-colour-declaration-means.md) — what a colour declaration means | Accepted 2026-08-10 (#71) | every colour-valued attribute the rasterizer reads: `fill`, `stroke`, `stop-color`, and any that follow | all done: #69, #62, #63, #64 |
  | [ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md) — when the box and the pixel grid disagree | Accepted 2026-08-18 (#110), amended the same day (#117, R5) | where the widget's buffer lands: grid alignment, containment, tangency, fractional `size × dpr`, and (R5) what is claimed when the drawing cannot land one pixel per pixel | all done: #110, #117 |

  Statuses re-verified against each ADR's `Status:` line at HEAD.
- **Record-worthy promotion.** Two areas were re-litigated and promoted: the
  rasterizer's colour vocabulary (ADR-0001 — a 2-axis grid, property ×
  declaration state, decided one cell at a time across #69 and #64, plus
  hidden-state rows #20 and #44 requiring opposite things in one file), and the
  widget's placement (ADR-0002 — `round` vs `floor` from #110's completeness
  pass; the reference cannot arbitrate it, upstream has no widget layer and
  Flutter records no public API for physical-pixel alignment,
  flutter/flutter#111302; and two artifacts required opposite things). The
  remaining candidate is the JS↔Dart semantics rules, if the hidden-state list
  starts needing a *rule* rather than another row. No project exception to how
  spines link or where write-back lands.
- **`GLOSSARY.md`** — does not exist at HEAD; created lazily.
- **`.pubignore`** — see below. **`example/`** — [example-app](example-app.md).

### What reaches the archive — `.pubignore`
A root `.pubignore` **disables git-based file listing entirely**, so everything
`.gitignore` excludes is repeated (a single `flutter test` once left a 44 MB
`.dill` under `build/` that "0 warnings" shipped — lessons.md #1). Excluded at
HEAD: the `.gitignore` mirror, `docs/`, `.github/`, `tool/`, **all of `test/`**
(fixtures hundreds of KB per state, goldens; a suite shipped without its data
cannot pass), `example/integration_test/`, `example/spike/`, `CLAUDE.md`.
`example/` itself **is** published (pana scores it). Dot-directories are skipped
by pub on its own (measured #42: a planted `.claude/worktrees/probe/junk.txt`
did not ship, a control file did); the dot entries stay so `.pubignore ⊇
.gitignore` is mechanically checkable. **`pub publish --dry-run` reports 0
warnings either way — no gate knows what belongs in an archive; read the file
list.** The archive cannot be un-published.

### Publishing
- `flutter pub publish` is irreversible (retract only) — **the agent does not
  run it; the maintainer does.**
- **Publish state is queried, not assumed**: `curl -s
  https://pub.dev/api/packages/boring_avatars`; score: `…/score` (`0/0` with
  only `is:recent` means "not yet scored", not "scored zero").
- Milestones mirror `CLAUDE.md`'s table: [milestones-sync](milestones-sync.md).

### Downstream loop
**Live since `0.1.0` (2026-08-12).** Derive consumers on the spot and **never
store the list** — a stored list is a derivable fact that rots:

```bash
for d in ../*/; do grep -l 'boring_avatars:' "$d/pubspec.yaml"; done
```

Run at `0.1.0`, `0.2.0` (attributed) and on 2026-10-22 (this note): no sibling
consumers. Not a standing answer — re-derive.

- **Releases oblige consumers to nothing, structurally**: a new upstream state
  is a new selector value, never an edit to a shipped one, so there is no
  constraint to raise, workaround to delete or pinned-bug test to flip. Say so
  explicitly in each release — "nothing to do" and "nobody checked" look
  identical from outside.
- **`0.2.0` was the first time the loop had a sentence to write**:
  `BoringAvatarsVersion.latest` moved `v1_6_1` → `v1_7_0`, so a consumer passing
  `latest` who relied on `<title>` lost it. That is what passing `latest`
  means, it is in the changelog, and it obliges the consumer to decide. (`latest`
  is `v1_10_1` at HEAD.)
- **`environment: sdk: ^3.11.5` is a published floor.** Raising it is a
  breaking change for every dependent, carried down by the caret range whether
  or not anyone thinks of it as an API change. The one thing that *would*
  oblige consumers. `pubspec.yaml` deliberately has **no `flutter:`
  constraint**: the newest Flutter API used, `MediaQuery.devicePixelRatioOf`,
  shipped in 3.10.0, far below what carries Dart 3.11.5 — re-checked at #110 and
  #117 (comment in `pubspec.yaml`).
- **The two-consumer signal cannot be seen from inside one consumer** — the
  duty to report a local guard upstream applies even when the local fix was
  correct.

## Code
- `pubspec.yaml` — `version`, `environment.sdk`
- `CHANGELOG.md` — one `## <version>` heading per release
- `.pubignore`
- `test/release_metadata_test.dart` — groups `'the published version is one
  fact, not two'`, `'README names every upstream release this package claims'`
- `lib/src/version.dart` — `BoringAvatarsVersion.upstreamVersions`, `latest`
- `README.md`, `docs/{rendering,performance,colors,fidelity}.md`, `docs/adr/`

## Reference behaviour
- pub.dev API (`/api/packages/boring_avatars`, `/score`) — the authority on
  what is published and how it scored.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the reason
  releases are additive and the downstream loop is structurally empty.
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) — the
  README table, the doc-comments and `CLAUDE.md`'s table are copies a release
  must move together; only the README half is gated.
- [sunset-url-character-list](../invariant/sunset-url-character-list.md) — README and `docs/fidelity.md` restate the list (without `%`).

## Blast radius
- [version-selectors](version-selectors.md) — a new selector is a new release
  row, a README row naming every version, a CHANGELOG entry and a doc-comment.
- [readme-gallery](readme-gallery.md) — the README's images are served from
  `main` on GitHub, not from the archive (see Known holes).
- [milestones-sync](milestones-sync.md) — reads `CLAUDE.md`'s table; a release
  row change owes a sync.
- [gates](gates.md) — `pub publish --dry-run` is the last gate; the CRLF
  restore exists because of it.
- [example-app](example-app.md) — `example/` ships; anything added under it
  ships unless `.pubignore` names it.

## Known holes / open
- **No gate checks archive contents**; `example/integration_test/` shipped by
  default until someone read the list.
- **README images point at `raw.githubusercontent.com/…/main/docs/images/`**,
  so every published version's pub.dev page shows whatever `main` holds today
  — a rasterizer change merged to `main` changes the pictures under
  already-published READMEs.
- `docs/*.md` are ungated prose; their accuracy is a sweep, not a test
  (`release_metadata_test.dart`'s doc says so on purpose).
- theflow's release-plan table stops at `0.3.1`; `0.3.2` and `0.3.3` have no
  "work that earns it" row except their CHANGELOG entries.
- The GitHub milestone `0.3.0` is still **open** although `0.3.0` published on
  2026-08-14 (measured 2026-10-22 via `tool/milestones/sync.mjs`); no milestones
  exist for `0.3.1`–`0.3.3`.
