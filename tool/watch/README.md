# `tool/watch` — the upstream watcher

Files an issue when [`boringdesigners/boring-avatars`](https://github.com/boringdesigners/boring-avatars)
changes `src/lib/`. Driven on a schedule by `.github/workflows/upstream-watch.yml`
— **the one GitHub Actions workflow this repo has, and a watcher rather than a
gate**: it never runs on push or pull request, so it is not a check on any
branch and cannot block a merge.

```bash
node tool/watch/upstream.mjs                      # dry run — prints the issue it would file
node tool/watch/upstream.mjs --apply              # file it, then save state
node tool/watch/upstream.mjs --ref=main           # watch a different branch
node tool/watch/upstream.mjs --replay=v2.0.0..v2.0.1   # replay a past transition

node --test --test-reporter=tap tool/watch/diff.test.mjs   # the pure half
node tool/mutate/run.mjs cases/51-watch.json               # 10 mutants, all killed
```

`node --test tool/watch/` (the directory form) fails on Windows with a CJS
resolution error; name the file or glob it.

## Why blob SHAs and not releases

Measured across upstream's 28 tags, in the pinned reference tree:

| Fact | Number |
|---|---|
| tags | 28 |
| distinct `src/lib` trees | **18** |
| tags whose `src/lib` is identical to their predecessor's | **9** |
| releases published to npm with **no git tag** | **2** — `2.0.3`, `2.0.4` |

A release-triggered watcher is therefore noisy in one direction (9 tags where
nothing under `src/lib` moved) and **blind in the other**: upstream's two most
recent npm releases have no tag to trigger on at all, and `latest` is `2.0.4`.
The tree is the thing that actually moves, so the tree is what is watched.

## The state file

`last-seen.json` is committed, and that is the point — `git log` on it *is* the
record of when upstream moved. It holds the watched ref, the commit it pointed
at, the `src/lib` subtree SHA, and every blob SHA under it.

The commit is not decoration. The issue links a GitHub *compare* view, and
compare between two **tree** SHAs is a 404 — measured: `v2.0.1`'s and
`v2.0.2`'s `src/lib` trees return 404 from `github.com/…/compare`, their
commits return 200. `tool/mutate/cases/51-watch.json` case B-4 swaps one for
the other and the suite kills it, so the dead link cannot come back quietly.

## The order the two side effects happen in

On `--apply` the issue is filed **first**, the state written **second**.

If the state write fails after the issue is filed, the next run would file a
duplicate — except the title carries the tree SHA and is checked against
existing `upstream-watch` issues, so it usually does not. Either way that
failure is loud and one `gh issue close` undoes it.

The reverse order fails silently: state advances, the issue never appears, and
an upstream change is swallowed with nothing anywhere recording that it
happened. Between a recoverable duplicate and a silent loss, this takes the
duplicate.

## `--replay` — how the "no issue for a quiet tag" claim is checked

A subtree SHA from `git rev-parse <tag>:src/lib` in the pinned reference tree is
byte-identical to the one GitHub's tree API returns for the same subtree
(measured on `origin/master`: both `5790e5c5c9ef37af044d644eb75c48f200e5a7bd`).
So a replay feeds `diffTrees` the same numbers the scheduled run would have
seen, and is a real replay rather than an analogy.

`--replay` refuses `--apply`. A probe that could write state or file issues
would be indistinguishable from an observation, and the state it wrote would be
a past state presented as the present one.

Checked across **all 27 consecutive tag pairs** against `git diff --no-renames
--name-only … -- src/lib`: 27 of 27 agree. `--no-renames` is the honest
comparison — the watcher compares path sets, so it reports a rename as one
addition plus one removal, and git's rename detection collapses that to a
single line. With detection left on, three pairs "disagreed" and all three were
the probe misreading itself, not the watcher.

## The states it can be in, and how each is known to work

| State | How it is proved |
|---|---|
| no state file → baseline only, no issue | test + a real first run |
| unchanged | test + two live runs + 5 replayed no-op tag transitions |
| files modified | test + 4 replayed real transitions + a live run against a planted older state |
| files added / removed / renamed | test + the `v1.11.2 → v2.0.0` replay (upstream's JS→TS move: 9 removed, 9 added) |
| watched `ref` moved | test |
| tree moved, every blob identical (a mode change) | test |
| state file inconsistent with its own tree SHA | test — it throws rather than reporting a diff derived from a state that cannot exist |
| a truncated tree response | guarded, **not tested** — see below |
| GitHub unreachable | by construction: state is written last, so a failed fetch leaves it untouched and the next run retries |
| the issue was filed but the state commit failed | deduplicated by title, which carries the tree SHA |

The truncation guard is deliberately untested. `truncated` is GitHub paginating
a large tree, and this subtree holds nine files; the guard exists because
reading a truncated tree as a whole one turns "GitHub paginated us" into
"upstream deleted six files" — inventing a change out of nothing — and that is
worth one branch even where it should never fire.

## Two things that can make it go quiet

Both are properties of GitHub Actions, not of this code, and both fail toward
silence — which is why they are written down rather than guarded:

- **Scheduled workflows are disabled after 60 days of repository inactivity.**
  On a package that ships a release every few months, that is reachable.
- **If upstream renames `master`, the fetch 404s and the job goes red.** Nobody
  watches a green watcher; GitHub does email the last editor of the cron on a
  failed scheduled run, which is the only reason this is a note and not a
  guard.

## What it deliberately does not do

- **A first run files nothing.** No previous state means there is nothing to
  compare, and reporting the baseline as nine added files would announce that
  upstream rewrote everything on a day it did nothing.
- **It does not decide anything.** A `src/lib` change is not automatically a new
  release — `CLAUDE.md` principle 3 makes the unit the *output state*, which is
  measured with `tool/versions`, not inferred from a diff. The issue says what
  moved and asks a human.
