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

Already present: `lib/src/version.dart` (`BoringAvatarsVersion` — one value per
*supported* upstream release, `v1_6_1` as of 0.1.0) and `lib/src/variant.dart`
(`BoringAvatarsVariant` — the six drawn variants plus the two deprecated
aliases), with alias resolution and the degrade-to-`marble` parser that mirror
upstream's `avatar.js`.

`lib/src/variants/` holds each variant's scene builder (**sacred**) and
`lib/src/raster/` the deterministic software rasterizer. As of #37 they hold
`pixel` and `ring`. `raster.dart` fills two kinds of shape through a
rounded-rect mask — axis-aligned rectangles in closed form, and polygons by a
scanline integrator under the **nonzero** winding rule — `path.dart` turns SVG
path data and circles into those polygons at a stated flattening tolerance, and
`scene_raster.dart` bridges scene to pixels by reading nodes **by attribute
name**. Strokes, gradients and filters arrive with the variants that need them,
and everything unimplemented throws.

**Rects keep their own closed-form integrator on purpose.** The polygon path
quantises the vertical direction, and a horizontal edge is exactly where that is
worst; a box-overlap product has nothing to approximate. The two are tied
together by a test rather than left to drift — `raster_path_test.dart` renders
the same fractional rectangle both ways.

`lib/src/scene/` holds the backend-neutral drawing description and
`lib/src/svg/` serialises it. The scene carries its attributes **ordered** —
see hidden-state #18 — so the SVG emitter can reproduce upstream's bytes while
the rasterizer reads the same nodes by name.

`lib/src/js/` holds the sacred surface: `utilities.dart` (upstream's six
reachable utilities) and `js_number.dart` (the JS arithmetic and string
semantics Dart does not share — `jsMod`, `toSigned32`, `jsNum`,
`jsParseIntHex`, `jsSubstr`). **`getModulus` and `getAngle` are deliberately not
ported** — upstream exports both and no component imports either, and
`getModulus` is not called by the other utilities either. Same judgement that
closed the `turbulence` variant: unreachable upstream code has no output to
reproduce.

**Variant resolution does not vary by version** across the whole supported
range, so it is not parameterised by one — verified by reading `avatar.js` at
every tag from 1.6.1 to 2.0.2. Valid **as long as that stays true**; a release
that changes the dispatch roster makes resolution version-dependent and this
seam has to move.

Public surface is the barrel `lib/boring_avatars.dart`.

| Module (`lib/src/`) | Layer | Role |
|---|---|---|
| `js/` | **1 data** | JS-semantics primitives — `hashCode`, `getNumber`, `jsMod`, `toSigned32`, `getDigit`, `getBoolean`, `getUnit`, `getRandomColor`, `getContrast`. **Sacred.** |
| `variants/<name>.dart` | **1 data** + **2 scene** | per-variant value generation and its scene. Flat while one upstream state is supported; a second state that *draws differently* is what would split it. **Sacred.** |
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

### The upstream version ladder — historical, and no longer the port order

**This table is source archaeology, not the plan.** It records what the 28 git
tags contain, which is how the scope boundary at v1.6.1 was decided. The **port
order is in "The states in scope" below**, which groups by *output* — decided by
the user on 2026-07-29 and collapsing the eight in-scope selectors to three.

Read this table when you need to know what a tag holds. Do not read a row as a
release: rows 11–17 map to only **two** of the three shipped selectors, and row
15 (v1.11.0) ships in none of them.

28 tags collapse to **17 distinct source states**.

*(Corrected from 16 while working #1: row 15 below held two states, not one —
v1.11.0's components differ from v1.11.1's. Verified by blob SHA. And source
identity turned out to be the wrong grouping criterion entirely — see below.)*

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

**Row 15 is the one this table gets wrong on its own terms.** It reads as an
ordinary state; rendering it shows v1.11.0 leaks its props onto the `<svg>`
element (hidden-state #37). A blob diff cannot see that, which is the reason the
grouping criterion moved from source to output.

**Eleven** reachable variants — six current (`marble`, `beam`, `pixel`,
`sunset`, `ring`, `bauhaus`) and five historical (`geometric`, `abstract`,
`eye`, `dome`, `moholy`). `turbulence` ships a file but is **never dispatched**
— see hidden-state #12 and the reachable-variant matrix.

**States 16→17 and within 17, cleared concerns:** `v2.0.0` vs `v2.0.1`
`index.tsx` is byte-identical (only `types.ts` moved, which has no runtime
effect); `2.0.4` **changes** the default `size` from `40` to `'40px'`. Not adds —
`avatar.js` already destructures `size = 40` at v1.6.1 (corrected in #37; the
earlier wording implied there was no default before 2.0.4). What moves is the
value and its unit. Either way it is **consumer policy under this project's
boundary rule**, not part of the version state — the caller always supplies size
here. Valid **as long as `size` stays consumer-owned**; if the package ever
renders at an implicit default, 2.0.3/2.0.4 becomes its own state.

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

### Scope boundary — the ladder starts at v1.6.1, not v1.2.0

**Decided by the user on 2026-07-28**, superseding the earlier "walk the whole
history from v1.2.0" call. A product judgement, theirs to reverse. What they
were shown: weekly npm download share per state, and the cost of the second hash
era.

`v1.6.1` is where `getNumber` is replaced by `hashCode`. Cutting there is a cut
along an **algorithm boundary**, not along a popularity threshold — the coverage
number is a consequence, not the criterion.

| Starting at | Coverage of weekly npm downloads | Hash functions | Reachable variants | Tag states |
|---|---|---|---|---|
| v1.2.0 | 99.79% | 2 | 11 | 17 |
| **v1.6.1** | **99.64%** | **1** | **6** | **8** |

The nine states below v1.6.1 total **0.14%** — roughly 360 downloads a week
across all of them, of which `v1_6_0` alone is 19. Supporting them would pull in
`getNumber`, whose `Array.from` iterates **code points** where `hashCode`'s
`charCodeAt` iterates **code units** — the two eras walk a string in opposite
directions, so they can share no helper (hidden-state #6). It would also add a
second `getContrast` return format (`'black'`/`'white'` vs hex).

**They are not deferred, they are out of scope.** No placeholder issue exists and
none should be opened: a feature at 0.14% that nobody has requested is a note
here, not a tracker entry. Re-entering scope is a fresh decision by the user.

### The states in scope — grouped by output, not by source

**Decided by the user on 2026-07-29**, superseding "one selector per distinct
source tree". A product judgement, theirs to reverse. What they were shown: the
four measurements below, and the fact that grouping by source gives 8 selectors
where grouping by output gives 3.

> **"꼭 버전마다 하나씩 만드는건 아니고 사용자 입장에서 결과물이 같으면 묶어서
> 하는거임. 문법은 상관없어. 결과물이 중요."**

The criterion is now: **two upstream versions share a selector when a caller
gets the same thing out of them.** Source identity is neither necessary nor
sufficient — `1.11.1` and `1.11.2` have different source trees and identical
output, while `1.11.0` shares `1.11.1`'s intent and differs in what it emits.

**Which selector covers which upstream versions is in `CLAUDE.md`, principle 3,
and only there.** Three selectors, `v1_6_1` / `v1_7_0` / `v1_10_1`, one per
release. This section holds the evidence for that grouping; the mapping itself
has one home so a new upstream release is one edit and not three.

**Measured, not read — and the measurement is re-runnable.** `tool/versions/`
installs every in-scope npm release side by side and groups them by what they
render:

```bash
cd tool/versions && npm install && npm run group
```

Fifteen versions × six variants × four names, grouped under four progressively
looser readings of "the same result", plus a report of *which variant* each
group boundary turns on. Keeping it is the same rule as `tool/parity`: the
release plan is a claim about measurement, and a claim whose evidence cannot be
re-run is one nobody can check.

| What is compared | Groups |
|---|---|
| the raw bytes | 6 |
| internal ids normalised (`id`, `url(#…)`, `mask`, `filter`) | 4 |
| ids normalised **and** `<title>` set aside | 3 |
| ids normalised, `title` forced on | 3 |

And the `v1_7_0` → `v1_10_1` boundary is one variant wide: rendering both eras
over six names, `pixel` differs on **6 of 6** and `marble`, `beam`, `sunset`,
`ring`, `bauhaus` are byte-identical on all of them.

**`1.11.0` is skipped — it is a broken release.** It spreads its own props onto
the `<svg>` element, so the markup carries junk attributes no other version
emits:

```
<svg … width="80" height="80" colors="#92A1C6,#146A7C,#F0AB3D,#C271B4,#C20D90"
     name="Clara Barton" …>
```

Measured on all six variants. Upstream fixed it in `1.11.1` by destructuring the
props it consumes. Under the output criterion it is a distinct state and would
otherwise need its own selector — supporting it would mean **reproducing the
junk attributes**, since a selector promises what that version emits.
**Decided by the user on 2026-07-29** to skip it: `v1_10_1` covers `1.11.1`
onward, and a caller pinned to `1.11.0` is told it is unsupported rather than
given a neighbouring version's output. If that ruling is reversed, the state is
`v1_10_1` plus the leaked attributes and nothing else.

**`1.8.0` and `1.9.0` need no selector of their own** — they are inside
`v1_7_0`. Independently, **their npm tarballs contain no JavaScript at all**
(`main` points at `build/index.js`, which is absent — verified by installing
them), so no user has ever run them.

**Generated ids are not a grouping boundary, and they are not our problem at
`v1_6_1`.** From 1.8.0 upstream names its mask with React's `useId()`, whose
value depends on the element's position in the render tree — the *same* avatar
comes out `:R0:` alone, `:R3:` as the third child, `:R2:` after a `<span>`.
Measured. What that changes is **two characters of an internal reference**; the
shapes, coordinates and fills are byte-identical across all of them, so the same
name always yields the same avatar on every page. At `v1_6_1` the question does
not arise: every id is a literal, and the one that must not collide already
carries the name (`gradient_paint0_linear_ClaraBarton`) while the one that does
collide is a mask identical for every avatar of that variant.

**A correction this replaces.** An earlier note here claimed the state count
differs per layer (2 values / 3 bytes / 2 pixels) and that all eight selectors
should be kept "so someone pinned to 1.8.0 can name it". Keeping a selector that
produces byte-identical output to its neighbour buys a name and costs a release;
the user ruled that the name is not worth it.

Everything else in the range is React plumbing that leaves no mark on the
drawing — `useId()` mask ids (1.8.0), prop spreading (1.11.0), destructuring
defaults with identical values (1.11.1), the `prefix__filter0_f` →
`filter_${maskID}` rename in `marble` (1.10.2), and the TypeScript rewrite
(2.0.0).

So the eight selector values map to **two render paths and three byte paths**.
Keep all eight — someone pinned to 1.8.0 must be able to name it — but do not
build eight implementations.

### Hidden-state list

Read this **before** writing any data-layer code. These are the JS/SVG semantics
a first-principles Dart port gets wrong *while looking correct*. Add to this list
when a completeness pass surfaces another.

| # | Where | JS behavior | Naive Dart | Consequence |
|---|---|---|---|---|
| 1 | `hashCode`'s `hash = hash & hash` | `ToInt32` — truncates to **signed 32-bit every iteration**. Not a no-op: `<<5` truncates, but the following `- hash` and `+ character` run in float64 and escape 32 bits again | Dart `int` is 64-bit; no truncation | **The hash itself diverges** on longer names |
| 2 | `%` | remainder, keeps the dividend's sign: `-7 % 5 == -2` | Dart `%` is always non-negative: `3` | sign flip — but **inert at v1.6.1**, the same way #4 is. `hashCode` is `Math.abs`'d and every caller passes it or a positive multiple, so swapping `jsMod` for Dart `%` breaks no fixture assertion; only the helper's own unit test pins it. Keep `remainder()` so the port is already right the day a negative appears |
| 2b | `%` with a **zero divisor** | `NaN`, and everything downstream of it becomes `undefined` | Dart **throws** | reachable twice over: an empty palette (`range == 0`) *and* `pixel`'s `hash % i` at `i == 0`. `jsMod` deliberately rejects zero; callers that can see one use `jsModOrNull`, which returns `null` — the Dart shape of `NaN` |
| 3 | `getUnit`'s `if(index && …)` | `index === 0` is **falsy** → branch skipped. Measured: `getUnit(645088871, 10, 0)` and `getUnit(645088871, 10)` both give `1` | `if (index != null)` enters at 0 | wrong negation. **No caller passes 0 today**, so the fixture had to be widened to index `0` deliberately — until it was, a mutation removing the guard passed the whole suite |
| 4 | `getDigit`'s `number / Math.pow(10, ntn)` | **float64 division** | `~/` gives a different value | **for non-negative input, nothing.** Writing `n = q·10^k + r`, the float quotient is `q + f` with `0 ≤ f < 1`, so `floor((q + f) % 10) == q % 10` always — verified over 11.2M reachable pairs. They diverge only on **negative** input (`getDigit(-15, 1)` is `-2` float, `-1` integer — measured). Valid **as long as `getDigit` only ever receives `hashCode` output and multiples of it**. Keep the float division: it is what upstream writes, and `js_primitives_test.dart` pins the negative cases so a `~/` mutation *is* caught |
| 5 | `charCodeAt` / `name.length` | UTF-16 **code units** | `runes` iterates code points | hash diverges on non-BMP input |
| 6 | `getNumber`'s `Array.from(name)` (states 1–9 only) | iterates **code points**, then `charCodeAt(0)` of each — the *opposite* of #5 | using `codeUnits` here | wrong sum on non-BMP. **The two eras iterate differently — do not share a helper** |
| 7 | Number → string in SVG | `4` → `"4"` (shortest round-trip) | `4.0` → `"4.0"` | layer-2 byte mismatch. Needs a `jsNum()` formatter |
| 8 | `colors: []` | `% 0` → `NaN` → `colors[NaN]` → `undefined`. **Then it splits by variant:** five variants put that straight into a `fill`, and React drops the attribute; **`beam` throws**, because it hands the same `undefined` to `getContrast`, which calls `.slice` on it | `% 0` **throws** everywhere | crash where JS degrades — *and* silent success where JS crashes. "Empty palette degrades" is true per variant, not in general (measured at v1.6.1, all six variants × 20 names) |
| 9 | SVG `rx` on `<rect>` | clamped to `width/2` | Flutter `RRect` scales radii instead | wrong corner shape |
| 10 | SVG arc with radii too small (`a1,0.75 … 10,0` in beam's mouth) | spec **scales both radii up** until the ellipse fits (F.6.6) | `arcToPoint` does not correct | wrong or throwing path |
| 11 | `<filter>` with no `x/y/width/height` (marble) | region defaults to **-10%/-10%/120%/120%** of the bbox; the blur is clipped there | unclipped blur | halo beyond the reference |
| 12 | **A variant file existing ≠ the variant being reachable.** `avatar.js`'s dispatch is the authority, not the file listing | `avatar-turbulence.js` ships from v1.2.0 to v1.5.2 with an unchanging blob and is **never dispatched in any version** | porting it from the file tree | the project's heaviest rasterizer feature built for something no user could select |
| 13 | `eye` | dispatched **only at v1.2.0**; the file survives to v1.5.2 unreachable | assuming it lives as long as its file | a phantom variant in later states |
| 14 | `geometric` / `abstract` | **two different meanings by era** — distinct variants at v1.2.0; *unreachable* v1.3.0–v1.4.2 (fall through to `marble`); **deprecated aliases** `{geometric→beam, abstract→bauhaus}` from v1.5.3 | one enum value with one meaning | the same name renders three different things |
| 15 | unknown `variant` | falls back to the era's default — `geometric` at v1.2.0, `marble` from v1.3.0. Never throws | throwing on an unknown value | a crash where upstream degrades |
| 20 | **The two backends disagree on a malformed colour** | the palette is consumer policy and upstream validates none of it, so `#F00`, `red`, `rgb(…)`, `#RRGGBBAA` all reach the port. The SVG emitter passes them through and a browser draws them; the rasterizer parses `#RRGGBB` only | letting the rasterizer guess, or letting it silently skip | the same input yields a correct SVG and a blank raster — the two-backend divergence the scene seam exists to prevent. Today the rasterizer returns `null` and draws nothing; a sign is rejected outright, since `int.tryParse('+12345', radix: 16)` succeeds and would turn punctuation into a plausible colour |
| 21 | SVG `rx` / `ry` clamping | clamped **independently** — `rx` to width/2 and `ry` to height/2 — so a non-square rect gets **elliptical** corners | one circular radius | wrong corner shape. Inert while every mask is square (all six variants); `beam`'s eye rects are `1.5 × 2` with `rx=1`, which wants rx 0.75 / ry 1 — an ellipse. Valid **as long as only square masks reach the rasterizer** |
| 22 | `mask-type` | `pixel` declares `mask-type="alpha"`; **the other five declare nothing**, which in SVG means a *luminance* mask | treating every mask as alpha | wrong everywhere the mask shape is not white. Inert today — all six fill the mask `#FFFFFF`, where luminance and alpha both come to 1 — and the rasterizer now **throws** rather than assuming, so the day one is not white it fails loudly |
| 24 | **Abutting shapes vs stacked shapes** | two half-covering rects meeting inside one pixel should fill it — an exact rasteriser gives alpha 255 | source-over compositing, which gives **192** | source-over is right for shapes *stacked* on each other and wrong for shapes *abutting* each other. Inert for `pixel` — its tile edges are integer-aligned and `_checkViewBox` refuses any target that is not 1:1 — and inert for `ring`, which abuts along `y=45` in four places but at the enforced 90×90 target that is a pixel boundary. Live for `marble`, `bauhaus` and `beam`, which both stack and abut. Valid **as long as every drawn edge falls on a pixel boundary** |
| 23 | Rounding when shapes overlap | a browser draws each shape of a plain display list onto an **8-bit** surface, so it rounds once per shape too | assuming either model without measuring | **corrected in #37 — the row used to claim the opposite of what the code does.** `blend()` reads back the byte the previous shape wrote, so k stacked shapes round k times, and that is what matches the reference. Measured drift against a single float accumulation, over 1.2M stacks of 2–9 opaque shapes: **2/255 premultiplied** (16/255 straight at negligible alpha — #29, not a real difference). `pixel`'s tiles never overlap; `ring` stacks nine; marble, bauhaus and beam stack two to four. Valid **as long as no group opacity or filter introduces an offscreen layer** — `marble` has one, and the seam throws on it |
| 18 | **Attribute order is per call site, not per element** | React emits props in the order the JSX author wrote them, so one element takes several orders: `circle` is `cx cy r fill` in `ring` and `cx cy fill r transform` in `bauhaus`; `rect` and `path` each take five or more | giving the emitter a canonical order per element | every render whose order differs — silently, since a browser does not care about attribute order. The scene node therefore carries **ordered** attributes and the rasterizer reads them by name |
| 19 | React's serialisation details | no self-closing tags (`<rect …></rect>`, never `<rect/>` — zero `/>` in 480 renders); no whitespace between elements; `'` escapes to **`&#x27;`** not `&apos;`; tabs, newlines and non-ASCII pass through; element names keep camel case (`linearGradient`) while some attributes hyphenate (`mask-type`, `stop-color`) and others do not (`maskUnits`, `stdDeviation`) | any of the plausible alternatives | byte-level layer-2 failure that renders identically on screen. The hyphenation split is **a list, not a rule** — callers supply the emitted spelling |
| 17 | **`pixel`'s first tile is never filled** | `avatar-pixel.js` builds its 64 colours with `getRandomColor(numFromName % i, …)` from `i == 0`. `hash % 0` is `NaN`, so `colors[NaN]` is `undefined` and the first `<rect>` ships **with no `fill` attribute at all** | filling tile 0 from the palette | wrong on **100% of pixel renders**, every name, every palette — including the defaults. Distinct from #8: that is a degenerate *palette*, this is a degenerate *loop index*, and it needs no unusual input to fire. Committed fixture `svg.json` → `pixel\|upstream-default\|upstream-default` shows it |
| 16 | `<title>` | `1.6.1` emits `<title>{name}</title>` **unconditionally and has no `title` prop at all** — there is no way to switch it off; the prop arrives in `1.7.0`, defaulting off | giving `v1_6_1` a `title` parameter, or implementing the prop-gated form everywhere | `v1_6_1`'s SVG bytes are wrong while its pixels are right — a layer-2 failure a pixel test cannot see |
| 25 | **SVG arc flags are single characters and may be packed against the number after them** | `ring` writes `a32 32 0 10-64 0`, where `10` is *two flags* — large-arc 1, sweep 0 — and `-64` is the endpoint | a tokeniser that scans numbers uniformly reads ten, then takes `-64` as the sweep flag | a plausible wrong picture that throws nothing. Upstream writes this form in four of `ring`'s six arcs, so it is not hypothetical. Pinned by `raster_path_test.dart` — two `d` strings differing in one byte must come out mirrored |
| 26 | **The drawing space is per variant, and is not the display size** | `ring`'s viewBox is **90**; the other five are 80. `size` still only reaches `width`/`height` | assuming one canvas constant for the package | the rasterizer refuses a target that does not match the viewBox, so this surfaces as a throw rather than a squashed avatar — but the *goldens* have to be generated at 90, and a per-package `size` in the golden tool silently produces the wrong reference |
| 27 | **Chrome's own curves are inset from true circular geometry**, by an amount that depends on the radius | measured directly: `<circle r=20>` loses 1.69 px² of area (0.0135 px inward), `r=23` loses 11.95 (0.083 px), `r=40` loses 32.03 (0.127 px); an `<path>` half-disc of r=38 loses 17.32 (0.145 px). An integer-edged `<rect>` is **exact** and a fractional one is within 0.003 px | treating a Chrome render as ground truth for curve geometry | the recorded ≤1/255 calibration bar is **unmeetable for any curved edge** — not because our coverage is wrong but because Chrome's is. Ours reproduces the same shapes to 0.02 px². **Pending the user's ruling** — see Step 4 |
| 28 | **F.6.5's centre square root goes negative when a chord rounds past the diameter** | for an *angled* chord equal to the diameter, `lambda` can compute as exactly `1.0` — so F.6.6's correction does not fire — while `(rx²ry² − …)/…` lands at `-1.3e-16`. Measured at `r = 1/7` | `sqrt` of the raw value | every vertex becomes `NaN` and the render dies in `ceil()`. Inert for `ring`, whose chords are all **horizontal** (the radicand is then exactly zero every time) — which is why a mutation removing the clamp survived the whole suite until a case was searched for. Valid **as long as arcs stay axis-aligned**; `beam` and `marble` are the ones to re-check |
| 29 | **Straight-alpha RGB is meaningless where alpha is small** | both our buffer and a PNG store *straight* alpha, so a pixel we cover 3/255 carries the full undiluted colour while Chrome's uncovered pixel carries zero | comparing the two backends channel by channel as stored | a 3/255 disagreement reads as a delta of **240** and a calibration run fails on a difference nobody could see. Compare **premultiplied** — `tool/calibrate/compare.dart` does. The same trap bites any comparison of our own arithmetic against itself: row #23's drift measures 16 straight and 2 premultiplied |
| 30 | **A container's attributes change the picture as much as a shape's** | `beam` wraps its whole face in `<g transform="translate(4.5 4.5) rotate(-9 18 18)">`; `<svg>`, `<g>`, `<defs>` and `<mask>` all carry attributes | validating only the elements you know how to *draw*, and walking through containers unchecked | the face renders 4.5 units off and unrotated with **nothing thrown** — the exact failure `UnsupportedSceneError` exists to prevent, one level up from where it was being checked. Found by the #37 completeness pass; every element on the walk now carries an allow-list |
| 31 | **An unreadable `fill` is not the same as an absent one** | upstream omits `fill` to mean "no paint" (#17), and writes `fill="url(#…)"` to mean a gradient | letting both fall through to "the colour did not parse, so draw nothing" | **every `sunset` render rasterised to a blank square**, silently, and a golden made from one would have frozen the blank as correct. A `url(...)` fill now throws. Distinct from #20, which is the *caller's* palette and keeps its recorded behaviour — this one is upstream's own output |
| 32 | **Content outside the masked group is drawn by a browser, not dropped** | `<g mask>` masks its children; a sibling shape renders **unmasked** | silently collecting only what sits under the mask group | a picture the reference does not produce, with no error. Inert across all six variants — every drawn element is inside `<g mask="url(#…)">` — but the seam now throws rather than dropping. **This inverted an assertion #36 had pinned the other way**; both readings agreed on every real scene and only one agreed with SVG |
| 33 | **A mask applies to the composited group, not to each shape** | SVG composites a `<g mask="…">`'s children, *then* scales the result's alpha by the mask | folding the mask into every shape's own coverage | the mask is applied once per shape. Two opaque shapes stacked on a pixel a mask half-covers come out at **192** where one of them gives 128 — 64 levels of alpha against a bar of one. Inert for `pixel` and `ring`, whose mask-edge pixels are reached by at most one shape; **live for `marble`, `bauhaus` and `beam`**, which each lay a background rect under a shape crossing the mask edge. Fixed in #37; the fix moved 8 pixels of `pixel`'s goldens, all fully transparent, all straight-RGB-only (#29) |
| 34 | **`z` ends a subpath; what follows starts a new one** | `M0 0h10v10H0zh10v10` is two subpaths from the same origin | treating `z` as only a "return to start" and leaving the contour open | the two weld into one polygon — measured 75 units where SVG gives 100. Inert at v1.6.1: across the 18 distinct `d` strings in all 600 renders, `z` is always the **last** command, so no fixture could catch it. Valid **as long as that stays true** — a multi-subpath `d` in a later upstream version makes it live |
| 35 | **A `<mask>` carries a clip region, units, and an id that is referenced** | `maskUnits` decides whether `x/y/width/height` are user units or bbox fractions; the region clips the mask shape; `mask="url(#id)"` has to name a mask that exists | reading only the child shape | three silent wrong pictures: a region that cuts its own shape renders uncut, `objectBoundingBox` reinterprets every number, and a dangling reference renders masked where a browser renders unmasked (SVG 2) or not at all (SVG 1.1). All inert at v1.6.1 — one mask, `userSpaceOnUse`, region equal to the shape — and all three now throw |
| 37 | **`1.11.0` spreads its own props onto the `<svg>` element** | `<svg … colors="#92A1C6,#146A7C,…" name="Clara Barton">` — the destructuring keeps `colors` and `name` in `...otherProps`, so React writes them as DOM attributes | assuming a "prop spreading" changelog entry leaves the output alone | a whole upstream release whose markup differs from every neighbour on **all six variants**. It is the reason `1.11.0` is skipped rather than folded into `v1_10_1`; fixed upstream in `1.11.1`. Found by grouping rendered output, which a source diff had classified as inert |
| 36 | **The `largeArc` flag is dead-valued across the entire corpus** | every arc upstream writes has a chord equal to its (corrected) diameter, so F.6.5's centre offset is exactly zero and `sign = largeArc != sweep` multiplies a zero | assuming a passing suite exercises the endpoint→centre conversion | the hardest branch of the arc code is unreachable from any real input — two mutants on the sign rule survived the whole suite. Not a defect and not fixable by upstream data; the case is **constructed** in `raster_path_test.dart` (chord 20 on radius 15, minor segment vs major), with Chrome confirming which of the four shapes each flag pair draws |

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
| **1 data — utilities** | `tool/parity` imports `utilities.js` **straight from the pinned reference tree** and calls the real functions; the values become `test/fixtures/<version>/utilities.json` | **Exact. No tolerance.** |
| **1 data — per-variant values** | **Not directly observable.** No component exports its generator — `generateData` / `generateColors` are module-private in all six — so per-variant values are proved *transitively* through layer 2, where every value that reaches the drawing appears as an attribute | via layer 2 |
| **2 scene** | our emitted SVG vs `test/fixtures/<version>/svg.json`, rendered from the **real npm package** through `react-dom/server` | **Byte-identical**, excluding generated ids (`useId`, `prefix__…`), which are internal references. **`<title>` is not excluded** — see hidden-state #16 |

**What the normalisation excludes is excluded on *both* sides.** `id="…"`,
`url(#…)` and `mask="…"` are erased from our output and from the fixture, so
"byte-identical" says nothing about any of them — mutating `mask__ring` to
`mask__pixel`, or a group's reference to a dangling one, left the whole suite
green. That exclusion is right for the ids `useId` generates from 1.8.0, and
buys nothing at 1.6.1 where every id is a **literal in the JSX**. Since #37 the
harness also records them *unnormalised* (`maskIdentifiers`), and the parity
tests assert the literals directly. A normalisation is a hole in the gate; it
needs its own assertion beside it.

**Every consumer-facing prop needs its own renders, or it is inference.** The
matrix runs at one `size` and one `square`, which is right — but a prop the
matrix never varies is a prop nobody has compared to upstream. `size` has
carried a `sizePassthrough` section since #33 for exactly this reason; `square`
did not until **#37**, and until then `pixel` had shipped with `square`
asserted only against itself *and a golden committed for it*. `svg.json` now
carries `squareRenders` — six variants × two names × five palettes.
| **3 raster — regression** | our rasterizer vs **golden images committed to this repo** (raw RGBA under `test/goldens/`, not PNG — no encoder in the loop, so a decoder change cannot move a golden) | **0 diff, no exceptions.** Runs every `flutter test` |
| **3 raster — parity calibration** | our rasterizer vs a **real Chrome render** | interior/background **0**; antialiased edge pixels **≤1/255**. Run **manually** when the rasterizer changes, not per commit |
| **widget** | widget test asserting the produced `ui.Image` bytes, observed at the screen | as layer 3 |

**Why the raster gate is split.** A 0-diff gate against Chrome is a gate that
fails when *Chrome* updates while our code is untouched — and theflow forbids
lowering a threshold to clear a red build, so it would deadlock. The committed
golden is fully deterministic and stays 0-diff forever; the Chrome comparison
proves upstream parity and is run deliberately.

**The calibration harness is `tool/calibrate/`.** `compare.dart` emits the SVG
our own emitter produces, `render.mjs` drives headless Chrome over it and
decodes the PNG, then `compare.dart` reports the diff. Feeding Chrome *our*
document is deliberate: a harness that rebuilt the SVG independently could pass
while the two backends disagreed about what to draw.

**⚠ The ≤1/255 edge bar has never been met, and #37 is the first run of it.**
Recorded in #33 and executed for the first time in #37 — including on `pixel`,
which was merged in #36 without it. Measured, comparing premultiplied
(hidden-state #29):

| Case | Interior mismatches | Worst edge delta |
|---|---|---|
| `pixel-clara-default` | **0** | 71/255 |
| `ring-clara-default` | **0** | 66/255 |
| `ring-alice-pair` | **0** | 101/255 |
| `ring-clara-square` | **0** | 66/255 |

**Interior 0 is the part that matters and it holds**: every solid region matches
Chrome exactly, which is what proves the arc sweep directions, the paint order
and the nine-slot colour map. The edge deltas are all on curves, all in one
direction, and hidden-state #27 measures why: **Chrome's circles are up to
0.13 px small and ours are not**. Matching the bar would mean reproducing a
browser's Bézier approximation error.

**This is a decision for the user, not the agent** — it changes a recorded bar,
and theflow forbids moving a threshold to clear a red run. Until it is ruled on,
the bar stands as written and this note is the honest record that it fails.

**Traps:**

- **A fixture that regenerates itself is not a proof.** The harness writes
  fixtures; the test only reads them. If a run can rewrite the expectation it
  just failed against, the gate is tautological.
- **The two fixtures come from two different sources and can disagree.**
  `utilities.json` is imported from the git tag; `svg.json` is rendered from the
  npm package — and npm `1.8.0`/`1.9.0` shipped no JavaScript at all, so their
  fixtures must come from the tag. `test/fixtures_test.dart` cross-checks the
  two against each other (marble's background fill against `colors[hash %
  range]`) rather than assuming they match.
- **A measurement can point at the wrong element.** The first `<rect>` in a
  marble render is the *mask's* rect, not the background — reading it made 71 of
  80 cross-checks look like failures until the probe was corrected. When a check
  fails wholesale, suspect the check.
- **Antialiasing coverage cannot be self-checked.** Comparing our rasterizer to
  our own supersampled reference measures our own arithmetic twice. Only the
  Chrome render is an outside opinion — **but it is not the only one, and for
  curves it is the weaker one.** The area of a disc is πr² whoever computes it,
  so summing coverage over a flattened circle is an outside opinion that needs
  no browser and no tolerance negotiation. `raster_path_test.dart` uses it, and
  it is what established that Chrome is the less accurate of the two (#27).
- **A straight-alpha comparison misreads itself.** See hidden-state #29: the
  same pixel differs by 3 or by 240 depending on which representation you
  subtract in. Premultiply first.
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

`tool/calibrate/` is the layer-3 equivalent — it drives real Chrome and reports
the pixel diff. Same shape, same rule: a tool, run deliberately. See Step 4.

`tool/milestones/sync.mjs` renders the GitHub milestone descriptions from
`CLAUDE.md`'s release table. **Run it whenever that table changes.** A milestone
description has to carry the version list — "see CLAUDE.md" is useless to
someone browsing GitHub — so the mapping lives in two surfaces whether or not we
want it to; generating one from the other is what keeps them together. The
authored half (what ships in a release, why `1.11.0` is excluded) lives in the
tool's `NOTES`, so regenerating never destroys it.

It reports three kinds of drift, each verified to fire: a version list that no
longer matches, a milestone that exists with no row in the table, and a row with
no note. Dry-run by default; `--apply` writes.

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

### Release plan — one release per **output state**

**A release declares support for every upstream version that produces the same
thing, and is cut as soon as that support is verified.** The unit is the output
state, not the version number.

**Decided by the user on 2026-07-29**, replacing "one release per upstream
version" (2026-07-28), which itself replaced "batch everything into 1.0.0".
Both earlier plans are recorded so their reasoning is not re-proposed.

**What each release declares support for is in `CLAUDE.md`, principle 3, and
only there.** Below is what each one has to *do* — the mapping is not repeated.

| Release | The work that earns it |
|---|---|
| `0.1.0` | everything: harness, primitives, scene, all six variants, the public SVG surface |
| `0.2.0` | the `<title>` gate (hidden-state #16) — **one change** |
| `0.3.0` | `pixel`'s second colour-index path — **one change**, and the only one in scope where the drawing moves |

**Why this collapsed from eight releases to three.** The previous plan gave
`1.8.0`, `1.10.2`, `1.11.0` and `1.11.1` their own releases whose stated work was
"verification only" — they existed so a caller could *name* their pinned version,
not because anything rendered differently. The user ruled that a name that buys
no different output does not earn a release. Five releases' worth of README,
CHANGELOG, fixture generation and publish ceremony disappear with them.

**What was kept from the earlier plan.** The two rules below are unchanged and
matter more now, not less, because each release covers more versions:

- **Every release re-proves the additive invariant.** A user pinned to `v1_6_1`
  must not have their avatars move because `0.3.0` touched `pixel`.
- **Per-version fixtures are still generated for every covered version**, not one
  per release. Collapsing the *releases* does not license collapsing the
  *evidence* — the `<title>` divergence was found precisely because 1.6.1 and
  1.7.0 were rendered separately, and a plan that rendered one and claimed four
  would have missed it.

**`1.11.0` is not in the table, and that is deliberate** — see "The states in
scope" above. It emits junk attributes no other version does.

**`0.1.0` ships SVG only.** Decided by the user on 2026-07-29: the public surface
is a function returning the SVG string, which is what upstream itself produces
and is a complete product on its own. The widget and its device-pixel
rasterisation (#58, #59) follow in a later release rather than blocking the first
one. A Flutter caller therefore needs a third-party SVG renderer for `0.1.0`, and
the package's determinism guarantee applies to the raster path only — say so in
the README rather than leaving it implied.

**"Supporting a version" is a verification claim, not necessarily new rendering
code.** `0.2.0` and `0.3.0` each change one thing; the rest of what earns them is
generating every covered version's fixtures and proving the existing renderer
reproduces them. That is the deliverable, and it is why they are releases at all.

*(An earlier revision of this section argued the opposite of the current plan —
that a version needing no new code still earns its own release, because the
product is verified version coverage. That reasoning stands for the **work**; it
was rejected for the **release boundary**, since a release the caller cannot
distinguish from its neighbour is a name rather than a version. Kept here so the
argument is not re-made from scratch.)*

`flutter pub publish` is run by the **user**, never the agent — it cannot be
undone. Confirm the result with
`curl -s https://pub.dev/api/packages/boring_avatars` rather than assuming it.

### Downstream loop

**N/A — nothing is published.** At first publish, derive consumers on the spot
(`for d in ../*/; do grep -l 'boring_avatars:' "$d/pubspec.yaml"; done`) and
never store the list here. Note that this package's releases are **additive by
construction** (a new state is a new selector value), so a release will normally
oblige consumers to do nothing — say so explicitly rather than leaving it
implied.

---

## War-story index

Per-incident evidence lives in [`lessons.md`](lessons.md), indexed by step. The
hidden-state list above is *pre-incident* enumeration, not evidence; move a
row's story into `lessons.md` the first time it actually catches a defect, and
cite the issue number.

Twelve entries as of #37. The ones that have caught something more than once:

| Rule | Caught in |
|---|---|
| A file existing is not the feature existing | #1 → closed #8 |
| A tripwire that cannot trip reads as coverage | #34 |
| A mutation surviving means one of two opposite things | #34, #37 |
| A substitution that matches nothing reads as a surviving mutation | #34, #36, #37 |
| A byte gate catches what a picture never shows | #36 |
| A golden that agrees with itself proves nothing | #36 |
| A bar can be recorded, believed, and never run | #33 → #37 |
| A suite can be green for a mechanism it never runs | #36 |
| The hidden-state list is a hypothesis, and gets things wrong | #34 |
| "0 warnings" shipped a 44 MB build artifact | #1 |
