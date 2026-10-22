# milestones-sync

## What it is
`tool/milestones/sync.mjs` renders the GitHub milestone descriptions for
`kihyun1998/boring_avatars` from `CLAUDE.md`'s principle-3 release table. A
milestone description must carry the version list itself ("see CLAUDE.md" is
useless to someone browsing GitHub), so the mapping lives in two surfaces; this
tool derives one from the other. **Run it whenever that table changes.** Dry
run by default; `--apply` writes. A tool, not a gate.

## Governing decisions
**None.** It mirrors `CLAUDE.md` principle 3, the single home of the mapping.

## Design model
- **Derived vs authored, one home each.** The version list is parsed from
  `CLAUDE.md` (`readReleaseTable`, a regex over `| \`x.y.z\` | \`selector\` |
  versions |` rows; throws if none match). The per-release sentence — what
  ships, why `1.11.0` is excluded — is a product judgement kept in `NOTES` in
  the script, so regenerating never destroys it. Description format:
  `상류 <versions> 지원 (선택자 \`<sel>\`). <note> — 버전 목록은 CLAUDE.md 원칙 3
  에서 생성됨 (tool/milestones/sync.mjs)`.
- **Three kinds of drift reported**, each verified to fire (attributed): a
  version list that no longer matches; a milestone with no row in the table;
  a row with no note (`describe` throws — checked *before* looking up the
  milestone, because a new release is exactly when the milestone does not
  exist yet).
- **`state=all` is load-bearing.** The API defaults to open milestones, so a
  shipped release's milestone would vanish and be reported "missing" — caught
  the day `0.1.0` was closed. A shipped release's description is the permanent
  record.
- **`NOTES` is not derived, so nothing checks it.** The `0.1.0` note said
  "widget and pixel output are the next release" until after publish, although
  the maintainer had widened `0.1.0` on 2026-08-10 (comment in `NOTES`).
- **Input bounds:** `CLAUDE.md` and the GitHub milestones API (`--paginate`).

## Code
- `tool/milestones/sync.mjs` — `REPO`, `NOTES`, `readReleaseTable`,
  `describe`, `gh`

## Reference behaviour
**None.** Measured 2026-10-22 (dry run): `0.1.0` and `0.2.0` match (closed),
`0.3.0` matches (still open); no milestone without a table row.

## Cross-cutting invariants
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) — the
  milestone descriptions are a generated copy of the mapping; this tool is the
  one copy kept in sync mechanically.

## Blast radius
- [release-and-publishing](release-and-publishing.md) — a new release row in
  `CLAUDE.md` owes a `NOTES` entry and a run; a reformatted table breaks
  `readReleaseTable`.
- [version-selectors](version-selectors.md) — a new selector is a new row here.

## Known holes / open
- Patch releases (`0.3.1`–`0.3.3`) have no row in `CLAUDE.md`'s table and so no
  milestone; the tool has no notion of a release that is not a state.
- The `0.3.0` milestone is open two months after `0.3.0` published.
- `NOTES` can drift from what shipped with nothing to catch it.
