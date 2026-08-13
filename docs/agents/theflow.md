# theflow bindings (boring_avatars)

Project-specific data for the `theflow` skill. The skill holds the portable
*method*; this file holds this package's *bindings* — which reference to read,
where the boundary falls, how to prove behavior, which surfaces to sweep, which
gates to run. Per-incident evidence lives in [`lessons.md`](lessons.md).

Identity & invariants live in `CLAUDE.md`. `CONTEXT.md` / `docs/adr/` do not
exist yet — created lazily.

**Environment:** Claude Code and the user share one machine, and **which one
varies per session** — Windows (Flutter 3.41.9, Node v26.4.0, npm 11.17.0)
through #58, macOS (Flutter 3.44.8, Node v24.11.1) at #59, **Windows again at
#51 and #42**. It moves back and forth, so this list is history and not a
current-state field; **measure, do not read it**: `flutter --version`,
`node --version`, `uname -s`. The one thing that actually depends on the answer
is `pana` — see Step 7. Either way, run `flutter test` /
`analyze` / `dart format` and the Node parity harness directly (do not ask). The
exception is anything that opens a window (`flutter run`) — ask the user to drive
and say what to look for. **There are no CI gates**: the Step 7 gates are the
only gates and they run here. The one GitHub Actions workflow this repo has is a
*watcher*, not a gate (see Step 7).

**Line endings are a property of the checkout, not of the repo.** `.gitattributes`
declares `* text=auto` and the index is LF for all 80 text files — measured with
`git ls-files --eol`. The worktree is what differs: CRLF under Windows'
`core.autocrlf=true`, which is where `lessons.md`'s two CRLF incidents came from,
and LF on macOS. So "the tree is CRLF" is a *machine* fact and was recorded here
as a repo one until #59. `tool/mutate/run.mjs` already does the right thing —
it reads the file's own ending — and a mutation pattern typed from the wrong
assumption comes back `NO MATCH`, which is the outcome that exists for it.

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
`lib/src/raster/` the deterministic software rasterizer. As of #41 they hold
**all six** — `pixel`, `ring`, `sunset`, `bauhaus`, `beam` and `marble`.
`raster.dart` fills two kinds of shape
through a rounded-rect mask — axis-aligned rectangles in closed form, and
polygons by a scanline integrator under the **nonzero** winding rule —
`path.dart` turns SVG path data, circles, cubics, rounded rects and stroked
paths into those polygons at a stated flattening tolerance, `transform.dart`
reads a `transform` attribute back into an affine matrix (`translate`, `rotate`,
`scale`), and `scene_raster.dart` bridges scene to
pixels by reading nodes **by attribute name**, composing an inherited matrix down
through `<g transform>`. `raster.dart` also holds the
colour vocabulary — `readColourDeclaration` splits a declaration into absent /
`none` / read / unreadable, and `fill`, `stroke` and `<stop>` each answer those
four explicitly (#69). The `<color>` grammar behind "read" spans three data
files: `named_colours.dart` (generated from the spec's §6.1 table),
`system_colours.dart` (generated from a Chrome measurement — for system
colours the measurement *is* the spec) and `colour_spaces.dart` (the Color 4
conversion maths, matrices derived from the primaries' chromaticities rather
than transcribed; gamut model per-channel clip, measured). The measurement
harness is `tool/colour4/`. One reader stays outside it on purpose: `_readMask`'s
`fill != '#FFFFFF'` guard asks whether the mask is filled with the literal white
upstream writes, which is a byte question and not a colour one. `matrix`/`skew`, quadratics and
`stroke-linecap: square` arrive with the variants that need them, and everything
unimplemented throws.

**Filters and blend modes arrived with `marble` (#41), and they are the first
thing in the package that does not composite straight onto the destination.** A
shape carrying a `filter` or a `mix-blend-mode` is drawn into its own **padded
float** layer, blurred premultiplied, and composited once. Three things about
that are load-bearing and none is obvious:

* **The layer is bigger than the canvas.** `marble`'s second blob reaches x ≈ 89
  on an 80-wide target once its `scale(1.3)` applies, and a blur of sigma 8.4
  pulls that back about 25 pixels into view. Rasterising only `[0, width)` drops
  it and the edge is quietly wrong.
* **The blur's sigma is in the *element's* user space, which includes the
  element's own `transform`.** §15.7.2's "user coordinate system in place when
  the filter is referenced" is the transformed one, so `stdDeviation="7"` under
  `scale(1.2)` is a blur of **8.4** device pixels. Taking the 7 literally
  measured **27/255** against Chrome; scaling it took the same comparison to
  **1/255**. A non-uniform transform would need an elliptical kernel and is
  refused rather than averaged.
* **The filter chain is validated as a whole and then reduced to one number.**
  Upstream writes `feFlood` (transparent) + `feBlend` (source over it) +
  `feGaussianBlur`, which is a blur and nothing else — but only because the
  first two are *checked* to be the no-ops they look like. A flood that paints,
  or a blend reading something other than `SourceGraphic`, throws.

**A stroke outline is a pile of pieces, not one polygon.** `strokePathOutline`
emits a quad per segment and a disc per joint and lets the **nonzero** rule union
them — so there is no offset-curve arithmetic at a joint and no self-intersection
to resolve. The catch is that every piece must wind the same way or nonzero
*subtracts* and each joint becomes a hole; the quads are always negatively
oriented and `flattenCircle` positive, so the discs are reversed. Round joins are
not an approximation of `miter` here: a browser strokes the *curve*, whose true
offset is the Minkowski sum with a disc, and mitering our own chords would
reproduce an artefact of the flattening instead — 1.7e-5 user units apart at
`beam`'s mouth, four orders below the coverage bar.

**A rounded rect is §9.2's equivalent path, not a fifth primitive.** It is built
from the same `_appendArc` the arc commands use, so its corners inherit F.6.5,
F.6.6 and the stated tolerance rather than getting a second implementation to be
wrong in.

**`transform.dart` is the second half of a seam, not a convenience.** Upstream
builds the attribute by concatenating numbers into a string, so the scene carries
that *string* and the SVG backend emits it verbatim; only the rasterizer turns it
into geometry. A rasterizer that read `translateX`/`rotate` off the variant
instead would be a second copy of the placement, free to drift from the one the
emitter ships.

**Rects keep their own closed-form integrator on purpose.** The polygon path
quantises the vertical direction, and a horizontal edge is exactly where that is
worst; a box-overlap product has nothing to approximate. The two are tied
together by a test rather than left to drift — `raster_path_test.dart` renders
the same fractional rectangle both ways.

**#58 made that branch unreachable at every scale but 1:1, and the rationale is
now conditional.** `Affine.isTranslationOnly` requires `a == 1 && d == 1`, and
the walk now starts at `Affine.scaling(s, s)`, so at any `s != 1` every
axis-aligned rect goes to the scanline integrator instead. Accuracy is not what
changes — measured against exact analytic box coverage at `s` of 1.0, 1.25, 1.5
and 2.5, the scanline result is **0.0/255** off at every pixel — so this is a
reachability and cost question, not a wrong picture. The closed form stays
because 1:1 is the golden path and the reference the other integrator is checked
against; a widget rendering at a fractional device pixel ratio will simply never
reach it.

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

Public surface is the barrel `lib/boring_avatars.dart`. As of #59 it exports
**three** names: the two enums and `boringAvatarSvg`. The third export carries a
`show` clause — `lib/src/avatar.dart` also holds `buildAvatarScene`, whose return
type is the scene model, and exporting that would ship every element, attribute
and ordering rule as public API. `api_surface_test.dart` pins the export list
literally, because a test that only *uses* the surface cannot see what leaks out
beside it.

| Module (`lib/src/`) | Layer | Role |
|---|---|---|
| `js/` | **1 data** | JS-semantics primitives — `hashCode`, `getNumber`, `jsMod`, `toSigned32`, `getDigit`, `getBoolean`, `getUnit`, `getRandomColor`, `getContrast`. **Sacred.** |
| `avatar.dart` | **1 dispatch** + public seam | upstream's `avatar.js`: `(version, variant) →` a scene, with the alias/degrade rules delegated to `variant.dart` rather than restated. Plus `boringAvatarSvg`, the only thing the barrel exports |
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

So the eight in-scope upstream states map to **two render paths and three byte
paths**, and the three byte paths are the three selectors `CLAUDE.md` principle
3 lists. Not eight.

*(This paragraph read "**Keep all eight** — someone pinned to 1.8.0 must be able
to name it — but do not build eight implementations" until #43, which is the
exact claim the correction four paragraphs above says it replaces. The
correction was written and the sentence it corrected was left standing ten lines
below it, so this section argued both sides at once — and the losing side was
the one a reader hits last. Found while verifying #43's grouping, which rests on
this section.)*

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
| 8 | `colors: []` | `% 0` → `NaN` → `colors[NaN]` → `undefined`. **Then it splits by variant, and by *attribute*:** five variants put that straight into a `fill`, and React drops the attribute; **`beam` throws**, because it hands the same `undefined` to `getContrast`, which calls `.slice` on it — **reproduced as an `ArgumentError` since #38, on the user's ruling S-2**, so the port fails on exactly the inputs upstream fails on. **`bauhaus` loses a `stroke` as well** — its `<line>` has no fill at all (#39) | `% 0` **throws** everywhere | crash where JS degrades — *and* silent success where JS crashes. "Empty palette degrades" is true per variant, not in general (measured at v1.6.1, all six variants × 20 names). The two absences are safe for **different reasons**: `stroke`'s initial value is `none`, so a missing one paints nothing on its own, while `fill`'s initial value is **black** and what makes it safe is the root `<svg fill="none">` inheriting down — present in all 600 renders. A variant whose root dropped that would paint every unfilled shape black, and nothing in the rasterizer reads the root to notice. Contrast row #39, where `stop-color`'s absence *is* black |
| 9 | SVG `rx` on `<rect>` | clamped to `width/2` | Flutter `RRect` scales radii instead | wrong corner shape |
| 10 | SVG arc with radii too small (`a1,0.75 … 10,0` in beam's closed mouth) | spec **scales both radii up** until the ellipse fits (F.6.6) | `arcToPoint` does not correct | wrong or throwing path. **Implemented in #36/#37 for `ring` and first actually *fired* by `beam` in #38** — every arc `ring` writes has λ exactly 1 (#36), so the correction was dead code for two tickets. Here λ is 25: both radii scale ×5 to rx 5 and ry 3.75, and the filled half-ellipse is **29.45** where an uncorrected one would be **1.18**. `beam_raster_test.dart` measures which, and the two are a factor of 25 apart so no tolerance can confuse them |
| 11 | `<filter>` with no `x/y/width/height` (marble) | the region defaults to **-10% / -10% / 120% / 120%** — and under `filterUnits="userSpaceOnUse"` those percentages resolve against the **viewport**, not the bounding box (SVG 1.1 §7.10). For `marble`'s 80 x 80 viewBox that is `(-8, -8, 96, 96)` — **and those numbers are then coordinates in the *referencing element's* space, not the viewport's**, so the element's own `transform` moves, scales and rotates the region (§15.7.2, the same sentence that governs `stdDeviation`). Under a rotation its device-space image is a quad. It is a clip on the **output only**: content outside it still blurs *in*, it just cannot be seen *out* | reading the percentages as bbox fractions, or clipping the source too | **this row said "of the bbox" from #1 to #41 and nothing could catch it** — `marble` is the only variant with a filter and it was unported, so no code read the number. Measured in Chrome when #41 finally opened it: a 10 x 10 rect at (35, 35) blurred with no region renders **identically** to one given `x="-8" y="-8" width="96" height="96"`, ink from 18.25 to 61.75, and quite differently from the bbox reading's hard cut at 34…46. The output-only half was measured the same way: a bar spanning x = -40…20 inside a region starting at x = 6 is cut to nothing below 6 and **identical to an unclipped render** at every x >= 6. Both readings are now inert for `marble` anyway — the region contains the mask, so the mask cuts first — which is why `marble_raster_test.dart` constructs a region that really does clip. **And the row was wrong twice.** The #41 completeness pass found the port applying §15.7.2 to the sigma and not to the region — an internal inconsistency, since one sentence governs both. Reproduced in Chrome with a control that must come out the same under either reading: `region x=0 w=20` renders ink `0..19` untransformed (both readings agree), `0..39` under `scale(2)` and `40..59` under `translate(40 0)` — the transformed reading, twice. On the variant itself Chrome clips `marble-clara-square` by 23 pixels where the port clipped none. Live only for `square: true`: with the disc mask the region cuts nothing the mask has not already cut. Same lesson as #26, twice over: a row nobody can act on is a row nobody checks, and a row that is *half* inert survives its own ticket |
| 12 | **A variant file existing ≠ the variant being reachable.** `avatar.js`'s dispatch is the authority, not the file listing | `avatar-turbulence.js` ships from v1.2.0 to v1.5.2 with an unchanging blob and is **never dispatched in any version** | porting it from the file tree | the project's heaviest rasterizer feature built for something no user could select |
| 13 | `eye` | dispatched **only at v1.2.0**; the file survives to v1.5.2 unreachable | assuming it lives as long as its file | a phantom variant in later states |
| 14 | `geometric` / `abstract` | **two different meanings by era** — distinct variants at v1.2.0; *unreachable* v1.3.0–v1.4.2 (fall through to `marble`); **deprecated aliases** `{geometric→beam, abstract→bauhaus}` from v1.5.3 | one enum value with one meaning | the same name renders three different things |
| 15 | unknown `variant` | falls back to the era's default — `geometric` at v1.2.0, `marble` from v1.3.0. Never throws | throwing on an unknown value | a crash where upstream degrades |
| 20 | **The two backends disagree on a malformed colour** | the palette is consumer policy and upstream validates none of it, so `red`, `rgb(…)`, `hsl(…)` and every hex form all reach the port. The SVG emitter passes them through and a browser draws them; **as of #63 so does the rasterizer** — hex (#62), the 148 named colours, `transparent`, `currentColor`, and the four colour functions, with ASCII-insensitive keywords and CSS trimming | letting the rasterizer guess, or letting it silently skip | the same input yields a correct SVG and a blank raster — the two-backend divergence the scene seam exists to prevent. A sign is rejected outright, since `int.tryParse('+12345', radix: 16)` succeeds and would turn punctuation into a plausible colour. **#69 separated the state without moving the answer**: "unreadable" is now its own case rather than everything `parseHexColour` rejects, so `none` stopped being filed under it (#31). **#64 then changed the answers alone**, which is what #69's naming was for: a value outside every grammar now draws what a browser draws for an ignored declaration — **nothing in a `fill` or `stroke`, black in a `stop-color`** (ADR-0001 R2, and `<stop>`'s throw went with it — #44). Both measured against Chrome end-to-end: `bauhaus-invalid` and `sunset-invalid` in `tool/calibrate` render a mixed valid/invalid palette to interior-exact agreement. **The row's premise — that this is *intended* divergence — was false, and #62 rewrote the row rather than the intent.** `red` and `#F00` were never caller garbage; they are notations a browser draws and this rasterizer had not learned, which makes the blank a **gap**. #62 closed the hex half of it: four notations, either case, short forms doubling every digit including alpha (`#F008` is 136 and not 128, measured), and a colour's alpha multiplying the shape's coverage rather than replacing it (`#FF000080` over white is 255,127,127 at full coverage and 255,191,191 at half — both measured). **#63 finished the rest**: the 148 named colours generated from the CSS Color 4 §6.1 table and cross-checked against Chrome (148/148), `transparent`, `currentColor` (**black**, measured in a document declaring no `color`), and `rgb()`/`rgba()`/`hsl()`/`hsla()` with either separator, percentages or 0–255, alpha as number or percentage, and hue in `deg`/`grad`/`rad`/`turn`. So the gap this row described is closed, and with #64 the last question — what a value *outside* the grammar draws — is answered too. **What remains different is not an answer but three seams**: the `fill` answer is produced by a different *mechanism* (we answer "unreadable" directly; a browser ignores the declaration and inherits the root's `none` — ADR-0001 discrepancy ②, which parts ways the day a root declares a colour, and the rasterizer does not read the root); a dangling `url(#…)` still throws where a browser paints nothing (deliberate, ADR-0001's one departure, for observability); and the **widget** still refuses an unreadable palette with `ArgumentError` (#80's ruling) where `boringAvatarSvg` passes it through — a seam whose stated rationale ("the raster path cannot read it") #64 has now aged, flagged to the user rather than edited. **And the one residue that was a gap is closed**: #64's pass measured that `hwb()`, `lab()`/`lch()`, `oklab()`/`oklch()`, `color()` and the system colours were valid Color 4 filed as unreadable; the user ruled "learn them" (2026-08-11) and **#95 did** — matrices derived from the primaries' chromaticities, the gamut model measured as per-channel clip, the 42 system colours frozen from a Chrome 151 measurement (`tool/colour4`, re-runnable), all byte-exact against the reference Chrome and interior-exact end-to-end (`bauhaus-colour4` / `sunset-colour4`). What now lands in "unreadable" while a browser draws it is **recorded scope, not accident**: `none` components, relative colour syntax and `calc()` — measured drawn, deliberately skipped, pinned in `raster_colour4_test.dart`. **One value moved cell rather than answer**: `#FF00` is a valid `#RGBA` — yellow at alpha zero — so it draws nothing by *painting nothing*, not by being ignored, and #62's own acceptance criteria had it listed beside `#GG0000` as invalid. **The rule this row keeps re-deciding is [ADR-0001](../adr/0001-what-a-colour-declaration-means.md)** — the split it describes is derived there from the property's grammar and its inheritance, not decided per case |
| 21 | SVG `rx` / `ry` clamping | §9.2 in three steps, and the middle one is the one that gets skipped: one given radius fills **both** slots, then `rx` clamps to width/2 and `ry` to height/2 **independently**, so a non-square rect gets **elliptical** corners | one circular radius, or `min(w,h)/2` for both | wrong corner shape. **Live since #38.** `beam`'s eye rects are `1.5 × 2` with `rx="1"`: `ry` becomes 1 too, then `rx` clamps to 0.75 and `ry` stays 1 — and because each is exactly half its own side the straight edges vanish and the eye is a full **ellipse**. Two ellipses are 4.712 px² where two circles of the clamped 0.75 would be 3.534 and two unrounded rects 6.0, so the reading is decided by arithmetic rather than by a tolerance. The masks are all still square, so the *mask* half of this row remains inert |
| 22 | `mask-type` | `pixel` declares `mask-type="alpha"`; **the other five declare nothing**, which in SVG means a *luminance* mask | treating every mask as alpha | wrong everywhere the mask shape is not white. Inert today — all six fill the mask `#FFFFFF`, where luminance and alpha both come to 1 — and the rasterizer now **throws** rather than assuming, so the day one is not white it fails loudly |
| 24 | **Abutting shapes vs stacked shapes** | two half-covering rects meeting inside one pixel should fill it — an exact rasteriser gives alpha 255 | source-over compositing, which gives **192** | source-over is right for shapes *stacked* on each other and wrong for shapes *abutting* each other. Inert for `pixel` — its tile edges are integer-aligned and `_checkViewBox` refuses any target that is not 1:1 — and inert for `ring`, which abuts along `y=45` in four places but at the enforced 90×90 target that is a pixel boundary. **Also inert for `bauhaus`, contrary to what this row said until #39**: it draws a full-canvas background rect and then three shapes *on top of* it, so every pair either overlaps or is disjoint and no two share a boundary. The row named it live on the strength of its fractional edges, which is the condition for the *other* half of the sentence. **And inert for `beam` too, contrary to what this row predicted until #38** — the same correction it already took for `bauhaus`, for the same reason. `beam` lays a full-canvas background, puts the card on top of it and the face on top of the card, so every pair either overlaps or is disjoint and no two shapes meet edge to edge. The row named it live on the strength of its fractional coordinates, which is the condition for the *other* half of the sentence. **And inert for `marble` too, measured in #41 — so the row is now inert for all six and has never once been live.** `marble` lays a full-canvas background and puts two blurred blobs on top of it, so every pair either overlaps or is disjoint; two arbitrarily rotated polygons do not share an edge. That is the third time this row predicted "live" from fractional coordinates alone (after `bauhaus` and `beam`) and the third time the actual condition — two shapes *meeting edge to edge* — was absent. The prediction, not the mechanism, is what keeps being wrong. **And then #58 made it live — the first time in this row's history — by deleting the clause that made it inert.** Both of its inertness arguments named `_checkViewBox`: `pixel`'s tile edges are integer-aligned *at a 1:1 target*, and `ring` abuts along y=45 *at the enforced 90×90*. An arbitrary device scale is exactly the condition the row's closing sentence reserved. Measured on the branch, counting interior pixels clear of the mask rim whose alpha is below 255 — `pixel` 80→0, 84→452, 100→556, 101→1025, **210→1944**, 128→0; `ring` 101→36; worst gap **80/255** for `pixel` and 63/255 for `ring`. `pixel`'s 10-unit tiles land mid-pixel whenever the target is not a multiple of 8, and 210 is the 2.625 device pixel ratio a widget will actually ask for. **Ruled in #83: live, and the reproduction is correct.** A browser compositing a plain display list conflates the same way (row #23), and it does — measured, not inferred. `tool/calibrate` grew a **square** `pixel` at 100, which is the only case in that harness with no curve in it, and both sides produce **784** partial pixels with **zero** where Chrome is opaque and we are not; worst edge delta **3/255**, the best row in the table by a factor of twenty. `pixel` at **210** — the 2.625 device pixel ratio a widget actually asks for — agrees the same way. The residues that remain in that run (`pixel` 100 rounded, 1 px; `ring` 101, 8 px) are all on a **mask curve**: mirror-symmetric about the centre, at the circle's extremes, which is hidden-state #27 and a separate unruled question. **So the code does not change**, and `raster_scale_test.dart` now carries the count *and* the agreement rather than the count alone. Valid **as long as every drawn edge falls on a pixel boundary**, and only where two shapes actually meet edge to edge |
| 23 | Rounding when shapes overlap | a browser draws each shape of a plain display list onto an **8-bit** surface, so it rounds once per shape too | assuming either model without measuring | **corrected in #37 — the row used to claim the opposite of what the code does.** `blend()` reads back the byte the previous shape wrote, so k stacked shapes round k times, and that is what matches the reference. Measured drift against a single float accumulation, over 1.2M stacks of 2–9 opaque shapes: **2/255 premultiplied** (16/255 straight at negligible alpha — #29, not a real difference). `pixel`'s tiles never overlap; `ring` stacks nine; marble, bauhaus and beam stack two to four. **The condition this row reserved is now discharged, and it went the other way.** `marble` does introduce an offscreen layer, and #41 implemented it: a filtered shape is drawn into a padded **float** buffer, blurred premultiplied, and composited once. So the layer rounds *once*, not per shape — the opposite of the model this row defends for a plain display list, and right for the same reason, because a browser also composites a filter result as one image. Measured against Chrome on the real variant: every remaining interior disagreement is exactly **1/255**, on at most 5 pixels of 6400 |
| 18 | **Attribute order is per call site, not per element** | React emits props in the order the JSX author wrote them, so one element takes several orders: `circle` is `cx cy r fill` in `ring` and `cx cy fill r transform` in `bauhaus`; `rect` and `path` each take five or more | giving the emitter a canonical order per element | every render whose order differs — silently, since a browser does not care about attribute order. The scene node therefore carries **ordered** attributes and the rasterizer reads them by name |
| 19 | React's serialisation details | no self-closing tags (`<rect …></rect>`, never `<rect/>` — zero `/>` in 480 renders); no whitespace between elements; `'` escapes to **`&#x27;`** not `&apos;`; tabs, newlines and non-ASCII pass through; element names keep camel case (`linearGradient`) while some attributes hyphenate (`mask-type`, `stop-color`) and others do not (`maskUnits`, `stdDeviation`) | any of the plausible alternatives | byte-level layer-2 failure that renders identically on screen. The hyphenation split is **a list, not a rule** — callers supply the emitted spelling |
| 17 | **`pixel`'s first tile is never filled** | `avatar-pixel.js` builds its 64 colours with `getRandomColor(numFromName % i, …)` from `i == 0`. `hash % 0` is `NaN`, so `colors[NaN]` is `undefined` and the first `<rect>` ships **with no `fill` attribute at all** | filling tile 0 from the palette | wrong on **100% of pixel renders**, every name, every palette — including the defaults. Distinct from #8: that is a degenerate *palette*, this is a degenerate *loop index*, and it needs no unusual input to fire. Committed fixture `svg.json` → `pixel\|upstream-default\|upstream-default` shows it |
| 16 | `<title>` | `1.6.1` emits `<title>{name}</title>` **unconditionally and has no `title` prop at all** — there is no way to switch it off; the prop arrives in `1.7.0`, defaulting off | giving `v1_6_1` a `title` parameter, or implementing the prop-gated form everywhere | `v1_6_1`'s SVG bytes are wrong while its pixels are right — a layer-2 failure a pixel test cannot see. **Ported in #43, and the row's warning shaped the API.** The public argument is `bool? title`: either literal default would be silently wrong for one of the two selectors, and `null` lets each answer as upstream does. The row's first trap — giving `v1_6_1` a `title` parameter — is avoided by making `title: false` there an `ArgumentError` rather than a no-op; the second is avoided by keeping the flag in `avatar.dart` and passing it down, so the six builders carry upstream's own `{props.title && …}` and nothing decides the rule twice. Measured: the 1.6.3 → 1.7.0 source diff is 7 files and 14 lines, **6 of them this element and 6 whitespace inside a JSX expression** that reaches no output, so this row is the whole of `0.2.0`. `v1_7_0` with `title: true` is byte-identical to `v1_6_1` for all six variants |
| 25 | **SVG arc flags are single characters and may be packed against the number after them** | `ring` writes `a32 32 0 10-64 0`, where `10` is *two flags* — large-arc 1, sweep 0 — and `-64` is the endpoint | a tokeniser that scans numbers uniformly reads ten, then takes `-64` as the sweep flag | a plausible wrong picture that throws nothing. Upstream writes this form in four of `ring`'s six arcs, so it is not hypothetical. Pinned by `raster_path_test.dart` — two `d` strings differing in one byte must come out mirrored |
| 26 | **The drawing space is per variant, and is not the display size** | **three** values, not two: `ring` is 90, `beam` is **36**, and `bauhaus`, `marble`, `pixel`, `sunset` are 80. `size` still only reaches `width`/`height` | assuming one canvas constant for the package | **until #58 the rasterizer refused a target that did not match the viewBox, so this surfaced as a throw rather than a squashed avatar; it now scales to any uniform target instead, and the throw is gone.** What the three numbers still decide is what 1:1 *means* per variant — the *goldens* have to be generated at the right number, and a per-package `size` in the golden tool silently produces the wrong reference. **This row said "the other five are 80" until #38 measured it**, and it was wrong for the whole time `beam` was unported — the fact sits in `avatar-beam.js:4` (`const SIZE = 36`) and in all 80 of its fixture renders, and nothing read either. A row nobody can act on yet is a row nobody checks; see `lessons.md` |
| 27 | **Chrome's own curves are inset from true circular geometry**, by an amount that depends on the radius — **and its shallow straight edges are wrong in the other direction** | measured directly: `<circle r=20>` loses 1.69 px² of area (0.0135 px inward), `r=23` loses 11.95 (0.083 px), `r=40` loses 32.03 (0.127 px); an `<path>` half-disc of r=38 loses 17.32 (0.145 px). An **axis-aligned** `<rect>` is exact at integer edges and within 0.003 px at fractional ones — but a **rotated** one is not, and it errs *outward*: measured in #39 against exact coverage (Sutherland–Hodgman clip + shoelace, which quantises nothing), Chrome overstates a 4°-from-horizontal edge by **30.6/255** and a 22° one by 19, while at 0° it is exact. Ours is within 0.03/255 of exact on every shape `bauhaus` draws | treating a Chrome render as ground truth for *any* antialiased edge, curved or shallow | the old ≤1/255 calibration bar was **unmeetable for a curved edge and for a shallow rotated one** — not because our coverage is wrong but because Chrome's is. **Settled 2026-08-11** — the bar was re-scoped to what each statistic can measure (Step 4's event): interiors and the curve-free control stay gated, curves and shallow edges are reported with this row as the named reason. The row's old sentence "a fractional rect is within 0.003 px" was true and covered only the axis-aligned case, which is exactly the case `bauhaus` stopped being |
| 28 | **F.6.5's centre square root goes negative when a chord rounds past the diameter** | for an *angled* chord equal to the diameter, `lambda` can compute as exactly `1.0` — so F.6.6's correction does not fire — while `(rx²ry² − …)/…` lands at `-1.3e-16`. Measured at `r = 1/7` | `sqrt` of the raw value | every vertex becomes `NaN` and the render dies in `ceil()`. Inert for `ring`, whose chords are all **horizontal** (the radicand is then exactly zero every time) — which is why a mutation removing the clamp survived the whole suite until a case was searched for. Valid **as long as arcs stay axis-aligned**. **`beam` re-checked in #38 and it is still axis-aligned**: its closed mouth runs `(13, y)` to `(23, y)`, a horizontal chord, so the radicand is exactly zero there too — and that is *after* F.6.6 scales the radii, which is the case this row was written to worry about. **`marble` checked in #41 and it is inert for a stronger reason than `ring`'s or `beam`'s: it has no arcs at all.** Across the 18 distinct `d` strings in all 600 renders, `marble`'s two are the only ones this row had left, and their commands are `M L H v h l z` — no `a`. So the row is now settled for all six, and the only thing that exercises F.6.5 is the constructed case in `raster_path_test.dart` |
| 29 | **Straight-alpha RGB is meaningless where alpha is small** | both our buffer and a PNG store *straight* alpha, so a pixel we cover 3/255 carries the full undiluted colour while Chrome's uncovered pixel carries zero | comparing the two backends channel by channel as stored | a 3/255 disagreement reads as a delta of **240** and a calibration run fails on a difference nobody could see. Compare **premultiplied** — `tool/calibrate/compare.dart` does. The same trap bites any comparison of our own arithmetic against itself: row #23's drift measures 16 straight and 2 premultiplied |
| 30 | **A container's attributes change the picture as much as a shape's** | `beam` wraps its whole face in `<g transform="translate(4.5 4.5) rotate(-9 18 18)">`; `<svg>`, `<g>`, `<defs>` and `<mask>` all carry attributes | validating only the elements you know how to *draw*, and walking through containers unchecked | the face renders 4.5 units off and unrotated with **nothing thrown** — the exact failure `UnsupportedSceneError` exists to prevent, one level up from where it was being checked. Found by the #37 completeness pass; every element on the walk now carries an allow-list. **#38 discharged it by implementing the thing rather than refusing it**: `_collectShapes` threads an inherited matrix and composes `parent · own` per §7.5, and `<g transform>` moved onto the container allow-list *in the same change*. The order matters — an allow-list entry for a transform nobody applied is precisely the silent wrong picture this row describes, so the two edits are one edit. Worth keeping as the record of a guard that paid for itself: the Step 1 enumeration for #38 listed five missing capabilities and this was not one of them; the guard is what found it. **And the row had a second half nobody had covered**: `<mask>` was allow-listed in #37 but *its child `<rect>`* was not, because `_readMask` is a different function that reads five geometry attributes and ignores the rest. Measured in #38 before fixing: `transform="scale(2)"` on the mask's shape produced exactly the untransformed coverage where a browser doubles it, and `opacity="0.5"` produced full coverage where a browser halves it — two wrong pictures, no throw, in the element that decides what the whole avatar is clipped to. The lesson generalises past this row: **an allow-list covers the walk it is on, and a second reader of the same tree needs its own** |
| 31 | **An unreadable `fill` is not the same as an absent one — and neither is `none`, which makes three** | upstream omits `fill` to mean "no paint" (#17), writes `fill="url(#…)"` to mean a gradient, and writes `fill="none"` / `stroke="none"` to mean SVG's own "no paint is applied" (11.2) | letting all of them fall through to "the colour did not parse, so draw nothing" | **every `sunset` render rasterised to a blank square**, silently, and a golden made from one would have frozen the blank as correct. A `url(...)` fill now throws. The third state was added in #69: `parseHexColour('none')` returned `null` because the string is four characters long, so `none` was *accidentally* right — and `beam` is the variant that brings it, `<path fill="none">` on 44 of its 80 non-throwing renders and `<rect stroke="none">` 160 times, so the accident would have been frozen into `beam`'s goldens. `readColourDeclaration` now returns four states — absent / `none` / read / unreadable — and `fill`, `stroke` and `stop-color` each answer them explicitly. The enumeration is closed, not sampled: across every rendered fixture section those three attributes take absent, `none`, `url(#…)` (on `fill` only) and upper-case `#RRGGBB`, and nothing else. Distinct from #20, which is the *caller's* palette and keeps its recorded behaviour — this one is upstream's own output |
| 32 | **Content outside the masked group is drawn by a browser, not dropped** | `<g mask>` masks its children; a sibling shape renders **unmasked** | silently collecting only what sits under the mask group | a picture the reference does not produce, with no error. Inert across all six variants — every drawn element is inside `<g mask="url(#…)">` — but the seam now throws rather than dropping. **This inverted an assertion #36 had pinned the other way**; both readings agreed on every real scene and only one agreed with SVG |
| 33 | **A mask applies to the composited group, not to each shape** | SVG composites a `<g mask="…">`'s children, *then* scales the result's alpha by the mask | folding the mask into every shape's own coverage | the mask is applied once per shape. Two opaque shapes stacked on a pixel a mask half-covers come out at **192** where one of them gives 128 — 64 levels of alpha against a bar of one. Inert for `pixel` and `ring`, whose mask-edge pixels are reached by at most one shape; **live for `marble`, `bauhaus` and `beam`**, which each lay a background rect under a shape crossing the mask edge. Fixed in #37; the fix moved 8 pixels of `pixel`'s goldens, all fully transparent, all straight-RGB-only (#29). **First variant to actually exercise it: `bauhaus` in #39** — `bauhaus_raster_test.dart` measures (14, 70), where the background and the bar both reach a mask-edge pixel, against a background-only render, so the expected value never comes from the mask's own coverage number. **Confirmed live for `beam` in #38**: its full-canvas background and its card both reach the mask edge, and the crosscheck's 0-pixel bar over 160 rendered `beam` cases would fail on the per-shape reading |
| 34 | **`z` ends a subpath; what follows starts a new one** | `M0 0h10v10H0zh10v10` is two subpaths from the same origin | treating `z` as only a "return to start" and leaving the contour open | the two weld into one polygon — measured 75 units where SVG gives 100. Inert at v1.6.1: across the 18 distinct `d` strings in all 600 renders, `z` is always the **last** command, so no fixture could catch it. Valid **as long as that stays true** — a multi-subpath `d` in a later upstream version makes it live |
| 35 | **A `<mask>` carries a clip region, units, and an id that is referenced** | `maskUnits` decides whether `x/y/width/height` are user units or bbox fractions; the region clips the mask shape; `mask="url(#id)"` has to name a mask that exists | reading only the child shape | three silent wrong pictures: a region that cuts its own shape renders uncut, `objectBoundingBox` reinterprets every number, and a dangling reference renders masked where a browser renders unmasked (SVG 2) or not at all (SVG 1.1). All inert at v1.6.1 — one mask, `userSpaceOnUse`, region equal to the shape — and all three now throw |
| 37 | **`1.11.0` spreads its own props onto the `<svg>` element** | `<svg … colors="#92A1C6,#146A7C,…" name="Clara Barton">` — the destructuring keeps `colors` and `name` in `...otherProps`, so React writes them as DOM attributes | assuming a "prop spreading" changelog entry leaves the output alone | a whole upstream release whose markup differs from every neighbour on **all six variants**. It is the reason `1.11.0` is skipped rather than folded into `v1_10_1`; fixed upstream in `1.11.1`. Found by grouping rendered output, which a source diff had classified as inert |
| 38 | **`sunset` puts the caller's name inside an id** | `'gradient_paint0_linear_' + props.name.replace(/\s/g, '')`, referenced as `fill="url(#…)"` — and React escapes the attribute, so `O'Brien` becomes `O&#x27;Brien` **in the id and in the reference alike** | keeping the raw name, or stripping a different whitespace class | the two sites drift and the reference names nothing, which a browser renders **black** rather than erroring. Invisible to the byte sweep: `normalise` erases `id="…"` and `url(#…)` on both sides, so a port that named its gradients anything at all passes all 100 renders. The harness records them unnormalised (`derivedIdentifiers`, per name) and `sunset_parity_test.dart` asserts them. Dart's `\s` matches exactly JS's 25 code points — measured — so the strip is a straight translation |
| 39 | **A missing `stop-color` is black, where a missing `fill` is nothing** | an empty palette makes upstream emit `<stop></stop>`; SVG's initial `stop-color` is **black**, so `sunset` renders a solid black disc | reusing the other five variants' rule that an absent colour means "draw nothing" | a transparent avatar where upstream draws a black one. Confirmed in Chrome before it was implemented. `sunset` is the only variant whose empty-palette answer is a *picture* rather than an absence |
| 40 | **`<defs>` is not "not drawn, so not interesting"** | it sits *outside* `<g mask>`, after it, and holds the paint the drawn shapes reference | skipping it the way `<mask>`'s own shape is skipped | every `sunset` render came out blank, silently — the shapes referenced paint that had never been read. Fixed in #40 by reading `<defs>` into paint servers before the shapes are collected, and validating its contents as strictly as a drawn element's |
| 41 | **Chrome dithers a gradient but does not approximate it** | measured: Chrome's gradient stays within **0.987** of the exact sRGB interpolation, varying across x within a row | assuming the `≤1/255` bar behaves the same for gradients as for curves | it does not, and the difference is the point. An exact interpolation rounded to nearest lands **≤1/255** from Chrome across all 4548 gradient pixels (58.6% exact, 41.4% off by one) — the bar is *met* here, where for a curve it cannot be (#27). One threshold was measuring two unrelated things |
| 43 | **A dangling paint reference paints nothing, not black** | measured in Chrome: `fill="url(#nope)"` gives `0,0,0,0` at every pixel, with or without a root `fill` — a CSS `<url>` with no fallback and an invalid target has the used value `none` | writing "a browser renders it black" as the reason for a guard | the guard is still right and the *reason* was wrong, in three places at once (#40 wrote it into `scene_raster.dart` and two tests). Throwing is justified by "a blank is indistinguishable from the paint never having been read" — which is the bug #40 fixed and it was silent for a whole variant — not by a colour Chrome does not produce |
| 44 | **`sunset` throws on a palette colour the other five draw nothing for — RESOLVED in #64** | historical: `parseHexColour` returned `null` for what is now a truly invalid value; in a `fill` that meant "draw nothing" (#20), and in a `<stop>` `_readLinearGradient` threw instead | assuming the two agree | measured when live: `['red']` gave a blank avatar for `pixel` and `ring` and an exception for `sunset`. **Ruled in [ADR-0001](../adr/0001-what-a-colour-declaration-means.md)**, and the answer was neither of the two this row offered. The split is real and *derived*: `fill` is inherited and the root declares `none`, `stop-color` is not inherited and its initial value is black, so one invalid-value rule (CSS 2.1 §4.2 + §6.1.1) produces both answers. What was **not** right was the throw — the derivation says an unreadable `stop-color` is black, and **#64 made it so** (`none` in a `stop-color` went the same way, being equally outside 13.2.4's grammar). The asymmetry this row's title names is over: all six variants now answer an invalid palette entry without throwing, per property. Kept as the record of the promotion trigger it was — this row and #20 requiring opposite things in one file is half of why ADR-0001 exists |
| 42 | **The calibration's interior/edge split is defeated by a gradient — and by any shape thinner than three pixels** | `_isEdge` asks whether a pixel's 3×3 neighbourhood is uniform — a good proxy for "antialiasing happens here" on flat fills, meaningless where every pixel differs from the one above it by design, and meaningless again for a shape no 3×3 window fits inside | reading "interior mismatches 0" as evidence that a shape is drawn correctly | for `sunset` it is **vacuous**: every gradient pixel is an edge, so the interior count is zero because the interior is empty. For `bauhaus` the interior is **not** empty — 56–61% of the painted pixels — and the statistic is *still* blind to the whole new capability: **deleting the stroked `<line>` outright leaves interior mismatches at 0 on all three cases** (#39, reproduced). A 2-unit stroke at 1 device px/unit has no 3×3-uniform pixel anywhere. The worst edge delta does move, 71 → 174–255, but the recorded bar is ≤1 and the baseline is already 71 (#27), so no threshold separates a missing shape from Chrome's own error. **`flutter test` killed every wrong picture tried; the Chrome run killed none of them** — the same conclusion #37 reached for a different reason. Measure a thin shape separately, or assert it in-repo. **#41 added the sharpest case yet: a *blur*.** Every pixel of a blurred shape differs from the one above it by construction, so `_isEdge` files 100% of `marble` as edge and the interior count is structurally incapable of moving — the `sunset` situation, but covering the whole variant rather than one gradient. The one place `marble` produces interior mismatches at all is where `overlay` **saturates** a region flat (an opaque white backdrop returns white for every source), which is an accident of the two-colour palette and not the statistic working. Read `marble`'s interior 0 as "the calibration had nothing to classify", never as agreement |
| 48 | **`dart:math`'s transcendentals are not guaranteed bit-identical across platforms, and invariant 4 says the bytes are** | IEEE-754 **requires** `sqrt` to be correctly rounded, and only *recommends* it for `cos`, `sin`, `atan2` and `acos`. Dart does not compute those itself: on the VM they go to the platform libm (UCRT / glibc / Apple's), on web to JS `Math.*` (V8's fdlibm port). Two platforms may differ by an ulp | assuming `math.cos` is a fixed function of its argument, the way `sqrt` is | a 1-ulp difference moves a vertex by ~1e-14, coverage by ~1e-14, and the ×255 product by ~2.5e-12 — which flips a byte only where the exact product sits that close to a rounding boundary. The case that does is **coverage of exactly 0.5**: `127.5` rounds to 128 in Dart, and `0.49999999999999994` rounds to 127. **Not measured — no divergence has been observed, and nothing here could observe one.** The goldens are generated and compared on one machine, and this repo has no CI gate by policy, so a Windows-authored golden differing on Linux would fail nothing. Pre-existing since #37: `flattenCircle` uses `cos`/`sin` and `_appendArc` uses `atan2`/`acos`. What #39 changed is the **scope** — from deciding how finely a curve is chopped, to the *placement* of every rect and line via `Affine.rotation`. `rotate(0)` is exempt: `cos(0)` and `sin(0)` are exact everywhere. **#95 widened the scope again, onto colour values**: the Color 4 conversions use libm `pow` (five transfer functions) and `cos`/`sin` (`lchToAb`), so a 1-ulp platform difference can now flip a palette *byte*, not only a coverage byte — same analysis, same rounding-boundary condition, new entry point. The derived matrices themselves are exempt (only correctly-rounded `+ − × ÷`). Valid **as long as nobody compares this package's bytes across two platforms**; the day someone does, the answers are to narrow invariant 4's wording, implement the transcendentals in-package from a fixed polynomial, or add a second-platform golden run |
| 45 | **A `transform` list post-multiplies — the rightmost function applies first** | SVG 1.1 §7.5: a list is "as if each transform had been specified separately in the order provided", which the same section shows as nested `<g>` elements. So `translate(tx ty) rotate(a cx cy)` maps a point by `T · R`, and the rotation acts on the shape's own coordinates. §7.4 adds that the transform is applied **before** the element's `x`/`y`/`width`/`height` are read, so those are values in the *new* space | composing the list the other way round | a shape at a plausible wrong place, with nothing thrown — the same class as #30. Live for `bauhaus`, `beam` and `marble`, the only three variants with a transform at all (measured across all 600 renders). Pinned in `bauhaus_raster_test.dart` by an example where the two orders disagree, not by a golden. **#38 extended it one level out**: §7.5 says a list is *defined* by nesting, so an ancestor `<g>`'s matrix composes exactly as another function in the list would — `parent · own`, the ancestor applying second. `beam_raster_test.dart` pins that with a case where the two orders disagree **on canvas**, which took choosing the rotation centre: the obvious construction puts the reversed order off the edge, where both orders paint nothing and the test cannot fail |
| 46 | **`rotate(a cx cy)` is not a fourth primitive** | §7.4 defines it as *exactly* `translate(cx, cy) rotate(a) translate(-cx, -cy)`, and gives no closed form for it | writing a remembered closed form and hoping | a rotation about the wrong point. Built from the definition here, and the test asserts one spelling against the other rather than against hardcoded numbers. A corollary worth keeping: `rotate(0 …)` **is** the identity exactly — `cos(0)` is 1 and `sin(0)` is 0 with no rounding — so the empty name, whose hash is 0, keeps the closed-form rect integrator. `rotate(360 …)` is *not*, and upstream cannot write it because `getUnit(n, 360)` tops out at 359 |
| 47 | **A stroke has *three* "paint nothing" cases, one of them is a `NaN` factory, and one of them is not "paint nothing" at all** | §11.4: a subpath of a single moveto is never stroked; a **zero-length** subpath is not stroked under `butt` but **is** under `round`, "producing … a circle centered at the given point"; and "a zero value \[of `stroke-width`\] causes no stroke to be painted" | normalising the direction vector before checking the length, or collapsing the first two cases | the zero-length case divides by zero and puts `NaN` in every vertex, which the scanline integrator carries **silently** rather than throwing. Unreachable from `bauhaus`, whose line is always `(0,40)–(80,40)`; both cases are constructed in `bauhaus_raster_test.dart`, and the branch is driven through `rasterizeScene` as well as through the helper — driving only the helper left the seam's own branch untested, which a mutation found (#39). **#38 added the third case and the round-cap half**, which the row had missed: the spec's own example of a zero-length subpath is `M 40,40 c 0,0 0,0 0,0`, a *cubic*, so it became reachable from the command `beam` introduced. Merging "single moveto" into "zero length" paints a disc §11.4 says is not there |
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

Suspected upstream defects and the **user's ruling** on each. Never append a row
the user has not seen and ruled on. One ruling recorded so far, as an event
below the table.

| Ref | Upstream `file:line` @ tag | What it does | Ruling | Decided |
|---|---|---|---|---|
| **S-3** | `avatar-marble.js:56` @ v1.6.1 (still `avatar-marble.tsx:59` @ v2.0.x) | the first path takes its colour, translation and rotation from `properties[1]` and its **scale from `properties[2]`** — a copy-paste slip, five neighbouring reads all say `[1]`. Fixing it changes the output on **11 of 20 corpus names**, and on **75% of all hashes** by derivation: `getUnit(2h, 4)` is always even, so element 1's scale can only ever be 1.2 or 1.4, while element 2's `3h mod 4` reaches all four | **reproduce it — the reference is the specification** | 2026-08-07 |
| **S-1** | `avatar-sunset.js:20,36,41` @ v1.6.1 | builds a gradient id from the caller's name and references it as `url(#…)`. For any name containing `'`, `"`, `(`, `)`, `\` or a control character the reference is not a valid CSS url token, so **the browser paints nothing** and the avatar is blank. Reproduced in Chrome: `O'Brien-Smith, Jr.` → all pixels `0,0,0,0`; `Clara Barton` → the gradient. The corpus name `punctuation` is exactly this case, and an apostrophe in a name is common | **repair it — do not reproduce the blank** | 2026-07-29 |
| **S-2** | `avatar-beam.js:9,17` + `utilities.js:42` @ v1.6.1 | an **empty palette** makes `getRandomColor` return `undefined`, which `getContrast` calls `.slice(0, 1)` on — a `TypeError`, and no document at all. `beam` is the only one of the six that does this; the other five drop an attribute and render. Measured: 20 of 20 names throw, against 0 of 100 for the rest (hidden-state #8) | **reproduce the failure, in a Dart-idiomatic exception** | 2026-08-06 |
| **S-4** | `avatar.js:18` @ v1.6.1 — `size = 40`, forwarded untyped to `width={props.size}` | a `size` that is **neither a number nor a string** is not validated anywhere. Measured at 1.6.1: `true` / `false` / `null` make React **drop `width` and `height` entirely** (with a dev-console warning), `[80]` coerces to `width="80"`, and `{}` renders `width="[object Object]"`. This package throws `ArgumentError` for all of them — a crash where upstream degrades, which is the failure mode hidden-state #8 and #15 name | **throw. Do not reproduce the degradation** | 2026-08-08 |

### S-4 — the ruling, as an event

**What the user was shown (2026-08-08):** the measurement below, taken from
upstream 1.6.1 through the parity harness's own installed copy, beside what this
package does for the same input.

| `size` | upstream 1.6.1 | this package |
|---|---|---|
| `80` (control) | `width="80" height="80"` | same |
| `true` / `false` / `null` | **`width` and `height` absent**, plus a React dev warning | `ArgumentError` |
| `[80]` | `width="80"` | `ArgumentError` |
| `{}` | `width="[object Object]"` | `ArgumentError` |
| `undefined` | `width="40"` (upstream's own default) | not reachable — `size` is required |

Two options, with what each costs:

| option | what a caller gets | what it costs |
|---|---|---|
| throw | a failure naming the argument | a crash where upstream degrades — hidden-state #8's failure mode, in the direction this project has not taken before |
| reproduce the degradation | upstream's bytes for every input | implementing JS's `String()` coercion **and** React's attribute-dropping rules, to emit `width="[object Object]"` faithfully |

**What they chose:** throw — *"걍 에러 던져 그럼. 그런 상황만 아니면 똑같다는
거잖아."* Their reasoning is the scope of the divergence, and it is worth
recording as the ruling's own justification: every input a caller can plausibly
mean — any number, any CSS length string — is byte-identical, and the divergence
is confined to values that are not sizes at all.

**Why this is not S-2, which went the other way.** There the *reference itself*
failed and reproducing the failure was the only thing that matched, because
upstream emitted no bytes to be identical to. Here upstream emits a perfectly
good document and we refuse it. The two rulings differ because the question
does: S-2 asked "do we reproduce a crash", this asks "do we reproduce a
coercion". Upstream's behaviour here is not a designed degrade — React prints
`Received true for a non-boolean attribute` precisely to tell the author they
made a mistake — so reproducing it means reproducing a bug report.

**It is theirs to reverse.** A product judgement about an API's shape, not a
derivation. A later argument that the port should be faithful above all does
**not** reopen it; only the user does.

**What it costs.** `boringAvatarSvg` is not byte-identical to upstream for a
`size` that is neither a `num` nor a `String` — it produces no bytes at all.
`avatar_svg_test.dart` asserts the throw *and* the argument it names, so a guard
that rejected something wider, or blamed the wrong parameter, fails.

### S-3 — the ruling, as an event

**What the user was shown (2026-08-07):** the five lines of
`avatar-marble.js` side by side — `properties[1]` for the colour, the two
translations and the rotation, then `properties[2]` for the scale — the
measurement that 11 of the 20 corpus names take different values, the
derivation that puts it at 3 in 4 for *any* name, and **a rendered page**:
every corpus name drawn twice, upstream's version beside the "corrected" one,
with a live difference panel where black means identical.

The derivation is what made the number safe to act on. A count over 20 names is
a fact about those 20 names; here `getUnit(2h, 4)` is `2h mod 4`, which is 0 for
even `h` and 2 for odd, so **element 1's scale is 1.2 or 1.4 and nothing else,
for every name that will ever exist**. Element 2's `3h mod 4` cycles through all
four. They differ whenever `h` is odd, and again when `h ≡ 2 (mod 4)` — 1/2 plus
1/4. A synthetic sweep of two million hashes gives exactly 1,500,000.

| option | what a caller gets | what it costs |
|---|---|---|
| reproduce it | upstream's avatar, byte for byte | the port carries a copy-paste slip |
| correct it | an avatar nobody has ever seen | 3 names in 4 change identity; a divergence row; `tool/crosscheck` reports 110 ruled cases against a bar of **0** pixels; permanent divergence from every upstream version, 2.0.4 included |

**What they chose:** reproduce it — *"그대로 재현으로 가자."*

**Why this is not S-1.** S-1 repaired `sunset` because upstream's own output was
**a blank avatar** — a defect the user could see. Here both versions are
perfectly good avatars and the only claim available is about the author's
*intent*. "Fix the bug" does not carry over from one to the other, and the two
rulings going opposite ways is the ledger working rather than a contradiction.

**It is theirs to reverse.** A product judgement about fidelity versus intent. A
later argument that the slip is obviously unintended does **not** reopen it —
only the user does.

**What it costs.** Nothing at layer 2: the fixture *is* upstream's output, so
reproducing it is what makes the 100 renders byte-identical. What it costs is
that `marble.dart` has to carry an explanation, and
`marble_parity_test.dart` has to pin the odd read directly — otherwise the next
reader "fixes" it and the byte sweep tells them they broke something without
telling them why.

### S-1 — the ruling, as an event

**What the user was shown (2026-07-29):** the reference upstream emits
(`url(#gradient_paint0_linear_O&#x27;Brien-Smith,Jr.)`), a Chrome render of it —
every pixel `0,0,0,0`, the whole avatar blank — beside the same name rendering
correctly once repaired, the count of affected corpus names (**1 of 20**), and
four candidate repairs each measured in Chrome:

| repair | works | bytes that move |
|---|---|---|
| leave it (reproduce upstream) | **no — blank** | none |
| percent-encode the **reference** only | **yes** | the two `fill` attributes |
| quote the reference | yes | the two `fill` attributes |
| strip the characters from the id | yes | the two ids **and** the two references |
| percent-encode the id as well | **no — blank** | — |

**What they chose:** repair it — *"버그는 수정하자."* Percent-encoding the
reference is the implementation, because it is the only working repair that
leaves `<linearGradient id="…">` byte-identical to upstream.

**It is theirs to reverse.** This is a product judgement: it trades "the same
bytes as upstream" for "an avatar the user can see". A later argument that the
port should be faithful above all does **not** reopen it — only the user does.

**What it costs.** `sunset` is no longer byte-identical for a name containing
`'`, `"`, `(`, `)`, `\`, `%` or a control character — one corpus name today.
`sunset_parity_test.dart` lists those names explicitly and asserts the
difference is *exactly* a percent-encoding, so the divergence cannot widen
without someone editing that list. Every other name stays byte-identical, and so
does every id, for every name.

**The other five variants are unaffected** — `sunset` is the only one that puts
the caller's name inside an id.

### S-2 — the ruling, as an event

**What the user was shown (2026-08-06):** the upstream chain that fails
(`getRandomColor(hash, [], 0)` → `colors[NaN]` → `undefined` →
`getContrast(undefined)` → `.slice` → `TypeError`), the measurement that it is
20 of 20 names for `beam` and 0 of 100 for the other five, the fixture entry
`{"__throws": "TypeError"}` that records it, and **three** options with what
each costs:

| option | what a caller gets | what it costs |
|---|---|---|
| throw, as an ordinary Dart exception | a failure naming the palette | the exception *type* differs from a JS `TypeError` |
| throw, imitating upstream's message | a failure quoting `.slice` | worse for a Dart caller, and the cause is hidden |
| degrade like the other five | a **fully transparent** 36×36 image | requires inventing a face colour upstream never produces |

The third row is the one the artifact had to show rather than assert: degrading
is not "an avatar without a card", it is *nothing at all*, because the face
colour has no degraded value — `getContrast` has no defined answer for
`undefined`, and dropping the attribute leaves the eyes and mouth unpainted too.
And upstream emits **no bytes** for this input, so "byte-identical" is vacuous
either way: every non-throwing output diverges by construction, and throwing is
the only thing that matches.

**What they chose:** throw, in a Dart-idiomatic exception —
`ArgumentError.value(colors, 'colors', …)`.

**It is theirs to reverse.** This is a product judgement about an API's shape,
not a derivation. A later argument that the port should degrade for robustness
does **not** reopen it; only the user does.

**What it costs.** A caller who passes `colors: []` gets an exception from
`beam` and an image from the other five. That asymmetry is upstream's, recorded
in hidden-state #8, and `beam_parity_test.dart` asserts both halves — the throw
for the empty palette and a normal render for a one-colour one, so a guard that
rejected any short palette would not pass.

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

**The consumer seam is in-repo** (`lib/src/widget/`) — plus, once published,
real pub.dev dependents. It reaches the core through **sibling `src/` imports**,
not through the barrel: `buildAvatarScene` is deliberately unexported and
`rasterizeScene` is not exported at all, so the barrel is the surface a
*dependent* imports and not the one this package's own consumer layer uses. Same
arrangement `tool/` already has, and for the same reason. *(This sentence said
"through the barrel" until #80, which is a route that does not exist.)*

**Layer 1 is frozen on publish.** Once a version selector ships, its values are
a contract: changing them silently rewrites every existing user's avatar
identity. New upstream states are added as **new selector values only** — always
additive, never an edit to a shipped state.

**`v1_6_1` is that selector, as of `0.1.0` — published 2026-08-12, queried not
assumed** (`curl -s https://pub.dev/api/packages/boring_avatars` → `latest`
`0.1.0`). This sentence stopped being a rule about the future on that date.
Concretely: **Step 5's third unconditional trigger was vacuous until now** — "any
change to a *published* version selector's layer-1 output" named no selector,
because none was published. It names one today, so a change to what `v1_6_1`
draws is a completeness-pass path whatever its diff looks like.

**Cross-repo rules are live as of the same date.** They were N/A while pub.dev
returned `NoSuchKey`; the SDK-floor constraint, the two-consumer signal and the
after-merge downstream loop all assume consumers that cannot be seen from here,
and now such consumers can exist. What that changes in practice:

- **`environment: sdk: ^3.11.5` is now a published floor.** Raising it is a
  breaking change for every dependent, carried down by the caret range whether
  or not anyone here thinks of it as an API change.
- **The two-consumer signal cannot be seen from inside one consumer**, which is
  why the duty to report a local guard upstream applies even when the local fix
  was correct.
- **Consumers are derived at the moment they are needed and never stored** — see
  "Downstream loop", which now runs rather than being deferred.

### The public surface — the rulings, as events (#59)

**`version` has no default. Decided by the user on 2026-08-08**, and it is
theirs to reverse. A product judgement about the API's shape, not a derivation:
a later argument that a default is friendlier does **not** reopen it.

**What they were shown**, and why the question existed at all: two artifacts in
this repo required opposite things. `version.dart`'s shipped doc-comment said
the newest release is *"what you get unless you ask for an older one"* — which
promises a default of `latest` — while `CLAUDE.md`'s freeze invariant exists
because changing a selector's output "silently rewrites the profile picture of
every user of every app that depends on this package". A `latest` default makes
the *effective* selector move on upgrade, which is that failure by another
route. Three options, with what each costs:

| option | what a caller gets | what it costs |
|---|---|---|
| **required** | an avatar frozen at the version they named | every call site carries a `version:` |
| `latest` | the shortest call | `0.2.0` silently drops `<title>`; `0.3.0` redraws every `pixel` avatar |
| `v1_6_1` fixed | a default that never moves | the default is the *oldest* supported release, so a caller who does not think about it gets a `pixel` that differs from today's npm |

**What they chose:** required. `latest` stays on the enum — passing it is now an
explicit decision to track upstream's newest rather than to pin an avatar, and
its doc-comment says so instead of promising the default.

**The same reasoning already governs `size`**, which is why it is required too —
see the ladder's note on 2.0.3/2.0.4, whose default-size change stays out of the
version state only *because* the caller always supplies one. Both are pinned in
`api_surface_test.dart` against the source text, since Dart cannot be asked at
runtime whether a parameter has a default.

**The surface is a top-level function, `boringAvatarSvg`. Decided by the user on
2026-08-08** from a derived recommendation — an API-shape call, presented for a
yes/no rather than grilled. `BoringAvatar` was kept free for the widget the
module map already reserves it for.

**Every barrel export carries a `show`, and the reason is not the library it
names.** Without one, a re-export added *inside* an exported library reaches the
public surface with the barrel unchanged — so the guard in
`api_surface_test.dart`, which reads the barrel, sees nothing. Measured in #59:
an `export 'scene/scene.dart';` inside `version.dart` made `SvgNode`,
`SvgAttribute`, `SvgElement` and `escapeSvgText` importable from
`package:boring_avatars/boring_avatars.dart` with the whole suite green; with
the `show` in place the same edit leaves `SvgNode` an undefined class. The test
therefore pins two things — the exact export list, and that every entry has a
`show` — because the first alone is satisfied by a line that exports more than
it says.

**`lib/src/` stays importable, and that is not a contradiction.** `tool/` does
it deliberately. "Does not leak" means *not reachable from the barrel*, which is
what a pub.dev consumer is expected to import; Dart offers no stronger
enforcement short of moving files, and this project has no reason to.

---

## Step 4 — proof method per layer

| Layer | Real proof | Bar |
|---|---|---|
| **1 data — utilities** | `tool/parity` imports `utilities.js` **straight from the pinned reference tree** and calls the real functions; the values become `test/fixtures/<version>/utilities.json` | **Exact. No tolerance.** |
| **1 data — per-variant values** | **Not directly observable.** No component exports its generator — `generateData` / `generateColors` are module-private in all six — so per-variant values are proved *transitively* through layer 2, where every value that reaches the drawing appears as an attribute | via layer 2 |
| **2 scene** | our emitted SVG vs `test/fixtures/<version>/svg.json`, rendered from the **real npm package** through `react-dom/server` | **Byte-identical**, excluding generated ids (`useId`, `prefix__…`), which are internal references. **`<title>` is not excluded** — see hidden-state #16 |
| **2 scene — the picture, not the bytes** | `tool/crosscheck/` renders **upstream's own React output** and ours in the **same browser** and compares the screenshots | **0 differing pixels.** The one bar here with no tolerance to negotiate — see below |

### `tool/crosscheck` — the browser comparison whose bar is zero

**Both documents go through one browser, and that is the whole idea.** The
browser's own approximation error — circles up to 0.13 px inside true geometry,
shallow rotated edges up to 30/255 out (hidden-state #27) — applies identically
to each render and **cancels**. So the bar is **0 differing pixels**, with
nothing to relax when Chrome updates. It is the only bar in this project a
browser change cannot break, which is exactly what the layer-3 calibration below
*is* vulnerable to.

**It exists because no other check renders what upstream actually emits.** The
byte gate above normalises `id="…"`, `url(#…)` and `mask="…"` away on both
sides, and `tool/calibrate` hands Chrome **our** document by design. So anything
inside that hole is invisible to both. Demonstrated rather than argued: pointing
`ring`'s `<g mask="url(#…)">` at a mask that does not exist leaves every
per-name byte test **green** (measured — the group's `maskIdentifiers`
assertion, added in #37, is what catches it there), while this harness reports
22 468 differing pixels because the mask never applies. That assertion only
exists because someone anticipated *which* identifier mattered; this catches the
class without knowing.

**What it cannot see:** anything both documents get wrong the same way. It says
"upstream and this port draw the same picture", never "the picture is right".

```bash
dart run tool/crosscheck/emit.dart <work>    # our SVG, unnormalised
node tool/crosscheck/crosscheck.mjs <work>   # upstream fresh + browser + diff
```

Upstream is **re-rendered from the npm package**, not read from
`test/fixtures/`: those entries are stored normalised, and `mask="_"` has lost
its `url()` wrapper, so a fixture entry handed to a browser renders unmasked.
`playwright-core` drives the **system Chrome** (`channel: 'chrome'`), so nothing
downloads a browser and no path is hardcoded.

**Measured, #41 (2026-08-07) — the full roster for the first time:**

| | |
|---|---|
| checked | **1200** — 6 variants × 20 names × 5 palettes × `square` on and off, at size 320 |
| pixel-identical | **1150** |
| agreed refusals | **40** — `beam` × the empty palette, both `square` values: upstream throws and so do we, so there is no document on either side |
| ruled divergences | **10** — `sunset` × `punctuation`, both `square` values, five palettes |

`marble`'s 200 renders are **all pixel-identical**, including the blur, the
`overlay` blend and the filter region — through one browser, so the browser's own
approximation cancels. That is the bar this project has that a Chrome update
cannot break, and it is the reason the layer-3 calibration's failure to reach
≤1/255 (below) is not evidence of a wrong picture.

The ten are S-1 in the divergence ledger: upstream paints **0 pixels** for a
name containing an apostrophe, because its own `url(#…)` reference is not a
valid CSS url token. The harness lists those names explicitly and fails if the
difference *disappears* — that would mean the ruled repair stopped firing.

**The forty are S-2, and they are counted separately from the 950 on purpose.**
Both sides refusing is agreement — the strongest kind, since the only comparable
fact is *that* the input fails — but no pixels were compared, and a harness
reporting 990 identical renders when 40 of them were two exceptions would be
claiming evidence it does not have. The asymmetric cases are the interesting
ones and both are failures: upstream rendering where we refuse, or the reverse.

**All six are covered as of #41.** `marble` was the last one missing, and the
guard is what made adding it part of that change: `emit.dart` reads
`lib/src/variants/` and refuses to run if a variant gains a file without gaining
a line in its roster. It fired on `beam` in #38 and again on `marble` in #41 —
twice now, which is the whole argument for keeping it.

`square` is in the matrix here and **not** in the fixture matrix, which runs at
one value. That is the #37 lesson applied: a prop the matrix never varies is a
prop nobody has compared to upstream.

**It writes a page for human eyes**, `report.html` in the work dir: every case
as upstream / ours / a live `mix-blend-mode: difference` panel where **black
means identical**, differences sorted first, with filters. Two things about it
were only found by *opening it*, and both had the numbers saying 0 while the
picture said otherwise — the difference stack needs an **opaque black** backdrop
(over white, two agreeing transparent renders come out white), and each render
must be flattened onto that backdrop **before** the blend (a blend mode is
re-interpolated by the source alpha, so every antialiased rim grew a faint
coloured ring on cards that were byte-identical). A visual gate has to be looked
at, the same way a numeric one has to be watched failing.

`CROSSCHECK_LIMIT=<n>` caps the run for iterating on the harness. A capped run
says so in the summary, in the `PASS` line and in the report's own header — a
tool that quietly checked 20 of 800 and printed "PASS" is the silent-truncation
failure this project keeps writing rules about.

**A TOOL, not a gate.** `flutter test` never runs it — it needs npm, a browser
and a network install. Run it when a variant lands or the emitter changes.

**Two of the three fixture sections exist because a normalisation hid
something.** `maskIdentifiers` (#37) and `derivedIdentifiers` (#40) both record
ids *unnormalised*, because the byte sweep erases them on both sides and
therefore proves nothing about them. `sunset` is the sharper case: its gradient
ids are derived from the **name**, so the erased thing is a real derivation with
real edge cases, recorded per name across the whole corpus.

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

**And "has its own renders" is per *variant*, which took a third incident to
learn.** `sizePassthrough` held `marble` alone from #33 to #59, so five of the
six were compared to upstream at one size and to nothing at a second. It was
harmless while `size` was an argument to six separate builders and became a real
hole the moment #59 put a dispatch in front of them: measured there, hardcoding
`size: 80` on the `ring`, `beam`, `pixel`, `sunset` or `bauhaus` arm left **all
677 tests green**, because the main matrix renders at exactly that number.

**Then the completeness pass measured that fixing it had moved the hole, not
removed it.** With the section widened per variant but still running one name,
one palette and `square: false`, an arm honouring `size` only for
`Clara Barton` — or dropping it whenever `square` is set — was *still*
invisible. So the unit is not "the prop varies on every path that carries it"
either: it is **the prop varies on a path something else varies on too**.
`sizePassthrough` is now `<variant>|<name>|<size>|<sq|rd>`, and
`sizePassthroughStrings` carries the String half of `size`'s public type, which
`corpus.sizes` (a list of `int`) structurally could not record — until #59 that
half was a *deleted probe* plus a comparison against the package's own render.

**A prop's fixture section is also the thing that ages when the prop's type
widens.** `size` became `num | String` at the public seam in #59 and the section
kept recording integers, which is why `test/fixtures_test.dart` now guards the
string half by **reading** the emitted attribute rather than rebuilding it from
the key — React escapes an unrecognised value like any other, so `a"b` arrives
as `a&quot;b` and a guard that reconstructed the expected text would be
asserting its own copy of the escaper.
| **3 raster — regression** | our rasterizer vs **golden images committed to this repo** (raw RGBA under `test/goldens/`, not PNG — no encoder in the loop, so a decoder change cannot move a golden) | **0 diff, no exceptions.** Runs every `flutter test` |
| **3 raster — parity calibration** | our rasterizer vs a **real Chrome render** | three parts, each scoped to what its statistic can measure (settled 2026-08-11, event below): interior residues **≤1/255**; the curve-free control case seam-exact with worst edge **≤3/255**; curves and shallow edges **reported, ungated** — the residual there is Chrome's own (#27). Run **manually** when the rasterizer changes, not per commit |
| **widget** | a test asserting the produced `ui.Image` bytes against the goldens, taken at `rasterAvatarImage` inside `runAsync`, **not** through `pumpWidget` | as layer 3 |

**The widget bar says `rasterAvatarImage` because `pumpWidget` was measured
shut, not because it is easier.** A raster started from `build()` lives in the
test binding's fake-async zone while `compute` and `decodeImageFromPixels`
complete on real callbacks, and all three pump arrangements fail: inside
`runAsync` it deadlocks past seven minutes without failing, one pump after it
arrives with no image, two pumps hang at 3m30. `decodeImageFromPixelsSync` would
have removed the callback and is "not implemented on Skia", which is the test
backend. A future *created inside* `runAsync` has none of that, which is what a
caller of `rasterAvatarImage` is.

What that leaves unproved is everything the widget does *after* the raster
starts — the error path, the one-raster-at-a-time bound, dropping a stale
picture, and the widget-level leak. Four behaviours, named in
`test/widget_test.dart`'s header rather than left blank, and the length of that
list is itself the finding: **this widget's asynchronous half is structurally
unprovable under the current binding.** Opening it needs an injected decoder or
a test-only hook in `lib/`, which is a judgement about public surface and has
not been taken.

**"Observed at the screen" — discharged 2026-08-10, on both paths.** The example
(#78) is what carries it, and the two platforms are genuinely different code:
`compute` is a real isolate on native and a main-thread call on web, so seeing
one prove nothing about the other.

- **Web**: built, served, and looked at in Chrome at 1280x900. All six variants
  render, `beam` draws its faces, the palette cycles, and the SVG panel shows
  the document the avatars above it were rasterised from.
- **Native (Windows)**: run by the user with `flutter run -d windows` and
  reported working. The agent cannot run this one — it opens a window.

Fourteen concurrent rasters are on screen at first paint, because the variant
picker is drawn by the thing it picks. That was not planned as a test of the
one-raster-per-widget bound, but it is one, and it held.

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

**The old ≤1/255 edge bar was never met, and its replacement is above — the
ruling event is at the end of this section.** Recorded in #33 and executed for
the first time in #37 — including on `pixel`, which was merged in #36 without
it. Measured, comparing premultiplied (hidden-state #29):

| Case | Interior mismatches | Worst edge delta | Last run |
|---|---|---|---|
| `pixel-clara-default` | **0** | 71/255 | #39 |
| `ring-clara-default` | **0** | 66/255 | #39 |
| `ring-alice-pair` | **0** | 101/255 | #39 |
| `ring-clara-square` | **0** | 66/255 | #39 |
| `sunset-clara-default` | **0** | 71/255 | #39 |
| `sunset-empty-palette` | **0** | 71/255 | #39 |
| `bauhaus-clara-default` | **0** | 71/255 | #39 |
| `bauhaus-alice-pair` | **0** | 71/255 | #39 |
| `bauhaus-empty-name` | **0** | 71/255 | #39 |
| `marble-empty-name` | **0** | 71/255 | #41 |
| `marble-clara-default` | 2 | 71/255 | #41 |
| `marble-alice-pair` | 5 | 71/255 | #41 |
| `marble-clara-square` | 2 | **9/255** | #41 |
| `pixel-clara-100` | 0 | 53/255 | #83 |
| `pixel-clara-square-100` | **0** | **3/255** | #83 |
| `pixel-clara-210` | 0 | 63/255 | #83 |
| `ring-clara-101` | 0 | 52/255 | #83 |
| `bauhaus-translucent` | 417, **all 1/255** | 71/255 | #62 |
| `sunset-translucent` | **0** | 52/255 | #62 |
| `bauhaus-named` | **0** | 71/255 | #63 |
| `sunset-named` | **0** | 71/255 | #63 |
| `bauhaus-invalid` | **0** | 71/255 | #64 |
| `sunset-invalid` | **0** | 71/255 | #64 |
| `bauhaus-colour4` | **0** | 71/255 | #95 |
| `sunset-colour4` | **0** | 71/255 | #95 |

**⚠ `bauhaus-translucent` is why the interior bar is "≤1/255" and not "zero
count" — its 417 residues are all exactly 1/255, and under the settled bar
(event below) that is a pass with the mechanism still open as a candidate.**
It is the first case in this harness with a palette that carries
its own alpha, and the first where every stacking level's rounding is *visible*:
with an opaque palette the top shape hides the arithmetic underneath it. All 417
disagreements are exactly **1/255**, the same magnitude `marble`'s three rows
carry, and the **alpha channel agrees exactly at every one of them** — so this is
not the alpha product being wrong, which would move alpha first. The likely
mechanism is that we store straight alpha and divide back out per shape while a
browser composites premultiplied, which rounds differently; that is **inferred
from the shape of the disagreement, not measured**, and is a candidate rather
than a finding. `sunset-translucent` reaching interior 0 is the useful contrast:
its colours arrive through a gradient, which is sampled once per pixel rather
than composited in layers.

The interior column also gained a **worst delta** in #62. Until then the bar was
zero and a count said everything; 417 pixels out by 1 and 417 out by 40 are
different findings and five printed samples cannot separate them.

**⚠ Every row above `pixel-clara-100` rendered at the variant's own viewBox
side, and that is the one target where hidden-state #24 is inert.** Not a
tolerance problem and not a coverage gap anyone could see: `_cases` passed one
number to both the scene and the raster target, so the device scale was always
exactly 1, `pixel`'s tile edges always landed on pixel boundaries, and no two
shapes ever met *inside* a pixel. The harness's zeros were true and said nothing
about the row — the same shape as "a tripwire that cannot trip reads as
coverage", in a tool rather than a test. Asking for a different number turned out
to cost nothing structural, because `size` reaches `width`/`height` only and the
viewBox is a per-variant constant, so both sides still receive the same document.

**The four new rows carry a ruling, and `pixel-clara-square-100` is the one that
carries it.** It is the only case in the harness with no curve, so it is the only
one where a residue could mean anything: hidden-state #27 measures Chrome's own
curves up to 0.13 px inside ours, which is what the 71/255 in five rows above
already is. With the curve gone the run reports **784 partial pixels on each
side**, **zero** pixels Chrome fills that we leave translucent, and a worst edge
of **3/255**. See hidden-state #24 for the ruling and #83 for the run.

**The seam counters were added because the interior/edge split cannot answer
this question.** Where two abutting tiles differ in colour, Chrome's own 3x3
neighbourhood is non-uniform whatever it does about the seam, so the pixel is
filed as an *edge* and its delta lands beside the mask curve's 71 — invisible.
Only same-coloured neighbours reach the interior bucket. `compare.dart` therefore
also reports *"opaque in Chrome, translucent here"* and, beside it, the partial
count on **both** sides — because a zero in the first number means one of two
opposite things (the seam exists and Chrome conflates identically, or there is no
seam to disagree about) and only the second number separates them.

**⚠ `marble`'s rows read differently from every other row in this table, and
the difference is the point.**

* Its interior mismatches are **not zero** — 2 to 5 pixels of 6400 — and every
  one of them is exactly **1/255**. They appear only where `overlay` saturates a
  region flat (an opaque backdrop returns itself for every source), because that
  is the only place a blurred variant *has* a 3x3-uniform pixel to classify. See
  hidden-state #42: for `marble` the interior statistic is otherwise vacuous, so
  its 0s carry less information than anyone else's, not more.
* `marble-clara-square`'s worst edge is **9/255** against everyone else's 71 —
  and that is the same 71, at the same pixel (71, 15), on five other rows.
  Dropping the mask's corner radius removes it. So the 71 this table has carried
  since #37 is **the mask's own curve** (hidden-state #27), not the variant's
  drawing, and `marble-clara-square` is the row that separates the two.
  **It read 5/255 before the region was corrected, and that smaller number was
  the feature being absent rather than the port being accurate** — the clip
  simply was not happening there. Doing it with a hard pixel-centre test gave
  11; antialiasing the boundary with the same integrator every other shape
  uses gave 9. Chrome's own clip on that render moves 23 pixels by up to 6,
  so what is left is the boundary's shading, not its position. A calibration
  number going *down* is not evidence of anything until you know the
  capability was running.
* The blur itself is the one mechanism in this package that can meet the bar.
  SVG 1.1 §15.17 specifies the three-box algorithm exactly rather than leaving
  it to the renderer, so both sides compute the same convolution: measured on a
  step edge, our kernel and Chrome's agree to **0–1/255** for every sigma from 3
  to 12. Above about 12 Chrome stops following it (31/255 at sigma 20, 65 at
  sigma 30 — Skia downsamples for large radii); `marble`'s sigma is 8.4–9.1
  device pixels, inside the range where the spec is what Chrome does.

**Interior 0 is the part that matters for a *solid* region and it holds**: every
solid area matches Chrome exactly, which is what proves the arc sweep
directions, the paint order and the nine-slot colour map. The edge deltas are
all on curves or on shallow rotated straight edges, and hidden-state #27
measures why: **Chrome's circles are up to 0.13 px small and its shallow edges
up to 0.12 px large; ours are neither**.

**⚠ Interior 0 is not evidence about a thin shape, and #39 measured that.**
Deleting `bauhaus`'s stroked `<line>` outright leaves interior mismatches at
**0** on all three of its cases — a 2-unit stroke has no 3×3-uniform pixel, so
`_isEdge` files the whole rule as edge. See hidden-state #42, which used to name
only gradients. Read this table as "the solid regions agree", never as "the
picture is right".

**The bauhaus rows were also split by boundary**, because the aggregate hides
which edge disagrees. `bauhaus-empty-name`, whose hash is 0 so every transform is
the identity, has **zero** disagreement outside the two curves. The rotated cases
disagree only on shallow straight edges, and exact analytic coverage
(Sutherland–Hodgman clip + shoelace) puts our integrator within **0.03/255** of
the truth and Chrome up to 30.6 away. Ours is the correct one.

#### The calibration bar, re-scoped — the settlement, as an event

**Directed by the user on 2026-08-11** (*"1번 판정 정리하고 pana 돌려보자"*),
**settled as a derivation** from the measurements this section already
recorded — so it falls to a better derivation, and the *direction to settle*
is what was theirs. Recording the split matters: a later argument against the
numbers reopens the derivation on its merits; only the user reopens whether
the bar should have been re-scoped at all.

**What the derivation rests on, all previously recorded:** the old bar
("interior 0, edge ≤1/255") was written in #33 and **never met by any run
that ever existed** (#37) — so no regression can hide under changing it, which
is what the never-lower-a-threshold rule protects. It was unmeetable *in
principle* for half the shapes: hidden-state #27 measures Chrome's own circles
up to 0.13 px inside true geometry and its shallow rotated edges 30/255 out,
against this integrator's ≤0.03/255 from exact analytic coverage — on a curve,
the bar measured the reference's error, not ours. Meanwhile every statistic
that *can* be exact was already at its floor: gradients interpolate to ≤1/255
(#41), the blur to 0–1/255 in `marble`'s sigma range, every interior residue
is exactly 1/255 (the compositing-rounding class, #23/#29), and the curve-free
control built in #83 reads seams 0 / edge 3/255. And twice-measured (#37,
#39): `flutter test` killed every wrong picture ever pushed through this
harness while the Chrome comparison killed none — the gate role was never
here.

**The bar is now three parts** (implemented in `compare.dart`, and the FAIL
path was watched firing before this was written): interior worst delta
≤1/255; the curve-free control (`pixel-clara-square-100`) seam-exact with
worst edge ≤3/255 — 3 being that case's measured value kept as a regression
tripwire, not a derived constant; everything on a curve or shallow edge
reported ungated with #27 as the named reason. Tightening is always
legitimate; loosening any of the three is a new ruling.

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
- any change to a **published** version selector's layer-1 output. **This row was
  vacuous until 2026-08-12** — it named no selector because nothing was
  published. `0.1.0` shipped `v1_6_1`, so it names one now, and the trigger fires
  on a one-line change to what that selector draws

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

  **Areas that already carry a record.** The filing step checks this list
  *before* proposing a spine, so a cluster with a home never gets a second one.

  | Record | Status | Area it governs | Conformance items |
  |---|---|---|---|
  | [ADR-0001](../adr/0001-what-a-colour-declaration-means.md) — what a colour declaration means | **Accepted** 2026-08-10 (#71) | every colour-valued attribute the rasterizer reads: `fill`, `stroke`, `stop-color`, and any that follow | **all done**: #69, #62, #63, #64 |

  A **proposed** record counts for this check exactly as an accepted one does —
  it is already doing a spine's job (a hypothesis, a roster, an explicit
  not-yet-decided list), so a spine beside it would split the roster in two.
- **`CONTEXT.md`** — does not exist; created lazily by `/domain-modeling`.
- **`.pubignore`** — must exclude `docs/`, `.github/`, `CLAUDE.md`, `tool/`,
  `test/fixtures/`. A root `.pubignore` disables git-based file listing. The
  pub.dev archive cannot be un-published.
- **`example/`** — does not exist yet; becomes a gate the day it does.

**Record-worthy here.** One area has been re-litigated and promoted: the
rasterizer's colour vocabulary, now ADR-0001. It arrived the way the promotion
rule predicts — a 2-axis grid (property × declaration state) being decided one
cell at a time across #69 and #64, plus two hidden-state rows (#20 and #44)
requiring opposite things in the same file. The remaining candidate, by
construction, is the JS↔Dart semantics rules, if the hidden-state list starts
needing a *rule* rather than another row. Promotion lands in `docs/adr/`.
**No project exception** to how spines link or where write-back lands — the
skill's defaults govern.

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

`tool/crosscheck/` is the layer-2 *picture* comparison: upstream's own React
output and ours, through the **same** browser, bar **0 differing pixels**. It is
the only check that renders what upstream actually emits, and the only bar a
Chrome update cannot break. Full description and the measured numbers are in
Step 4. It reports the variants it did **not** cover by name — today `marble`
alone, which is not ported.

`tool/mutate/` is the **test-trust gate made re-runnable**. Step 3 requires
turning a fix off and watching the test go red; until #41 that was done with a
throwaway script every time, and a commit could say "12 of 12 mutants died"
with nothing in the tree able to check it. Same rule as `tool/versions`: a
claim about a measurement whose evidence cannot be re-run is one nobody can
check. Cases live in `tool/mutate/cases/<issue>-<area>.json` and are literal
substitutions, never patterns.

It has **four** outcomes — `killed`, `SURVIVED`, `NO MATCH`, `NO TESTS` — and
the last two are the ones this repo has been burnt by five times. A stale case
exits non-zero, so it cannot rot quietly. Full description in its README.

```bash
node tool/mutate/run.mjs cases/41-marble.json          # 32 cases, all killed
node tool/mutate/run.mjs cases/41-marble.json --only=A # layer 1 only
node tool/mutate/run.mjs cases/51-watch.json           # 10 cases, runner: node
```

A case file may name a **`runner`** — `flutter` (the default, so every existing
case file is untouched) or `node`. #51 added the second one because the
watcher's logic is a `.mjs` under `tool/`, which `flutter test` cannot see at
all; a suite the gate cannot reach is exactly where an unkilled mutant would
sit forever. A runner is a command **and** a way to count tests that ran —
without the count, `NO TESTS` collapses into `SURVIVED` and the harness's third
outcome stops working.

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

`.github/workflows/upstream-watch.yml` + `tool/watch/`, as of #51. A weekly
scheduled job that files an issue when upstream moves. **It watches `src/lib/`
blob SHAs, not version numbers.** Full description, and the measured numbers
behind every claim here, in `tool/watch/README.md`.

**This paragraph used to say "v1.9.0, v1.10.0, v2.0.1 and v2.0.2 changed
nothing under `src/lib/` … of 28 tags, only ~16 are real work". #51 measured
it and two thirds of that was wrong**, which is what the routing table means by
external facts being verification targets — including the ones this file
asserts. Measured over the 28 tags in the pinned reference tree:

| Claim | Measured |
|---|---|
| v1.9.0, v1.10.0, v2.0.1 unchanged | **true** |
| v2.0.2 unchanged | **false** — `types.ts` and `index.tsx` both moved |
| "only ~16 tags are real work" | 28 tags → **18** distinct `src/lib` trees; **9** tags identical to their predecessor |

**And the stronger argument was the one nobody had made.** `2.0.3` and `2.0.4`
are on npm with **no git tag at all** — the tags stop at `v2.0.2`, and `latest`
is `2.0.4`. A release-triggered watcher is not merely noisy; it is **blind to
upstream's two most recent releases**.

**The fact was not new; carrying it here was.** `#45` has recorded it since it
was written ("주의 — 태그가 없는 버전"), as a note about where to *read* those
two versions from. Nobody had moved it the twelve inches into the watcher's
rationale, or into README's npm-versus-tag section, which named only the
opposite-direction example (npm `1.2.1` republishing older code) until #51.
That is the shape worth noticing: a measured fact sitting correctly in one
issue is not the same as a fact the project reasons with.

This is a **deliberate exception to the house "no CI" convention**: it is a
watcher, not a gate. It runs only on `schedule` and `workflow_dispatch`, never
on push or pull_request, so it is a check on no branch and cannot block a merge
— and `main` carries no branch protection to make it one (measured: the
protection endpoint 404s). Its failure mode is silence, not obstruction.

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
| `0.1.0` | everything: harness, primitives, scene, all six variants, the public SVG surface, **the rasteriser's arbitrary scale (#58), the `BoringAvatar` widget (#80), the banded rasteriser that keeps it off the frame on both platforms (#80), the example (#78), and the colour vocabulary the rasteriser reads (#71 → #62 → #63 → #64, plus #95 — the Color 4 remainder the #64 pass found unlearned; user ruling 2026-08-11, same criterion as the 08-10 ruling below: publishing first would put a release that refuses valid colours in people's hands)** |
| `0.2.0` | the `<title>` gate (hidden-state #16) — **one change** |
| `0.3.0` | `pixel`'s second colour-index path — **one change**, and the only one in scope where the drawing moves |

**Why the colour work moved into `0.1.0` — user ruling, 2026-08-10.** It had no
milestone at all, and the agent proposed `0.3.0` alongside the Chrome parity
sweep. The user ruled the other way: *"0.1.0 도 사람들이 쓰는 릴리스"* — delay is
acceptable, breaking `0.1.0`'s coherence is not.

The test was whether it breaks that coherence, and it does not. **The release
axis is the upstream output state, and colour parsing is not on that axis** —
the palette is the caller's, so nothing here creates a fourth output state or
touches the `v1_6_1` selector. Principle 3 is untouched.

The stronger argument is that shipping without it is what would be incoherent.
`0.1.0` currently carries **two palette contracts**: `boringAvatarSvg` passes any
string through, and `BoringAvatar` throws `ArgumentError` on anything that is not
`#RRGGBB` (`lib/src/widget/boring_avatar.dart:355`). The README spends a section
explaining that asymmetry away. And #64 in particular is a one-way door in the
wrong direction: ruling it *after* publish means one input yields an exception
for `0.1.0` users and a browser-matching render for the next release's, where
ruling it before publish means the package only ever had one answer.

**What this does not license.** #50 stays in `0.3.0` on its own merits, not on
preference — two of the seven combinations it counts require `#45`'s code to
exist, so it cannot run against one output state. Its circular blocked-by is
still unruled and was deliberately not encoded as a dependency edge.

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
- **Every covered version is measured; the committed fixture is per output
  state.** Collapsing the *releases* does not license collapsing the *evidence* —
  the `<title>` divergence was found precisely because 1.6.1 and 1.7.0 were
  rendered separately, and a plan that rendered one and claimed four would have
  missed it. What that protection actually requires is a **render and a
  comparison** per covered version, which is what `tool/versions/group.mjs` runs;
  it does not require a second directory of identical bytes under
  `test/fixtures/`, and a second copy is not a second measurement.

  **Decided by the user on 2026-07-29**, superseding this rule's earlier wording
  ("per-version fixtures are still generated for every covered version"), which
  described something the repo has never done: `test/fixtures/` has held one
  directory per output state since #33, and `tool/parity/` installs one upstream
  per state. A product judgement, theirs to reverse — *"문구까지 지킬 필요는
  없고 결과가 중요함"*, the same criterion they applied to the release boundary
  one level up.

  **What they were shown.** For the `v1_6_1` group, three artefacts and three
  answers, which do not all agree:

  | | 1.6.1 | 1.6.2 | 1.6.3 |
  |---|---|---|---|
  | git `src/lib` tree | `3cca55f5…` | same | same |
  | published npm bundle | `c9491576…` | same | **`f4636f1d…`** |
  | rendered output | — | identical | identical |

  1.6.3's bundle differs by **exactly 34 bytes**: the trailing
  `//# sourceMappingURL=index.js.map` comment and its newline. Everything
  executable is byte-identical, verified with `cmp`.

  **So the rule's teeth are in the middle row, not the top one.** "The git tree
  hash matches, therefore there is nothing to do" is a *source* argument for an
  *output* claim, and this project has already paid for that confusion once —
  `1.11.0` shares `1.11.1`'s source intent and emits different markup
  (hidden-state #37). Here the npm artefacts genuinely diverged and the
  divergence happened to land in a comment. Next time it may not, and the check
  that would catch it is the render, not the blob.

**`1.11.0` is not in the table, and that is deliberate** — see "The states in
scope" above. It emits junk attributes no other version does.

**`0.1.0` ships SVG only. — SUPERSEDED 2026-08-09; see the reversal below.**
Decided by the user on 2026-07-29: the public surface
is a function returning the SVG string, which is what upstream itself produces
and is a complete product on its own — `boringAvatarSvg`, built in #59. The
widget and the rasteriser scaling it needs (#58) follow in a later release
rather than blocking the first one. *(This sentence cited #59 as one of the
deferred items until #59 itself was worked; #59 is the surface `0.1.0` ships,
not something it defers.)* A Flutter caller therefore needs a third-party SVG renderer for `0.1.0`, and
the package's determinism guarantee applies to the raster path only — say so in
the README rather than leaving it implied.

#### The reversal — the ruling, as an event

**`0.1.0` ships the widget too. Decided by the user on 2026-08-09**, and it is
theirs to reverse. The 2026-07-29 ruling above is kept rather than deleted:
what it was decided *against* is the point of this entry.

**Why it was reopened at all.** Not by a better argument — by a measurement the
earlier decision could not have seen. The 07-29 ruling accepted one cost
knowingly: a Flutter caller reaches for a third-party SVG renderer, and those
pixels are not ours. What nobody had checked is whether they are even the right
*picture*. #78's probe checked.

**What they were shown.** Our SVG through `flutter_svg`, rasterised at each
golden's own size and compared to the golden the suite pins:

| variant | differing | distinct colours (golden / flutter_svg) |
|---|---|---|
| `marble` | 89.0% | 2411 / 177 |
| `beam` | 28.8% | 48 / 35 |
| `pixel` | 22.2% | 164 / 6 |
| `sunset` | 23.8% | 225 / 156 |
| `ring` | 31.7% | 282 / 393 |
| `bauhaus` | 27.8% | 305 / 187 |

In every row the pixels that are transparent in the golden and painted by
`flutter_svg` came to *exactly* that variant's transparent-pixel count — 1236
for the 80×80 trio, 1572 for `ring`, 220 for `beam` — and the opposite
direction was zero. The mask was not applying at all.

**Isolated to one attribute.** A hand-written mask with `rx="40"` masks
correctly; ours does not, and ours says `rx="160"` because upstream writes
`rx={size * 2}`:

```
rx= 40   1241 transparent px      a circle
rx= 80   3021 transparent px      a degenerate shape
rx=160   no mask — the rect stayed square      ← what we emit
rx=999   no mask — the rect stayed square
```

SVG 1.1 §9.4 clamps `rx` to half the width, so the shape *is* a circle in a
browser — which is why our goldens hold one, and what `tool/crosscheck` puts
against upstream's own render at a bar of zero differing pixels.
`flutter_svg` does not clamp. `<mask>` itself is fine: `mask-type` and
`maskUnits` make no difference, only the clamp does.

`marble` loses a second thing. `vector_graphics_compiler`'s parser has no
`filter` in its element table, and the sole occurrence of "filter" in its 2449
lines is the attribute name `'color-interpolation-filters'`; an unhandled
element prints once and is skipped, so the Gaussian blur vanishes.
`mix-blend-mode: overlay` *is* supported, which is why the blend survives and
only the blur is gone.

**What they chose:** put the widget in `0.1.0`. Their reason was the direction,
not the schedule — *"매력적이겠지만 맞는 방향으로 가야함"*, said against the
alternative of publishing the finished SVG-only release now and shipping the
widget as `0.2.0`. Recording that is the point: the rejected option was cheaper
and was rejected on purpose, so proposing it again needs a new fact, not a new
argument.

**What it costs.** The first publish waits on #58 → #80 → #78, and #80 has no
design yet — the widest unknown in the chain. `0.2.0`'s `<title>` gate and
`0.3.0`'s `pixel` path move out by the same amount.

**What this does not decide.** Nothing about building a general-purpose SVG
renderer. The rasteriser stays narrow and refuses what it cannot draw, which is
what makes the determinism claim provable; a renderer that must accept arbitrary
input cannot refuse, and would degrade silently — which is the failure that
produced this entry. Whether to report the `rx` clamp to `flutter_svg` is a
separate, unfiled question.

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

#### The widget's execution model — the ruling, as an event

**The rasterisation leaves `build()`, `compute()` is the mechanism, and `0.1.0`
does not wait for the web half. Decided by the user on 2026-08-10**, and it is
theirs to reverse.

**What reopened it.** #80's completeness pass measured that `rasterAvatarImage`
contains **no `await` at all** — `async` and `unawaited` had moved only the
decode, and the decode was never the cost. The widget therefore shipped doing
the one thing #80's own body had excluded *by measurement*: a synchronous raster
inside `build()`. The doc-comment at `cf92d5d` recorded that hole rather than
closing it, which left the no-ceiling derivation conditional on a fix that did
not exist.

**What they were shown.** Three options against a 16.7 ms frame, with
`rasterizeScene`'s wall-clock (measured in #80, after warm-up):

| variant | 80 px | 120 px | 210 px |
|---|---|---|---|
| `marble` | 22 ms | 43 ms | 124 ms |
| `beam` | 14 ms (at 36) | 83 ms | 206 ms |
| `pixel` | 3 ms | 20 ms | 57 ms |

| | buys | costs |
|---|---|---|
| **A — off the UI thread** | the frame back on native | an isolate hop; **nothing on web** |
| **B — yield once, then run** | nothing measurable | — |
| **C — accept it, document the cost** | `0.1.0` ships now | the ticket's own premise stays falsified |

**They rejected C first, before the mechanism was chosen** — the sequence
matters, because C was the agent's standing recommendation at the time and its
argument (that a later fix is additive, so choosing C forecloses nothing) still
stands unrefuted. It lost on priority, not on logic, which is exactly the kind
of call that is theirs and not derivable.

**B was then eliminated by reading the SDK, not by taste**, when they pushed
back that it looked weak. `compute`'s two implementations, read at Flutter
3.41.9:

- `_isolates_io.dart:22` — `return Isolate.run<R>(() => callback(message), …)`.
  On native, `compute` **is** A; nothing is lost by not calling `Isolate.run`
  directly.
- `_isolates_web.dart:19-20` — `await null; return callback(message)`. That is a
  **microtask**, and the microtask queue drains before the browser paints, so it
  yields nothing to the platform and the callback runs on the main thread. On
  web, `compute` degrades precisely to B, and B's own measurement is that the
  stall is unchanged in length.

**So `compute` was chosen for what the SDK already carries**: the web branch is
Flutter's to maintain rather than a first platform `import` in `lib/`, and no
size threshold is needed — 3 ms off the frame beats 3 ms on it — which is what
keeps the package from inventing a policy it says it never invents.

**Then measured in a browser, because a source reading is not a measurement.**
A throwaway Flutter web app rasterised `marble` twice at each size — directly
and through `compute` — while a plain `setInterval` *outside Dart entirely*
recorded every tick it missed. A blocked main thread cannot tick, so the gap it
misses **is** the block. Chrome 151, release builds:

| physical px | dart2js direct | dart2js `compute` | WasmGC direct | WasmGC `compute` |
|---|---|---|---|---|
| 120 | 168 ms | 147 ms | 368 ms | 365 ms |
| 240 | 522 ms | 530 ms | 1315 ms | 1275 ms |
| 480 | 1990 ms | 1982 ms | 5061 ms | 5159 ms |

In all twelve runs the missed gap matched Dart's own stopwatch to within 8 ms,
and Chrome's Long Tasks API reported each as a **single** long task of the same
length. `compute` moves nothing on web — measured, not inferred.

Two facts nobody had asked for came out of the same run:

- **Web is ~4x slower than native at the same size.** `marble` at 120 physical
  pixels is 43 ms native (#80) and 168 ms under dart2js.
- **`--wasm` is not the escape hatch it looks like.** WasmGC ran this code
  **2.2–2.6x slower than dart2js** at every size. Whatever the cause, "build for
  wasm" cannot be offered as the web answer without re-measuring it — and it was
  never checked before this run.

So the web limitation is larger than the SDK reading alone implied: a
320-logical avatar at a 1.5 device pixel ratio freezes the tab for **two
seconds** under dart2js and **five** under WasmGC. It does not move the ruling —
nothing here is made worse by shipping, which is the ground the "do not wait"
half rests on — but it raises what the unchosen web fix is worth.

**Its validity condition — measured, and the mechanism is earned.** The one
objection that survived the SDK reading was that nobody had measured isolate
spawn plus buffer transfer, so a probe decomposed it rather than timing the
whole thing, because "`compute` is slower" would not have said *why*. Seven
repetitions each, under `flutter test`:

| | median |
|---|---|
| spawn alone (`compute` returning an `int`) | **0.3 ms** |
| spawn + returning 25 600 bytes | 0.4 ms |
| spawn + returning 176 400 bytes | 0.4 ms |

The hop costs **under a millisecond and does not grow with the buffer** — same
isolate group, so the return is not a serialisation. Against the cheapest thing
this package draws (`pixel` at 80, single-digit milliseconds) that is a few per
cent, which is exactly why no size threshold is needed and why the derivation
that refused to invent one holds. In the same run `compute` was not measurably
slower than the direct call at any size.

**A second question opened while measuring it, and is deliberately not answered
here.** The absolute raster costs #80 recorded could not be reproduced in that
session — `marble` at 80 came out at about twice its recorded 22 ms — and the
session's own numbers contradicted each other (an AOT build measured *slower*
than JIT at 210 px, which cannot be true), so the machine was not quiet enough
to adjudicate. One thing was ruled out: **#58 did not regress it.** The revision
before that change and the current one measured the same, back to back
(`pixel` 8.2 → 6.9 ms, `marble` 43.5 → 46.9 ms). The recorded costs are
therefore **unverified rather than wrong**, and re-measuring them on a quiet
machine is its own task, not this one.

**Re-measured on 2026-08-10, and the premise above was the thing that was
wrong.** Waiting for a quiet machine was never the condition, because this
machine cannot be made quiet and the comparison never needed it to be. Two
throwaway probes ran the raster directly, outside `flutter test`, over eight
runs — four JIT (`dart run`) and four AOT (`dart compile exe`), alternating
which mode went first so a warm-up or thermal order effect could not favour
either.

**What the noise turned out to be.** Inside a *single* AOT process, `marble` at
80 physical pixels measured **39.3 ms** in the first table and **286.2 ms** in
the second, minutes apart — same binary, same code path, same run. That is the
whole explanation for last session's impossible AOT-slower-than-JIT: it was
never an observation about AOT, it was an observation about what else the
machine was doing. A minimum over nine repetitions does not defend against
contention that lasts for minutes, which is the trap, because taking a minimum
*looks* like it does.

**So the boundary of what is measurable here is itself the result:**

- **Absolute cost is not measurable** closer than an order of magnitude. Across
  the eight runs the same cell moved by up to 7x. No number in the README should
  be read as a spec, and it now says so.
- **Any ratio measured back to back is measurable, and survives the same
  contention intact** — because both halves meet the same conditions and the
  conditions divide out. The banded-versus-sync overhead came out at 0.71–1.25x
  centred on **1.00** across all forty cells, *including* inside the run whose
  absolute numbers were inflated tenfold. Slicing the raster costs nothing.
- **AOT versus JIT stays unadjudicated**, and now for a stated reason rather
  than a shrug: the two differ by less than the run-to-run drift does.
- **The recorded costs are reproduced**, so the "unverified" flag is discharged.
  `marble` at 80 / 120 / 210 measured 33.4 / 90.5 / 233.1 ms in the quietest AOT
  run against 33 / 80 / 237 recorded.

**And a fact nobody had asked for, which is the reason this was worth doing.**
Cost is **discontinuous at the design size**. `scene_raster.dart` sends a rect to
the closed-form `RasterRect` only when its matrix `isTranslationOnly`, which
holds exactly when the device scale is 1 — that is, when the target equals the
variant's own viewBox side. Swept one pixel either way, twice:

| | at the side | one pixel off |
|---|---|---|
| `pixel` (all axis-aligned rects) | 2.8 ms | **6.5x** |
| `bauhaus` (some rects rotated) | 7.3 ms | 1.9x |
| `ring` (no axis-aligned rects) | 27.7 ms | flat |

`ring` is the control, and it is what makes this an attribution rather than a
dip someone noticed: the effect is present exactly where the mechanism predicts
it and absent where it predicts nothing. It is also robust to everything above,
because it is a ratio between neighbours measured seconds apart.

**It was undefended.** With `isTranslationOnly` forced false, **758 of 760 tests
stayed green** — every golden included, because the two integrators agree and
that agreement is the whole point of the pair. A change that stopped taking the
fast path would have made the cheapest variant six times dearer with a clean
suite. `test/raster_fast_path_test.dart` now pins it structurally rather than by
timing, and the two failures in that run were its own.

**What is still not known.** Why `pixel`'s discount is 6.5x and `bauhaus`'s only
1.9x is read from the code (`bauhaus` rotates some of its rects, so only part of
its work can take the fast path) and not measured per shape. Nothing depends on
it.

**What this does not decide.** The **web fix is unchosen.** Two candidates were
enumerated and neither was ruled on, because neither is needed to ship:

- **Banded rasterisation** — split the scanline walk into bands and yield
  between them, which is what the browser ecosystem does by hand (time slicing)
  and the only candidate that fixes web *and* native. Rows are independent by
  construction, so bands do not move a byte. It restructures `lib/src/raster/`,
  which is where #58's completeness pass found the missed gradient axis and five
  mutation gaps — the most expensive evidence surface in the repo. It sits
  *under* `compute` and does not replace it.
- **The browser's own SVG renderer**, via a platform view on web. Uniquely
  available to this package because the goldens *are* Chrome's output, so
  upstream fidelity would be higher, not lower. Costs a `lib/` platform branch,
  and cross-browser byte-identity is unmeasured.

A general-purpose web-worker path was rejected outright, not deferred: Flutter
web has no isolate equivalent, so it means compiling the rasteriser a second
time as a separate entry point — two copies of the geometry, which is the
divergence seed `CLAUDE.md` names.

**What it costs.** `0.1.0` gains a probe, a mechanism change to the widget, and
a documented web limitation; it does not gain a web fix. Web callers keep
today's behaviour exactly — this ruling makes nothing worse there, which is the
ground the "do not wait" half rests on. **— That half is SUPERSEDED the same
day; see immediately below. The rest of the entry stands.**

#### The web half joins `0.1.0` too — the ruling, as an event

**Decided by the user on 2026-08-10**, hours after the entry above, and it is
theirs to reverse. What changed was not the argument but the size of the thing
being deferred: the browser measurement landed in between.

**What they were shown.** The twelve-run table above — `compute` moving nothing
on web, a 320-logical avatar freezing the tab for two seconds under dart2js and
five under WasmGC, and `--wasm` measuring *slower* rather than being the escape
hatch. Against that, the two unchosen candidates and their costs, and the option
of shipping `0.1.0` without a web fix on the ground that nothing there gets
worse.

**What they chose:** put the web fix in `0.1.0`. The rejected option — ship now,
fix web later — was cheaper and was rejected on purpose, which is the same shape
as the reversal that put the widget in `0.1.0` in the first place.

**Which candidate is *not* their call, and that is recorded on purpose.** They
were asked and the question was withdrawn: **the browser's own SVG renderer is
foreclosed by invariant 4**, not merely dispreferred. "The same input yields the
same bytes on every platform … and rendering backend" is incompatible with
letting a browser's rasteriser decide the bytes — it is the *same sentence* that
forecloses `Canvas`, one level further out, and the widget's own doc-comment
already cites it. Choosing it would first require ruling that the determinism
guarantee does not cover web, which is a change to what the package *is* rather
than a choice of implementation, and it was not put to them in those terms. If
it ever is, this paragraph is what it has to overturn.

**So: banded rasterisation**, and it is a derivation — it falls to a better
derivation, not to a re-vote.

**The two mechanisms compose, which is why `compute` survives the reversal.**
`ComputeCallback` is `FutureOr<R> Function(M)` (`isolates.dart:19`), so an
*async* banded rasteriser is a legal `compute` callback. On native the isolate
runs it and the inter-band yields cost nothing; on web `compute` runs it on the
main thread and those same yields are what keep the frame alive. **One code
path, no platform branch in `lib/`** — which is the property that made the
web-worker candidate unacceptable in the first place.

**What it costs.** `0.1.0` grows by a rasteriser restructure. Three things are
known to be hard before starting: `marble`'s Gaussian is a whole-image operation
and does not band without overlap; the `Float64` layer has to stay alive across
yields, so peak memory lasts longer rather than shorter; and `lib/src/raster/`
is where #58's pass found the missed gradient axis and five mutation gaps, so
this buys a completeness pass rather than reasoning its way out of one.

**What this does not decide.** Nothing about *native* keeping `compute` — that
is settled above and unaffected. Nothing about band size, which is an internal
constant like the flattening tolerance and not caller policy.

**What banding costs on native — measured, back to back on the two revisions,
because the absolute numbers this session had proved untrustworthy:**

| | before | after |
|---|---|---|
| `pixel` @80 | 3.5 ms | 4.1 ms |
| `marble` @80 | 25.8 ms | 32.6 ms |
| `marble` @120 | 72.5 ms | 79.7 ms |
| `marble` @210 | 205.6 ms | 237.2 ms |

**A 10–26% tax**, and it is paid everywhere, not only on web. It is accepted
rather than optimised away, on the ground that on native the whole raster runs
inside a `compute` isolate where the tax costs no frame at all, and on web it is
what buys one. The obvious tuning — yield every *n* rows instead of every row —
was considered and **not taken**: at `marble` @210 a row is already ~1.1 ms, so
even n = 8 overshoots the 4 ms slice, and the coarsening would hurt exactly
where responsiveness matters most. Recorded so the next reader does not
re-derive it, and so the number is a decision rather than a discovery.

**And it was verified in a browser, which is the only place the claim was ever
about.** Everything up to that point was unit-level — a `Timer.run` getting its
turn proves the loop yields, not that a tab stays responsive. Same witness as
the original measurement, a `setInterval` outside Dart, reporting the **worst
single gap** per phase in Chrome:

| physical px | before (one block) | after (banded) |
|---|---|---|
| 120 | 213 ms | **17 ms** |
| 240 | 731 ms | **17 ms** |
| 480 | **2362 ms** | **17 ms** |

Flat in the size, and Chrome's Long Tasks API agrees independently: long tasks
appear in every blocking phase and in **none** of the banded ones.

**The web tax is far larger than native's, and it moved the default.** Total
wall time at 480 px went 2629 ms → 10130 ms at the 4 ms slice this shipped with
— because every yield on web is a `setTimeout(0)` the browser clamps to about
4 ms, so a slice *at* the clamp spends most of its time waiting rather than
drawing. Swept:

| slice | total | worst stall |
|---|---|---|
| 4 ms | 10130 ms | 28 ms |
| **8 ms** | **5450 ms** | **23 ms** |
| 16 ms | 5144 ms | 32 ms |
| 33 ms | 3407 ms | 47 ms |
| 100 ms | 2310 ms | 110 ms |

8 ms strictly dominates 16 ms — the only such pair on the curve — so it is the
default, at a 2.1x tax. The reasoned choice (4 ms, "comfortably inside a frame")
was the worst value on the curve, which is the entry's own argument for
measuring defaults rather than deriving them.

**And the earlier "unverified" note is partly discharged.** In this quieter run
`pixel` @80 measured 3.5 ms against #80's recorded 3 ms and `marble` @80 25.8 ms
against 22 ms — close enough to say the record was not wrong, only re-measured
under load. The two larger sizes are still about 1.7x their recorded figures,
which remains open.

#### The widget's asynchronous half ships unproven — the ruling, as an event

**Decided by the user on 2026-08-10**, and it is theirs to reverse.

Four widget behaviours have no test and are verified by reading: the failure path
(report + drop the stale image), the one-raster-at-a-time bound, dropping a
changed picture while keeping a rescaled one, and the widget-level leak. The
obstacle is structural and measured, not laziness — see the Step 4 bar above.

**What they were shown.** Two options, and the asymmetry between them:

- **A — ship it.** The four stay unproven, named in `test/widget_test.dart`'s
  header. Adding the seam later is additive.
- **B — add a testing seam now**, before `0.1.0` freezes the public surface: an
  injected decoder, or a test-only hook in `lib/`.

**What they chose: A.** The argument that decided it is one this repo keeps
reaching for — **A can become B and B cannot become A.** A public surface can be
added later and cannot be withdrawn, so B spends something irreversible to buy
something that is still available afterwards.

**What it costs, stated rather than implied.** The completeness pass on this very
change found a defect of exactly the kind these four tests would catch — a
concurrency bound deleted in silence while 752 tests stayed green. So the cost is
not hypothetical: it is that the next change to this widget has the same blind
spot, and the mitigation is that the blind spot is *written down* rather than
discovered again.

**What this does not decide.** Nothing about *how* the seam would look if it is
ever added, and nothing about the test binding itself — if a future Flutter makes
`pumpWidget` and real callbacks cohabit, the whole question dissolves and none of
this needs reversing.

### `pana` — 160/160 on the scoring version, now that the machine can run it

**Measured 2026-08-11, on macOS: `pana` 0.23.17 — the version pub.dev scores
with — runs clean and scores 160/160.** Conventions 30/30, documentation
(20%+ coverage, example) in full, all six platforms plus WASM-ready, static
analysis 50/50, dependencies 40/40 including the `pub downgrade` lower-bound
check. The one note it left — two undocumented symbols on `BoringAvatar` —
was fixed in the same change.

The earlier state of this section is kept because its lesson still holds for
anyone on Windows: measured 2026-08-10 there, 0.23.17 fails before analysing
anything (`Sandbox output folder must not contain ":"` —
`_detectGitRoot` → `GitTool` → `SandboxRunner.runSandboxed` runs
unconditionally, and every absolute Windows path contains a drive colon; being
outside a git repository does not avoid it). The 2026-08-10 score was
therefore taken with 0.22.19, which predates the sandbox check.

**This section said the hole was closed. It is open again whenever the session
is on Windows, which #42 measured it to be** (Flutter 3.41.9, Node v26.4.0,
`MINGW64_NT`). The sentence had read "on this machine that hole is closed — the
environment moved to macOS at #59", which quietly turned *one session's
measurement* into a standing property of the project. The machine alternates;
the hole alternates with it.

So `pana` is the one gate whose availability is **machine-conditional**, and
that is why it is not in the Step 7 block above. On macOS run 0.23.17 and expect
160/160. On Windows it cannot run at all, and the honest substitute is
**pub.dev's own analysis of the published version**, which is authoritative
rather than a local approximation:

```bash
curl -s https://pub.dev/api/packages/boring_avatars/score
```

It reports `0/0` with only an `is:recent` tag until pub.dev has analysed the
release — that is "not yet scored", not "scored zero", and the two are easy to
confuse at a glance.

### Downstream loop

**Live as of `0.1.0` (2026-08-12).** Derive consumers on the spot and **never
store the list here** — a stored list is a derivable fact that rots the day a
consumer or a constraint changes:

```bash
for d in ../*/; do grep -l 'boring_avatars:' "$d/pubspec.yaml"; done
```

Run at `0.1.0`: **no sibling consumers.** That is the expected answer for a
first release and it is not a standing one — re-derive, do not quote this line.

**A `0.1.0` release obliges consumers to do nothing, and that is structural
rather than lucky.** Releases here are additive by construction: a new upstream
state is a new selector value, never an edit to a shipped one, so the loop's
usual work — raise the constraint, delete the workaround the fix made
unnecessary, flip the test that pinned the old bug — has nothing to act on.
Say that explicitly in each release rather than leaving it implied; "nothing to
do" and "nobody checked" look identical from outside.

The one thing that *would* oblige them is a raised SDK floor, which is why it
sits in the boundary section above rather than here.

---

## War-story index

Per-incident evidence lives in [`lessons.md`](lessons.md), indexed by step. The
hidden-state list above is *pre-incident* enumeration, not evidence; move a
row's story into `lessons.md` the first time it actually catches a defect, and
cite the issue number.

**Forty-eight entries as of #51** — counted, not incremented. The number read
"thirty-six" until #51 added two and counted the file, which is its own small
instance of the lesson that pass recorded: a number in a doc reads as settled
because it is written down. The ones that have caught something more than once:

| Rule | Caught in |
|---|---|
| A validity condition came due, and only the condition could tell | #63 |
| A ticket's own acceptance criteria put a valid value in the invalid cell | #62, #64 (a whole notation family), #95 (the closure claim itself) |
| One sentence governs two values, and the port applied it to one | #41, #64 (a third reader) |
| A model with two candidates that no golden can distinguish is measured, not chosen | #62 |
| A harness that never ran in the condition cannot have cleared it | #83 |
| A zero means one of two opposite things, and one more counter separates them | #83 |
| A minimum over N repetitions is not a defence against a busy machine | #80 follow-up |
| Two paths that agree make the choice between them invisible | #80 follow-up |
| Going asynchronous deletes guarantees nobody wrote down | #80 |
| A default is a measurement, not a derivation | #80 |
| A pump cannot bridge two zones, and a hang is not a failure | #80 |
| A file existing is not the feature existing | #1 → closed #8 |
| A row nobody can act on yet is a row nobody checks | #38, #41 |
| A pattern written with the wrong line ending matches nothing | #39, #41 |
| A tripwire that cannot trip reads as coverage | #34, #39 |
| A mutation surviving means one of two opposite things | #34, #37 |
| A substitution that matches nothing reads as a surviving mutation | #34, #36, #37, #39 |
| A runner can report a false *kill* — the worse direction | #39 |
| A byte gate catches what a picture never shows | #36 |
| A golden that agrees with itself proves nothing | #36 |
| A bar can be recorded, believed, and never run | #33 → #37 |
| A gate can be blind to a whole capability, not just to a defect in it | #39 |
| A suite can be green for a mechanism it never runs | #36 |
| A value nothing reads is not a value that works | #37, #40, #39 |
| The hidden-state list is a hypothesis, and gets things wrong | #34, #39, #38 |
| A concurrent agent in the same worktree invalidates a measurement | #39 |
| "0 warnings" shipped a 44 MB build artifact | #1 |
