# gates

## What it is
The ordered set of local commands that must pass before a change is green, and
the conventions around running them. **There are no CI gates**: these run on
the maintainer's machine, by the agent, and they are the only gates. The one
GitHub Actions workflow is a watcher, not a gate ([upstream-watch](upstream-watch.md)).
Everything heavier — [parity-harness](parity-harness.md),
[crosscheck](crosscheck.md), [calibration](calibration.md), the
[mutation-harness](mutation-harness.md) run, [version-grouping](version-grouping.md),
[milestones-sync](milestones-sync.md), [readme-gallery](readme-gallery.md) —
is a tool, run deliberately; `flutter test` reads only what they committed.

## Governing decisions
**None.** No ADR. House conventions recorded in `CLAUDE.md` (Environment) and
theflow Step 7; the `bare` skill holds the "run every gate bare, never move a
threshold" rule this repo applies.

## Design model
**The gate block, in order:**

```
node tool/mutate/run.mjs --check                    # 0 stale cases; starts no tests
flutter analyze                                     # 0 issues
dart format --output=none --set-exit-if-changed lib test
flutter test                                        # includes fixture + golden gates
cd example && flutter analyze                       # separate package — its own run
flutter pub publish --dry-run                       # 0 warnings, clean tree
```

- **`--check` goes first** because it is the only gate that can fail in
  milliseconds (#107). It answers only "do the cases still point at their
  targets"; a clean result is **not** evidence any mutant dies (#106: two cases
  matched nothing for months under a commit claiming `13/13 mutations
  killed`). Measured 2026-10-22: `115 checked · 0 stale`.
- **`flutter test` is hermetic**: fixtures and goldens are committed; it never
  runs Node, a browser or the network.
- **The `example` line was owed from #78 and added in #43.** `example/` is a
  separate package (own `pubspec.yaml`, path dependency on `../`; the root
  `pubspec.yaml` declares no workspace), so the root `flutter analyze` does not
  cover it. **There is no `example/` suite to add** — `example/test/` does not
  exist at HEAD (a `flutter create` `widget_test.dart` was added in `07afe0c`
  and deleted in `d77c817`, both 2026-08-19). `example/integration_test/` needs
  a real device and is not a gate ([example-app](example-app.md)). Say so
  rather than letting the missing line read as coverage — `flutter_table_plus`
  #55 is the opposite failure: a leftover `flutter create` counter test kept
  that repo's example gate permanently red, which trains everyone to ignore it.
- **Example analyze runs before the dry-run, and the reason is a trap.** On
  Windows, analysing `example/` rewrites its checked-in generated registrants
  with the other line ending — identical content, `git diff` empty but for the
  CRLF warning — and `pub publish --dry-run` then reports "N checked-in files
  are modified in git". Restore **every platform directory `example/` has**,
  not the file the warning named:

  ```
  git checkout -- example/windows/flutter/ example/macos/Flutter/
  ```

  The set grows silently: the note named only `windows/flutter/`'s three files
  until `0.3.3` hit a fourth, `example/macos/Flutter/GeneratedPluginRegistrant.swift`,
  which arrived with macOS support in `07afe0c`. Adding a platform to `example/`
  adds a path here; nothing enforces it, so the failure mode is a dry-run
  warning rather than a red test. Tracked generated files at HEAD:
  `git ls-files example/windows/flutter example/macos/Flutter` (7 files).
- **Run each gate bare, never piped** — a pipeline's exit status is the last
  command's, so `flutter test | tail -1 && commit` always commits.
- **Never lower a threshold to clear a red run.** Tightening is always
  legitimate; loosening is a ruling.

**`pana` — the machine-conditional gate**, deliberately not in the block:
- **Measured 2026-08-11 on macOS**: `pana` 0.23.17 (the version pub.dev scores
  with) runs clean, **160/160** — conventions 30/30, documentation in full, six
  platforms plus WASM-ready, static analysis 50/50, dependencies 40/40 incl. the
  `pub downgrade` lower-bound check. Its one note (two undocumented symbols on
  `BoringAvatar`) was fixed in the same change.
- **On Windows it cannot run** (measured 2026-08-10): 0.23.17 fails before
  analysing anything — `Sandbox output folder must not contain ":"`
  (`_detectGitRoot` → `GitTool` → `SandboxRunner.runSandboxed` runs
  unconditionally; every absolute Windows path has a drive colon; being outside
  a git repository does not avoid it). That day's score was taken with 0.22.19,
  which predates the sandbox check. An earlier sentence said "on this machine
  that hole is closed — the environment moved to macOS at #59", turning one
  session's measurement into a standing property; #42 measured the session back
  on Windows. **The machine alternates; the hole alternates with it.**
- The honest substitute on Windows is pub.dev's own analysis of the published
  version: `curl -s https://pub.dev/api/packages/boring_avatars/score` (`0/0`
  with only `is:recent` = not yet scored).

**Environment — measure, do not read.** The machine Claude Code shares with the
maintainer **varies per session**: Windows (Flutter 3.41.9, Node v26.4.0, npm
11.17.0) through #58, macOS (Flutter 3.44.8, Node v24.11.1) at #59, Windows
again at #51 and #42, macOS again at #45 (when `tool/calibrate/render.mjs`'s
hardcoded Windows Chrome path finally cost a run). Measured 2026-10-22 for this
note: macOS (`Darwin`), Flutter 3.47.1 / Dart 3.13.1, Node v24.11.1. That list
is history, not a current-state field: `flutter --version`, `node --version`,
`uname -s`. What actually depends on the answer: `pana`, the CRLF restore, and
Chrome's path in `render.mjs`. Run `flutter test` / `analyze` / `dart format`
and the Node harnesses directly; ask the maintainer only for anything that opens
a window (`flutter run`) and say what to look for.

**Line endings are a property of the checkout, not of the repo.**
`.gitattributes` declares `* text=auto`; the index is LF for every text file
(`git ls-files --eol`: 174 `i/lf`, 44 `-text`, 6 `none` of 224 tracked files on
2026-10-22 — theflow's "80 text files" was an earlier count). The worktree
differs: CRLF under Windows' `core.autocrlf=true` (the source of lessons.md's
CRLF incidents), LF on macOS (`core.autocrlf` unset here). "The tree is CRLF"
is a *machine* fact and was recorded as a repo one until #59. The mutation
harness reads each file's own ending; a pattern typed from the wrong assumption
comes back `NO MATCH`.

**Branch and merge convention:** branch → `feat|fix|refactor|test(<scope>): …`
→ PR (`Closes #issue`) → **rebase-merge** (linear history; `git log --merges
--oneline main` is empty at HEAD, re-verified). Publishing is the
maintainer's (`pub-ready`, [release-and-publishing](release-and-publishing.md)).

**Reverting to test a test:** `git stash push -- <file>` / `git stash pop`,
never `git checkout -- <file>` on work in progress
([mutation-harness](mutation-harness.md)). The CRLF restore above is the one
sanctioned `git checkout --`, on generated files whose content is identical.

## Code
- `analysis_options.yaml` — `include: package:flutter_lints/flutter.yaml`, no
  extra rules
- `example/analysis_options.yaml` — the `flutter create` default, same include
- `.gitattributes` — `* text=auto`
- `tool/mutate/run.mjs` — `--check`
- `pubspec.yaml`, `example/pubspec.yaml` — two packages, two analyzer runs

## Reference behaviour
- pub.dev's `pana` 0.23.17 and the `/score` endpoint — the authority on the
  score; local `pana` approximates it only on macOS.

## Cross-cutting invariants
- [libm-transcendentals](../invariant/libm-transcendentals.md) — `flutter test`
  on Windows and on macOS reads the same goldens; that both pass is the only
  cross-platform byte evidence the gates produce, and nobody has recorded a
  same-day run on both.

## Blast radius
- [example-app](example-app.md) — a platform directory added there adds a path
  to the CRLF restore; a test directory added there owes a gate line.
- [mutation-harness](mutation-harness.md) — any rename in a targeted file can
  turn `--check` red; fix the case in the same change.
- [release-and-publishing](release-and-publishing.md) — the dry-run is the last
  gate and reads `.pubignore`; "0 warnings" says nothing about archive contents.
- [goldens](goldens.md), [parity-harness](parity-harness.md) — what
  `flutter test` reads; regenerating either is how a red gate can be "fixed"
  wrongly.

## Known holes / open
- `example/` has no unit/widget suite; its only test needs a real engine.
- Nothing enforces the CRLF-restore path list.
- `pana` is unavailable on Windows sessions.
- Cross-platform byte identity of `flutter test` output has not been recorded as
  a paired measurement (see the invariant above).
- `CLAUDE.md`'s Environment section still says "Windows machine … Flutter
  3.41.9, Node v26.4.0" — a single-machine statement this note's measurement
  contradicts.
