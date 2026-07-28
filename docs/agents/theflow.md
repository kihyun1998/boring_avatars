# theflow bindings (boring_avatars)

Project-specific data for the `theflow` skill. The skill holds the portable
*method*; this file holds this package's *bindings* — which reference to read,
where the boundary falls, how to prove behavior, which surfaces to sweep, which
gates to run. Per-incident evidence lives in [`lessons.md`](lessons.md).

Identity & invariants live in `CLAUDE.md`. `CONTEXT.md` / `docs/adr/` do not
exist yet — created lazily.

**Environment:** Claude Code and the user share the same Windows machine. On
`PATH`: Flutter 3.41.9, Node v26.4.0, npm 11.17.0 — run `flutter test` /
`analyze` / `dart format` and the Node parity harness directly (do not ask). The
exception is anything that opens a window (`flutter run`) — ask the user to drive
and say what to look for. **There are no CI gates**: the Step 7 gates are the
only gates and they run here. The one GitHub Actions workflow this repo has is a
*watcher*, not a gate (see Step 7).

---

## Reasoning bindings (project-wide)

**The reference is the specification, not a cross-check.** theflow's default —
"our own measurement outranks prior art" — is **inverted here**. Producing the
same output as `boring-avatars` *is* the product. A derivation that disagrees
with upstream is wrong by definition, however elegant.

**But a suspected upstream bug is never adjudicated by the agent.** When the
reference does something that looks like a defect, do **not** decide it alone in
either direction — neither "replicate silently" nor "fix silently". It goes into
the **user's approval batch** with:

- the `file:line` in the pinned reference tree,
- the value upstream actually produces,
- the value a "corrected" version would produce,
- what the difference looks like on screen.

The user rules per case. **Record the ruling as an *event*** in the divergence
ledger below — what they were shown, what they chose, and that it is theirs to
reverse. This is a **product judgement, not a derivation**: a later adversarial
pass producing a stronger argument does *not* reopen it. Writing "the user
decided X on <date>, shown Y" is what stops that re-litigation.

**Never dismiss a divergence candidate on a feeling.** Cite the ground — the
reference line, an existing ledger row, or the lens's own `INERT`/`DELIBERATE`
grade — or carry it to the batch.

---

## Crate / module map

Single Flutter package, single-context. The layer directories and the public
enums exist as of #1; **every layer below is still empty of behavior** — each
arrives with the ticket that fills it. This map is a binding because Step 2
splits changes against it.

Already present: `lib/src/version.dart` (`BoringAvatarsVersion`, the 17 states)
and `lib/src/variant.dart` (`BoringAvatarsVariant`, the 11 reachable variants),
plus the era-based variant resolution that mirrors upstream's `avatar.js`.

Public surface is the barrel `lib/boring_avatars.dart`.

| Module (`lib/src/`) | Layer | Role |
|---|---|---|
| `js/` | **1 data** | JS-semantics primitives — `hashCode`, `getNumber`, `jsMod`, `toSigned32`, `getDigit`, `getBoolean`, `getUnit`, `getRandomColor`, `getContrast`. **Sacred.** |
| `variants/<name>/v<ver>.dart` | **1 data** | per-variant, per-upstream-state value generation. **Sacred.** |
| `scene/` | **2 scene** | resolved drawing description — paths, transforms, fills, gradients, filters. Backend-neutral. |
| `svg/` | **2 scene** | scene → SVG string (the byte-parity surface) |
| `raster/` | **3 raster** | deterministic software rasterizer — scanline coverage AA, path flattening, 3-box blur, blend modes, gradients, filter-region clipping |
| `widget/` | consumer seam | `BoringAvatar` widget; `ui.decodeImageFromPixels` hand-off, caching |

Everything is inside the top-level `flutter test` workspace. **There are no
out-of-workspace members today.** When `example/` is created it becomes a
separate package with its own analyzer run and suite — add both to Step 7 then
(house convention; a leftover `flutter create` counter template kept
`flutter_table_plus`'s example gate permanently red, which trains everyone to
ignore it — #55 there).

---

## Step 1 — reference routing table

Read real source from the **local pinned reference tree** at `../.refs/boring-avatars`
(sibling of this repo, same convention as `../justerm` / `../just-shield`), with
`rg -n <symbol> -A 8`.

**WebFetch is banned on reference source** — it summarizes and silently drops
method bodies, so a generator that *is* there reads as absent. Fetch raw
(`gh api repos/<o>/<r>/contents/<path> -H "Accept: application/vnd.github.raw"`)
and grep the real lines.

| Change type | Real source to read |
|---|---|
| **Data-layer values** (hash, `getUnit`, a variant's generator) | `../.refs/boring-avatars` at the **specific tag** being ported — never at HEAD. The generator body is the whole spec |
| **JS language semantics** (`%` sign, `ToInt32`, `if(index &&…)` truthiness, `Number.prototype.toString`) | **Run a Node probe and read the number.** Reading the code is not observing what it does. Cross-check ECMA-262. **Never from memory** |
| **SVG geometry semantics** (`rx` clamp, arc out-of-range radii F.6.6, filter-region default `-10%/120%`) | the **SVG 1.1 / Filter Effects spec text**, not a blog restatement. The normative wording is the part a summary drops |
| **Rasterization** (Gaussian 3-box approximation, blend math, gradient interpolation) | Filter Effects spec first; where it is silent, a **Chrome render measured directly** |
| **Flutter canvas / image hand-off** | Flutter SDK source (house pattern) |
| **Published state** | `curl -s https://pub.dev/api/packages/boring_avatars` |
| **Hidden state** | the list below, in this file |

Create the reference tree once (it is outside the repo, so nothing to gitignore):

```bash
mkdir -p ../.refs && cd ../.refs
git clone --filter=blob:none --sparse https://github.com/boringdesigners/boring-avatars boring-avatars
cd boring-avatars && git sparse-checkout set src/lib && git fetch --tags
```

Do **not** use `--depth 1` here — unlike the other `.refs` trees, this one is
walked by tag across its whole history (below), so the tags must be present.

### The upstream version ladder — the port order

The target is the **full upstream history from v1.2.0**, walked in order.
**Decided by the user on 2026-07-28**, shown the collapsed-state analysis below
and the alternative of targeting only the frozen v1.6.1+ range. A product call —
theirs to reverse, not reopened by a later efficiency argument.

28 tags collapse to **17 distinct algorithm states**. Port one state per slice;
tags that share a state are one slice, not several.

*(Corrected from 16 while working #1: row 15 below held two states, not one —
v1.11.0's components differ from v1.11.1's. Verified by blob SHA.)*

| # | Tags | Hash | Variant set |
|---|---|---|---|
| 1 | v1.2.0 | `getNumber` | geometric (default), abstract, beam, eye, marble |
| 2 | v1.3.0–v1.3.1 | `getNumber` | marble (default), dome, moholy, beam, ring |
| 3 | v1.4.0 | `getNumber` | + bauhaus, pixel, sunset (9) |
| 4 | v1.4.1 | `getNumber` | 9 |
| 5 | v1.4.2 | `getNumber` | 9 |
| 6 | v1.5.3–v1.5.5 | `getNumber` | `dome` dropped → the modern 6; `geometric`/`abstract` become aliases |
| 7 | v1.5.6 | `getNumber` | 6 ⚠️ reverted at v1.6.0 |
| 8 | v1.5.7–v1.5.8 | `getNumber` | 6 ⚠️ reverted at v1.6.0 |
| 9 | v1.6.0 | `getNumber` | **byte-identical to v1.5.3** |
| 10 | **v1.6.1–v1.6.3** | **`hashCode`** ← the switch | 6 |
| 11 | v1.7.0 | `hashCode` | 6 |
| 12 | v1.8.0–v1.10.0 | `hashCode` | 6 |
| 13 | v1.10.1 | `hashCode` | pixel only |
| 14 | v1.10.2 | `hashCode` | marble only |
| 15 | v1.11.0 | `hashCode` | 6 |
| 16 | v1.11.1–v1.11.2 | `hashCode` | 6 — `defaultProps` → destructuring defaults, **same values**, no output change |
| 17 | v2.0.0–v2.0.2 (+ 2.0.3/2.0.4 on `master`) | `hashCode` (TS rewrite) | 6 |

**Eleven** reachable variants — six current (`marble`, `beam`, `pixel`,
`sunset`, `ring`, `bauhaus`) and five historical (`geometric`, `abstract`,
`eye`, `dome`, `moholy`). `turbulence` ships a file but is **never dispatched**
— see hidden-state #12 and the reachable-variant matrix.

**States 16→17 and within 17, cleared concerns:** `v2.0.0` vs `v2.0.1`
`index.tsx` is byte-identical (only `types.ts` moved, which has no runtime
effect); `2.0.4` adds `size = '40px'` as a *default*. That last one is **consumer
policy under this project's boundary rule**, not part of the version state — the
caller always supplies size here. Valid **as long as `size` stays consumer-owned**;
if the package ever renders at an implicit default, 2.0.3/2.0.4 becomes its own
state.

**States 7–9 are the trap.** v1.5.6/v1.5.7/v1.5.8 changed all six components and
v1.6.0 restored v1.5.3's blobs exactly — upstream reverted them. Port them as
*history*, and do not carry their changes forward into state 10.

**npm 2.0.4 has no git tag** (latest tag is v2.0.2). Resolve the 2.0.3/2.0.4
state from `master` blobs, not from a tag that does not exist.

### Scope boundary — the ladder is git tags, not npm versions

**Decided by the user on 2026-07-28**, shown the npm survey below. A product
call. Recorded here with its **validity condition** so the investigation is not
re-run and the consequence is not later mistaken for a defect.

The npm registry publishes **69 versions** collapsing to **38 distinct code
states** — more than double the 16 the git tags describe. We deliberately track
**git tags only**. This is valid **as long as the package does not claim
npm-version-level fidelity**. Three concrete divergences follow from it:

- **npm `1.2.1` ships `0.1.4`-era code** (identical content hash). Its bundle has
  only `abstract` and `geometric` and defaults `name: "abcdefg"`, while git
  `v1.2.0` already had beam/eye/marble/ring/turbulence. **A version number is not
  a point on the code's timeline** — 1.2.1 is *older* code than 1.2.0. So a
  `version: v1_2_0` selector matches the **tag**, and will not match a user's
  `npm i boring-avatars@1.2.1`.
- **npm `0.1.3`, `1.8.0`, `1.9.0` shipped no JavaScript at all** — `main` points
  at a `build/` directory absent from the tarball. Nobody could ever have run
  them, so there is no output to reproduce. `v1.8.0`/`v1.9.0` as *git* states are
  still reachable: their content equals state 12, which `v1.10.0` also shipped.
- **27 npm versions predate the first git tag** (`0.0.1` … `1.1.2`, from
  2020-12-30). They contain real, working code — often as unbundled source — and
  are simply out of scope.

Eight of the 38 npm states exist **only** as minified webpack UMD bundles with
no git tag and no `sourcesContent` in their sourcemaps. Their logic is
recoverable (the arithmetic survives; only the identifiers are mangled), but at
a cost. Avoiding that cost is part of why the boundary sits at git tags.

**If a user reports "your `v1_x` does not match my npm install", this note is the
answer, not a bug report.** Moving the boundary is a scope change and goes back
to the user.

### Hidden-state list

Read this **before** writing any data-layer code. These are the JS/SVG semantics
a first-principles Dart port gets wrong *while looking correct*. Add to this list
when a completeness pass surfaces another.

| # | Where | JS behavior | Naive Dart | Consequence |
|---|---|---|---|---|
| 1 | `hashCode`'s `hash = hash & hash` | `ToInt32` — truncates to **signed 32-bit every iteration**. Not a no-op: `<<5` truncates, but the following `- hash` and `+ character` run in float64 and escape 32 bits again | Dart `int` is 64-bit; no truncation | **The hash itself diverges** on longer names |
| 2 | `%` | remainder, keeps the dividend's sign: `-7 % 5 == -2` | Dart `%` is always non-negative: `3` | sign flip. Use `remainder()` via a `jsMod` helper |
| 3 | `getUnit`'s `if(index && …)` | `index === 0` is **falsy** → branch skipped | `if (index != null)` enters at 0 | wrong negation |
| 4 | `getDigit`'s `number / Math.pow(10, ntn)` | **float64 division** | `~/` gives a different value | digit extraction fails |
| 5 | `charCodeAt` / `name.length` | UTF-16 **code units** | `runes` iterates code points | hash diverges on non-BMP input |
| 6 | `getNumber`'s `Array.from(name)` (states 1–9 only) | iterates **code points**, then `charCodeAt(0)` of each — the *opposite* of #5 | using `codeUnits` here | wrong sum on non-BMP. **The two eras iterate differently — do not share a helper** |
| 7 | Number → string in SVG | `4` → `"4"` (shortest round-trip) | `4.0` → `"4.0"` | layer-2 byte mismatch. Needs a `jsNum()` formatter |
| 8 | `colors: []` | `% 0` → `NaN` → `undefined` | `% 0` **throws** | crash where JS degrades |
| 9 | SVG `rx` on `<rect>` | clamped to `width/2` | Flutter `RRect` scales radii instead | wrong corner shape |
| 10 | SVG arc with radii too small (`a1,0.75 … 10,0` in beam's mouth) | spec **scales both radii up** until the ellipse fits (F.6.6) | `arcToPoint` does not correct | wrong or throwing path |
| 11 | `<filter>` with no `x/y/width/height` (marble) | region defaults to **-10%/-10%/120%/120%** of the bbox; the blur is clipped there | unclipped blur | halo beyond the reference |
| 12 | **A variant file existing ≠ the variant being reachable.** `avatar.js`'s dispatch is the authority, not the file listing | `avatar-turbulence.js` ships from v1.2.0 to v1.5.2 with an unchanging blob and is **never dispatched in any version** | porting it from the file tree | the project's heaviest rasterizer feature built for something no user could select |
| 13 | `eye` | dispatched **only at v1.2.0**; the file survives to v1.5.2 unreachable | assuming it lives as long as its file | a phantom variant in later states |
| 14 | `geometric` / `abstract` | **two different meanings by era** — distinct variants at v1.2.0; *unreachable* v1.3.0–v1.4.2 (fall through to `marble`); **deprecated aliases** `{geometric→beam, abstract→bauhaus}` from v1.5.3 | one enum value with one meaning | the same name renders three different things |
| 15 | unknown `variant` | falls back to the era's default — `geometric` at v1.2.0, `marble` from v1.3.0. Never throws | throwing on an unknown value | a crash where upstream degrades |

### Reachable-variant matrix (from `avatar.js` dispatch, not the file tree)

| State / tags | Reachable variants | Default | Aliases |
|---|---|---|---|
| v1.2.0 | geometric, abstract, beam, eye, marble | `geometric` | — |
| v1.3.0–v1.3.1 | marble, dome, moholy, beam, ring | `marble` | — |
| v1.4.0–v1.4.2 | marble, pixel, bauhaus, ring, beam, sunset, dome | `marble` | — |
| v1.5.3 → v2.0.x | pixel, bauhaus, ring, beam, sunset, marble | `marble` | geometric→beam, abstract→bauhaus |

**Eleven** variants are reachable across the whole history. `turbulence` is
reachable in **zero** states.

### Upstream divergence ledger

Suspected upstream defects and the **user's ruling** on each. Empty until the
first one is adjudicated. Never append a row the user has not seen and ruled on.

| Ref | Upstream `file:line` @ tag | What it does | Ruling | Decided |
|---|---|---|---|---|
| — | `avatar-marble.tsx:59` @ v2.0.x | first path's transform reads `properties[2].scale` where `properties[1].scale` is implied — a copy-paste slip. Fixing it changes the output | **not yet ruled** | — |

---

## Step 2 — boundary rule

**Identity: bit-exact reproduction of `boring-avatars`, in Dart, for any upstream
version.** The package owns everything that decides *what the image is*; the
consumer owns everything that decides *how it is used*.

The core is **three layers with declared seams**, all inside this package:

- **Mechanism / core (this package owns):**
  - **Layer 1 — data.** name → numbers/colors. Pure, no rendering, no Flutter
    import. Only *correct* against the pinned reference.
  - **Layer 2 — scene.** the resolved drawing description, backend-neutral. Both
    the SVG emitter and the rasterizer read it, so geometry knowledge exists in
    **one** place — two emitters deriving geometry independently is the
    divergence seed this seam exists to prevent.
  - **Layer 3 — raster.** deterministic software rasterization on a `Uint8List`.
    Owned here **because** delegating to `Canvas` makes the output depend on
    Skia-vs-Impeller, GPU, platform and Flutter version — the package could then
    make no claim about its own output at all.
- **Policy / consumer (injected, never assumed):** the palette (`colors`), the
  upstream `version` selector, `square`, the display size, widget layout and
  decoration, caching policy, and whether the caller wants pixels or an SVG
  string.

**The consumer seam is in-repo** (`lib/src/widget/` reaching the core through
the barrel) — plus, once published, real pub.dev dependents.

**Layer 1 is frozen on publish.** Once a version selector ships, its values are
a contract: changing them silently rewrites every existing user's avatar
identity. New upstream states are added as **new selector values only** — always
additive, never an edit to a shipped state.

**Cross-repo rules — currently N/A because nothing is published** (pub.dev
returns `NoSuchKey` for `boring_avatars`). The SDK-floor constraint, the
two-consumer signal, and the after-merge downstream loop all assume consumers
that cannot be seen from here. Re-read them at first publish, not before.

---

## Step 4 — proof method per layer

| Layer | Real proof | Bar |
|---|---|---|
| **1 data** | Node harness runs the **real upstream package at the tag** over N names × the state's variant set; the dumped values become a committed JSON fixture; Dart asserts against it | **Exact. No tolerance.** |
| **2 scene** | our emitted SVG string vs the string React actually renders at that tag | **Byte-identical**, excluding `useId()` mask ids (states 12+), which are runtime-random upstream and carry no behavior |
| **3 raster — regression** | our rasterizer vs **golden PNGs committed to this repo** | **0 diff, no exceptions.** Runs every `flutter test` |
| **3 raster — parity calibration** | our rasterizer vs a **real Chrome render** | interior/background **0**; antialiased edge pixels **≤1/255**. Run **manually** when the rasterizer changes, not per commit |
| **widget** | widget test asserting the produced `ui.Image` bytes, observed at the screen | as layer 3 |

**Why the raster gate is split.** A 0-diff gate against Chrome is a gate that
fails when *Chrome* updates while our code is untouched — and theflow forbids
lowering a threshold to clear a red build, so it would deadlock. The committed
golden is fully deterministic and stays 0-diff forever; the Chrome comparison
proves upstream parity and is run deliberately.

**Traps:**

- **A fixture that regenerates itself is not a proof.** The harness writes
  fixtures; the test only reads them. If a run can rewrite the expectation it
  just failed against, the gate is tautological.
- **Antialiasing coverage cannot be self-checked.** Comparing our rasterizer to
  our own supersampled reference measures our own arithmetic twice. Only the
  Chrome render is an outside opinion.
- **A green data-layer test says nothing about pixels**, and vice versa. Each
  seam needs its own fixture; passing layer 1 while layer 2 drifts produces a
  correct-numbers, wrong-picture avatar.

**Test-trust gate.** Turn the fix off and watch the test go red. To revert
temporarily use `git stash push -- <file>` / `git stash pop`, **never
`git checkout -- <file>`** (it destroys uncommitted work) — house rule.

---

## Step 5 — unconditional completeness triggers

The completeness pass runs **regardless of the enumeration-risk judgement**, and
the second *refuting* lens is bought, on:

- `lib/src/js/**` — the JS-semantics primitives shared by every variant
- `lib/src/variants/**` — every per-state value generator
- any change to a **published** version selector's layer-1 output

**Why these and not the rasterizer.** A rasterizer error is ±1/255 on an edge
pixel: invisible, and fixable later at no cost to anyone. A layer-1 error
produces a *different avatar*, and after publish it cannot be corrected without
changing the profile picture of every user of every app that depends on this
package. The test is reversibility, not difficulty — a three-line `getUnit` is
sacred and a thousand-line rasterizer is not.

`lib/src/raster/**` and `lib/src/widget/**` fall back to the normal
enumeration-risk judgement.

---

## Step 6 — behavior-describing surfaces

- **`CHANGELOG.md`** — pub.dev snapshots it at publish. Never edit a published
  entry; open a new version.
- **`README.md`** — the variant × upstream-state matrix lives here; it goes stale
  the moment a state is added.
- **Public doc-comments** — they ship verbatim as the pub.dev API reference.
  The `version` enum's doc-comments are the only place a user learns which
  upstream tags a selector value covers.
- **`docs/agents/theflow.md`** (this file) — the version ladder and the
  hidden-state list are *behavior descriptions*. A ported state that changes what
  a row says updates the row in the same change.
- **The divergence ledger** — append the ruling in the change that adjudicates
  it, never in a later sweep.
- **`docs/adr/`** — house format: `NNNN-kebab-case-title.md`, sequential.
  **No ADRs exist yet**, so **no area currently carries a record** — the filing
  step's check against that list is trivially empty today, and a first cluster is
  free to open a spine.
- **`CONTEXT.md`** — does not exist; created lazily by `/domain-modeling`.
- **`.pubignore`** — must exclude `docs/`, `.github/`, `CLAUDE.md`, `tool/`,
  `test/fixtures/`. A root `.pubignore` disables git-based file listing. The
  pub.dev archive cannot be un-published.
- **`example/`** — does not exist yet; becomes a gate the day it does.

**Record-worthy here.** No area has been re-litigated yet. The first candidates,
by construction, are the recurring shapes this port will produce: the JS↔Dart
semantics rules (if the hidden-state list starts needing a *rule* rather than
another row) and the rasterizer's spec-vs-Chrome arbitration. Promotion lands in
`docs/adr/`. **No project exception** to how spines link or where write-back
lands — the skill's defaults govern.

---

## Step 7 — gate matrix + watcher

**No CI gates.** Run these locally, in order — they are the only gates:

```
flutter analyze                                     # 0 issues
dart format --output=none --set-exit-if-changed lib test
flutter test                                        # includes fixture + golden PNG gates
flutter pub publish --dry-run                       # 0 warnings, clean tree
```

Run each gate **bare, never piped** — a pipeline's exit status is the last
command's, so `flutter test | tail -1 && commit` always commits.

- Branch → `feat|fix|refactor|test(<scope>): …` → PR (`Closes #issue`) →
  **rebase-merge** (linear history; zero merge commits on `main`).
- `flutter pub publish` is irreversible (retract only) — **the agent does not run
  it; the user does.**
- **Publish state is queried, not assumed:**
  `curl -s https://pub.dev/api/packages/boring_avatars`.

### The parity harness

`tool/parity/` — its own `package.json`, installing the **real upstream package
pinned to the tag being ported**. It generates the layer-1 JSON fixtures and the
layer-2 SVG strings into `test/fixtures/<state>/`.

The harness is a **tool, not a gate**: `flutter test` reads the committed
fixtures and never runs Node. That keeps the gate hermetic (no network, no npm
state) and makes a parity change appear as a **reviewable `git diff` of the
fixture** rather than as a silently different expectation. The harness is
permanent, not disposable — the version ladder is walked repeatedly, so every
state must be reproducible on demand.

### The upstream watcher (the one GitHub Actions workflow)

A scheduled job that files an issue when upstream moves. **It watches
`src/lib/` blob SHAs, not version numbers** — v1.9.0, v1.10.0, v2.0.1 and v2.0.2
changed nothing under `src/lib/`, so a release-triggered watcher would be mostly
noise. Of 28 tags, only ~16 are real work.

This is a **deliberate exception to the house "no CI" convention**: it is a
watcher, not a gate, so it cannot gate-block and its failure never blocks a
merge.

### Downstream loop

**N/A — nothing is published.** At first publish, derive consumers on the spot
(`for d in ../*/; do grep -l 'boring_avatars:' "$d/pubspec.yaml"; done`) and
never store the list here. Note that this package's releases are **additive by
construction** (a new state is a new selector value), so a release will normally
oblige consumers to do nothing — say so explicitly rather than leaving it
implied.

---

## War-story index

Empty — this repo has no incidents yet. Per-incident evidence goes in
[`lessons.md`](lessons.md), indexed by step. The hidden-state list above is
*pre-incident* enumeration, not evidence; move a row's story into `lessons.md`
the first time it actually catches a defect, and cite the issue number.
