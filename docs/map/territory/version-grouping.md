# version-grouping

## What it is
`tool/versions/` installs every in-scope npm release of `boring-avatars` side
by side and groups them by **what a caller actually gets** — the criterion the
release plan rests on (`CLAUDE.md`, principle 3). It is the re-runnable
evidence for "these versions produce the same thing", and so for the number of
selectors and releases. A tool, not a gate. It also owns `ext-hook.mjs`, the
Node loader hook every harness uses to import upstream's 2.0.x ESM build.

## Governing decisions
**None.** No ADR. Governed by maintainer rulings (all 2026-07-29, theirs to
reverse): two versions share a selector when a caller gets the same output
(*"꼭 버전마다 하나씩 만드는건 아니고 사용자 입장에서 결과물이 같으면 묶어서
하는거임. 문법은 상관없어. 결과물이 중요."*); `1.11.0` is excluded; the
committed fixture is per output state while every covered version is still
measured. The grouping ruling is carried in
[version-selectors](version-selectors.md); the fixture-per-state ruling in
[release-and-publishing](release-and-publishing.md).

## Design model
- **Measured, not read.** Source identity is neither necessary nor sufficient
  (`1.11.1`/`1.11.2` differ in source and match in output; `1.11.0` shares
  `1.11.1`'s intent and emits junk attributes). The grouping is therefore a
  render, never a blob hash.
- **Every covered version is measured; the fixture is per output state.**
  `group.mjs` renders 15 releases (`VERSIONS`) × 6 variants × 4 names
  (`Clara Barton`, `박기현`, `a`, `''`) with upstream's default palette, and
  buckets them under four progressively looser projections: raw; ids
  normalised (`withoutIds`: `id`, `url(#…)`, `mask`, `filter`); ids and
  `<title>` set aside (`withoutTitle`); ids normalised with `title` forced on.
  Then ⑤ reports which variant each boundary turns on. The per-version render
  and comparison that the fixture-per-state ruling requires is also done,
  over the full corpus, by [parity-harness](parity-harness.md)'s `groupProof`.
- **`1.8.0`/`1.9.0` are absent on purpose**: their npm tarballs contain no
  JavaScript (`main` → `build/index.js`, absent); they sit in `1.10.0`'s group
  by source tree (same blob). `countJsFilesOnNpm` in `tool/parity/dump.mjs`
  re-runs that count.
- **The source/output trap, concretely** (maintainer was shown this,
  2026-07-29): for the `v1_6_1` group, three artefacts and three answers —

  | | 1.6.1 | 1.6.2 | 1.6.3 |
  |---|---|---|---|
  | git `src/lib` tree | `3cca55f5…` | same | same |
  | published npm bundle | `c9491576…` | same | **`f4636f1d…`** |
  | rendered output | — | identical | identical |

  1.6.3's bundle differs by exactly 34 bytes — the trailing
  `//# sourceMappingURL=index.js.map` and its newline; everything executable is
  byte-identical (`cmp`). The rule's teeth are in the middle row: a matching
  git tree is a *source* argument for an *output* claim; next time the npm
  divergence may not land in a comment, and the check that catches it is the
  render.
- **`ext-hook.mjs`**: 2.0.x ships ESM whose relative imports lack extensions,
  which Node rejects; the hook appends `.js` / `/index.js` so the published
  package loads unmodified — what is rendered is what npm shipped. Registered
  by `register.mjs` (`npm run group`), and by `tool/parity/dump.mjs` and
  `tool/crosscheck/crosscheck.mjs` through `register('../versions/ext-hook.mjs')`.
- **Input bounds:** a fixed in-code version list and name list.

## Code
- `tool/versions/group.mjs` — `VERSIONS`, `VARIANTS`, `NAMES`, `PALETTE`,
  `withoutIds`, `withoutTitle`, `renderAll`, `group`
- `tool/versions/ext-hook.mjs` — `resolve`
- `tool/versions/register.mjs`
- `tool/versions/package.json` — 15 aliases `v1_6_1` … `v2_0_4` (incl.
  `v1_11_0`); not installed in the checkout (`cd tool/versions && npm install
  && npm run group`)

## Reference behaviour
Measured results (attributed — theflow "The states in scope"; owned by
[version-selectors](version-selectors.md)): raw bytes 6 groups; ids normalised
4; ids + `<title>` set aside 3; `title` forced on 3. The `v1_7_0` → `v1_10_1`
boundary is one variant wide — `pixel` differs on 6 of 6 names, the other five
byte-identical. `1.11.0` separates on its own (its props leak onto `<svg>`);
the script's closing line says so.

## Cross-cutting invariants
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) —
  `VERSIONS` is the one copy that lists *every* in-scope release including the
  excluded `1.11.0`; it must gain a row when upstream publishes.

## Blast radius
- [version-selectors](version-selectors.md) — a new upstream release is
  grouped here first; a new bucket means a new selector, never an edit to a
  shipped one.
- [parity-harness](parity-harness.md), [crosscheck](crosscheck.md) — they load
  2.0.x through `ext-hook.mjs`; a change to its resolution rule changes what
  they render.
- [upstream-watch](upstream-watch.md) — the watcher's issue says what moved and
  asks a human; this tool is how that human decides whether it is a new state.

## Known holes / open
- `group.mjs` prints group membership and asks the reader to check it against
  `CLAUDE.md`'s table ("결과가 CLAUDE.md 원칙 3 의 표와 맞는지 확인하세요") — it
  asserts nothing; a drift would be read, not caught.
- Four names, one palette: coarser than the parity corpus (20 × 5). The
  per-selector `groupProof` is the full-corpus measurement.
