# upstream-watch

## What it is
A weekly GitHub Actions job (`.github/workflows/upstream-watch.yml`) plus
`tool/watch/`, which files an issue when upstream
`boringdesigners/boring-avatars` changes anything under `src/lib/`. It watches
**`src/lib` blob SHAs, not version numbers**, and it decides nothing — a
`src/lib` change is not automatically a new output state; the issue says what
moved and asks a human, who measures with [version-grouping](version-grouping.md).
It is the repo's only workflow, and a **watcher, not a gate**.

## Governing decisions
**None.** No ADR. It is a deliberate exception to the house "no CI"
convention (`CLAUDE.md`, Environment), justified below; see [gates](gates.md).

## Design model
- **Why blob SHAs, not releases** — measured over upstream's 28 tags (#51; the
  first three re-verified 2026-10-22 against the pinned tree with
  `git rev-parse <tag>^{commit}:src/lib`):

  | Fact | Number |
  |---|---|
  | tags | 28 |
  | distinct `src/lib` trees | **18** |
  | tags identical to their predecessor | **9** |
  | npm releases with **no git tag** | **2** — `2.0.3`, `2.0.4` (tags stop at `v2.0.2`; `latest` is `2.0.4`) |

  A release-triggered watcher is noisy one way and **blind to upstream's two
  most recent releases** the other.
- **A correction #51 measured** (theflow Step 7): the earlier sentence "v1.9.0,
  v1.10.0, v2.0.1 and v2.0.2 changed nothing under `src/lib/` … only ~16 tags
  are real work" was two-thirds wrong: v1.9.0/v1.10.0/v2.0.1 unchanged — true;
  v2.0.2 unchanged — **false** (`types.ts` and `index.tsx` moved); "~16" — **18**
  distinct trees. External facts asserted by the repo's own docs are
  verification targets too.
- **The tag-less fact was not new; carrying it was.** #45 had recorded it
  ("주의 — 태그가 없는 버전") as a note on where to *read* those versions from;
  nobody had moved it into the watcher's rationale or the README's
  npm-versus-tag section until #51. A measured fact sitting correctly in one
  issue is not a fact the project reasons with.
- **Why the exception to "no CI" holds**: it runs only on `schedule` (Mondays
  06:17 UTC) and `workflow_dispatch`, never on push or pull request, so it is a
  check on no branch and cannot block a merge — and `main` carries no branch
  protection to make it one (measured #51: the protection endpoint 404s;
  attributed). Its failure mode is silence, not obstruction.
- **Order of side effects**: on `--apply` the issue is filed **first**, state
  written **second**. A failed state write after filing yields a duplicate
  (usually prevented: the title carries the tree SHA and is checked against
  existing `upstream-watch` issues); the reverse order would swallow a change
  silently.
- **The state file is committed** — `git log tool/watch/last-seen.json` *is*
  the record of when upstream moved. It holds ref, commit, `src/lib` tree SHA
  and every blob SHA. The commit is needed because GitHub's compare view 404s
  between two tree SHAs (measured: v2.0.1/v2.0.2 trees 404, commits 200);
  mutation case B-4 in `51-watch.json` guards it.
- **`--replay=<a>..<b>`** feeds `diffTrees` the subtree SHAs from the pinned
  tree, byte-identical to GitHub's tree API (measured on `origin/master`:
  `5790e5c5…`), so it is a real replay. Checked over all 27 consecutive tag
  pairs against `git diff --no-renames --name-only … -- src/lib`: 27/27 agree
  (with rename detection on, three pairs "disagreed" — the probe misreading
  itself). `--replay` refuses `--apply`.
- **The job tests itself before acting**: `node --test --test-reporter=tap
  tool/watch/diff.test.mjs` runs first; a watcher with broken logic filing
  issues is worse than one that does nothing. Node pinned to `22`.
- **Least privilege**: `contents: write` (commit `last-seen.json`), `issues:
  write`; the repository default is read-only.
- **A first run files nothing** (baseline only).
- **Input bounds**: the GitHub tree API response; a `truncated` tree is guarded
  (would otherwise read "GitHub paginated us" as "upstream deleted files") but
  deliberately untested — the subtree holds nine files.

## Code
- `.github/workflows/upstream-watch.yml` — job `watch`
- `tool/watch/diff.mjs` — `UPSTREAM`, `diffTrees`, `renderIssue` (pure half)
- `tool/watch/upstream.mjs` — the impure half: `STATE_PATH`, `REFS`, `REPO`,
  `WATCHED = 'src/lib'`, `LABEL = 'upstream-watch'`, `--apply`, `--ref`,
  `--replay`
- `tool/watch/diff.test.mjs`
- `tool/watch/last-seen.json` — at HEAD: ref `master`, commit `d0ff258…`,
  tree `5790e5c5…`, nine files (`components/avatar-*.tsx`, `types.ts`,
  `index.tsx`, `utilities.ts`)
- `tool/watch/README.md` — the states table and how each is proved
- `tool/mutate/cases/51-watch.json` — 10 cases, `runner: node`

## Reference behaviour
- Pinned upstream tree `../.refs/boring-avatars` — the source of the tag
  measurements and of `--replay`.
- GitHub REST tree API for `boringdesigners/boring-avatars` — what the
  scheduled run reads.

## Cross-cutting invariants
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) — the
  watcher is what announces that every copy of the mapping may owe a row.

## Blast radius
- [version-grouping](version-grouping.md) — the human answering a watcher
  issue measures there; a change to what the issue reports changes what they
  start from.
- [mutation-harness](mutation-harness.md) — `51-watch.json` targets
  `diff.mjs` and counts `diff.test.mjs`'s TAP output.
- [gates](gates.md) — if the workflow ever gained a `push`/`pull_request`
  trigger it would become a gate, contradicting the "no CI" convention it is an
  exception to.

## Known holes / open
Both from GitHub Actions, both failing toward silence (README):
- **Scheduled workflows are disabled after 60 days of repository inactivity**
  — reachable on a package that ships every few months. Last state commit at
  HEAD: `c3a8ad0` (`git log -- tool/watch/last-seen.json`).
- **If upstream renames `master`, the fetch 404s and the job goes red**;
  GitHub emails the cron's last editor, nobody else.
- `node --test tool/watch/` (directory form) fails on Windows with a CJS
  resolution error; name the file.
