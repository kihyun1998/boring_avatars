# variant-dispatch

## What it is
Upstream's `avatar.js` / `index.tsx` dispatch: which of the six variant builders
draws a request. It owns the public `BoringAvatarsVariant` enum (six drawn
styles plus the two deprecated aliases), alias resolution, the degrade-to-
`marble` rule for an unrecognised upstream string, and the final
`switch (variant.resolved)` in `buildAvatarScene` that calls a builder. It is
the one piece of the dispatch that does **not** vary by selector; the parts that
do (`<title>`, the drawing era) are [version-selectors](version-selectors.md).

## Governing decisions
No ADR. Three decisions, one of them a maintainer ruling recorded here in full.

**Variant resolution does not vary by version — a derivation with a validity
condition, not a ruling.** Verified by reading `avatar.js` / `index.tsx` at
every tag from 1.6.1 to 2.0.2, and extended to `master` (= npm 2.0.3/2.0.4) in
#45: the roster, the two deprecated aliases and the `marble` default are
unchanged across the covered range (re-verified this map pass, 2026-10-22, at
`v1.6.1`, `v1.10.1`, `v1.11.0`, `v1.11.1`, `v1.11.2`, `v2.0.0`–`v2.0.2`,
`master`). So the dispatch is not parameterised by a selector. **Valid as long
as that stays true**: a release that changes the dispatch roster makes
resolution version-dependent and this seam has to move into
[version-selectors](version-selectors.md).

**`turbulence` is not ported — unreachable upstream code has no output to
reproduce** (#1, closed #8). `avatar-turbulence.js` ships from v1.2.0 to v1.5.2
with an unchanging blob and is dispatched by no version; porting it from the
file tree would have built the project's heaviest rasterizer feature for
something no user could select. The war story is in
[lessons.md](../../agents/lessons.md) ("A file existing is not the feature
existing"). The same judgement drops `getModulus`/`getAngle`
([upstream-utilities](upstream-utilities.md)).

### S-5 — the ruling, as an event
The ledger row is in
[upstream-divergences](../aggregate/upstream-divergences.md); this is the event
and what the code does about it.

**What the user was shown (2026-08-14, #45's batch):** the measured fork —
`'constructor'` handed to upstream as a `variant` degrades to marble at
1.10.1–1.11.2 and crashes React at 2.0.x, because `AVATAR_VARIANTS[variant]`
resolves an inherited `Object.prototype` member where the older roster check
did not — beside the fact that the reference cannot arbitrate (it disagrees
with itself inside one selector's covered range), that the port's parser
degrades to marble matching 7 of 9 releases, that the enum-typed public API
cannot even produce such a string except through
`BoringAvatarsVariant.fromUpstreamName`, and the agent's recommendation to keep
the degrade.

**What they chose:** keep the degrade — *"1번은 현행 유지로 가고"*.

**It is theirs to reverse.** A crash-vs-degrade product judgement, the same
class as S-2 and S-4; a later argument that the port should reproduce 2.0.x
faithfully does **not** reopen it — only the user does.

**What it costs.** For exactly the prototype-key strings, a caller of
`fromUpstreamName` gets a marble avatar where npm's `latest` would crash. Every
other unknown string behaves identically to every covered release, and the six
real names plus two aliases are untouched. The 2.0.x crash is a JS
prototype-chain accident, not a designed refusal — reproducing it would mean
reproducing the accident's mechanism.

**Re-measured this map pass (2026-10-22), and two details of what was shown are
off — the ruling's substance is not.** Rendering the real npm packages
(`tool/parity/node_modules`, React 18, Node v24.11.1) with `variant` set to four
prototype keys:

| release | `constructor` | `toString` | `__proto__` | `valueOf` |
|---|---|---|---|---|
| 1.10.1, 1.10.2, 1.11.1, 1.11.2 | marble | marble | marble | marble |
| 2.0.0 – 2.0.4 | throws | renders the text `[object Undefined]` | throws | throws |

So the degrade matches **4 of the 9** releases `v1_10_1` covers, not 7 (or 11 of
the 16 in-scope releases); and not every prototype key crashes 2.0.x —
`toString` is *called as a component* and renders a text node. And the 1.11.x
degrade is not a roster check: `DEPRECATED_VARIANTS[variant] || variant`
resolves the inherited function first, and the second lookup
`AVATAR_VARIANTS[<function>]` misses, falling to `AvatarMarble` — an accident
that happens to degrade. None of this changes what was decided (the port
degrades on every prototype key, which every pre-2.0 release does); it is
recorded so a later reader does not re-derive "7 of 9".

## Design model
From the source, the doc-comments and `api_surface_test.dart` (no record beyond
the rulings above).

- **The dispatch is the authority, not the file listing** (hidden-state #12).
  `BoringAvatarsVariant` holds exactly what upstream dispatches from 1.5.3
  onward: `pixel`, `bauhaus`, `ring`, `beam`, `sunset`, `marble`
  (`renderable`), plus `geometric → beam` and `abstract → bauhaus`.
  `abstract` is a Dart keyword, so the value is `abstractStyle` and
  `upstreamName` carries the string.
- **Unknown degrades, never throws** (hidden-state #15): `fallback` is
  `marble`, the era's default from v1.3.0 on (`geometric` at v1.2.0, out of
  scope).
- **One scan, not upstream's two stages — safe only because no
  `upstreamName` is in both sets.** Upstream tests its alias map before its
  roster, so a name carrying both meanings would resolve as the alias;
  `fromUpstreamName` meets the renderables first and would answer the other
  way. Uniqueness makes the order unobservable, and `api_surface_test.dart`
  asserts that uniqueness directly. *(The doc claimed the two-stage order until
  #59's completeness pass measured the code never had it, and the test then
  named for the ordering passed under `values.reversed` — a test that could
  not fail, replaced.)*
- **The public enum makes S-5 structural**: the API takes an enum, so a
  prototype-key string can only arrive through `fromUpstreamName`, whose
  linear scan over `values` cannot match it.
- **The final switch is exhaustive over the enum, including the aliases.**
  `variant.resolved` lands in `renderable` by contract, so the
  `geometric || abstractStyle` arm throws `StateError` and is dead by
  construction; it exists so a new enum value fails to compile there instead
  of falling through to a default. `api_surface_test.dart` pins the contract
  that makes it dead (`every variant resolves into the renderable set`).
- **No defaults inside `buildAvatarScene`.** The `marble` default lives on the
  public `boringAvatarSvg` only, because upstream's defaults are part of its
  API. A second default inside the dispatch was unreachable — its mutation
  survived the whole suite (#59; [lessons.md](../../agents/lessons.md), "A
  default nobody can reach is unreachable code, not a convenience").

**History the enum deliberately omits** — the reachable-variant matrix, from
`avatar.js` dispatch and not the file tree (re-verified this pass at `v1.2.0`,
`v1.3.0`, `v1.4.0`, `v1.4.2`, `v1.5.3`; all rows but the last are out of
scope):

| State / tags | Reachable variants | Default | Aliases |
|---|---|---|---|
| v1.2.0 | geometric, abstract, beam, eye, marble | `geometric` | — |
| v1.3.0–v1.3.1 | marble, dome, moholy, beam, ring | `marble` | — |
| v1.4.0–v1.4.2 | marble, pixel, bauhaus, ring, beam, sunset, dome | `marble` | — |
| v1.5.3 → v2.0.x / master | pixel, bauhaus, ring, beam, sunset, marble | `marble` | geometric→beam, abstract→bauhaus |

Eleven variants are reachable across the whole history; `turbulence` in zero
states. `eye` is dispatched **only at v1.2.0** while its file survives to
v1.5.2 (hidden-state #13). `geometric`/`abstract` carry three meanings by era
(hidden-state #14): distinct variants at v1.2.0, unreachable (fall to `marble`)
v1.3.0–v1.4.2, deprecated aliases from v1.5.3 — one enum value with one meaning
is right only because scope starts at v1.6.1.

## Code
- `lib/src/variant.dart — BoringAvatarsVariant` (values, `upstreamName`)
- `lib/src/variant.dart — BoringAvatarsVariant.renderable`, `.fallback`
- `lib/src/variant.dart — BoringAvatarsVariant.resolved`
- `lib/src/variant.dart — BoringAvatarsVariant.fromUpstreamName`
- `lib/src/avatar.dart — buildAvatarScene` (the `switch (variant.resolved)`
  that calls `buildMarbleScene`, `buildBeamScene`, `buildPixelScene`,
  `buildSunsetScene`, `buildRingScene`, `buildBauhausScene`)
- Tests: `test/api_surface_test.dart` — groups `BoringAvatarsVariant`,
  `variant resolution mirrors upstream avatar.js`, `fromUpstreamName degrades
  exactly as upstream does` (incl. `no upstream name carries two meanings —
  what makes one scan safe`); `test/avatar_svg_test.dart` — group `the dispatch
  mirrors upstream avatar.js`.
- Mutation case file: `tool/mutate/cases/59-dispatch.json`
  ([mutation-harness](mutation-harness.md)).

## Reference behaviour
- `git -C /Volumes/T7/GitHub/.refs/boring-avatars show v1.6.1:src/lib/components/avatar.js`
  — roster + `deprecatedVariants` + `'marble'` fallback (same shape through
  v1.11.0).
- `… show v1.11.2:src/lib/components/avatar.js` — `DEPRECATED_VARIANTS[variant] || variant`,
  then `AVATAR_VARIANTS[resolvedVariant] || AvatarMarble`.
- `… show master:src/lib/index.tsx` — aliases folded into `AVATAR_VARIANTS`,
  `AVATAR_VARIANTS[variant] || AvatarMarble` (the S-5 site, `index.tsx` @
  v2.0.0–master).

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — which
  builder a name reaches is part of every shipped selector's output.

## Blast radius
- [variants](../aggregate/variants.md) — every variant builder is reached only
  through this switch; a resolution change silently gives a caller another
  variant's picture, which no per-variant parity test sees because each
  calls its builder directly.
- [version-selectors](version-selectors.md) — shares `buildAvatarScene`; the
  claim that resolution is version-independent is what lets the variant switch
  sit outside the version switches.
- [public-svg-surface](public-svg-surface.md) — `BoringAvatarsVariant` is
  exported; adding, renaming or removing a value is a public API change.
- [widget-lifecycle](widget-lifecycle.md) — the widget takes the same enum and
  calls `buildAvatarScene`, so it inherits the alias and degrade rules.

## Known holes / open
- **S-5's behaviour is not pinned by a test.** `fromUpstreamName degrades
  exactly as upstream does` tries `turbulence`, `eye`, `dome`, `moholy`, `''`,
  `Marble`, `nonsense` — no prototype key. It holds structurally (a scan over
  enum values cannot match `'constructor'`), so a test would guard only a
  rewrite to a `Map` lookup.
- The S-5 event as shown to the user carried "7 of 9" and "React crashes";
  measured 4 of 9 and one non-crashing key (above). Whether the maintainer wants
  the event text itself amended is theirs to say.
- The validity condition above (dispatch roster unchanged) is re-checked only
  when someone reads a new upstream release's dispatch;
  [upstream-watch](upstream-watch.md) flags new releases, not roster changes.
