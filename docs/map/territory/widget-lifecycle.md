# widget-lifecycle

## What it is

`BoringAvatar`, the package's Flutter consumer seam: a `StatefulWidget` that
validates its inputs at `build`, turns `size × devicePixelRatio` into a physical
side, and keeps on screen an image rasterised by this package's own rasterizer
— off the frame, one raster at a time, blanking when the *picture* changes and
keeping the old image when only the *resolution* does. It owns the comparable
input value (`_AvatarKey` / `sameDrawingAs`), the draw loop (`_drawLatest`), the
failure path (`_rasterFailed`), the isolate hand-off (`rasterAvatarImage` →
`compute(_rasterBytes)` → `decodeImageFromPixels`), and the proof bar for all of
it. Where the image *lands* on the device grid is
[pixel-placement](pixel-placement.md); how the raster yields is
[banded-rasterisation](banded-rasterisation.md).

## Governing decisions

**None.** No ADR governs the lifecycle (ADR-0002 governs placement only).
Four user rulings, recorded in theflow and carried here — each theirs to
reverse:

**1. `0.1.0` ships SVG only — 2026-07-29, SUPERSEDED 2026-08-09.** The public
surface was to be `boringAvatarSvg` (#59) alone, with the widget and the
rasteriser scaling it needs (#58) in a later release; a Flutter caller would
use a third-party SVG renderer, and the determinism guarantee would cover the
raster path only. Kept because what the reversal decided *against* is the
point.

**2. The reversal: the widget goes into `0.1.0` — user ruling, 2026-08-09.**
- *Why it reopened:* not a better argument but a measurement the earlier ruling
  could not have seen. #78's probe rendered our SVG through `flutter_svg` at
  each golden's size against the committed golden:

  | variant | differing | distinct colours (golden / flutter_svg) |
  |---|---|---|
  | `marble` | 89.0% | 2411 / 177 |
  | `beam` | 28.8% | 48 / 35 |
  | `pixel` | 22.2% | 164 / 6 |
  | `sunset` | 23.8% | 225 / 156 |
  | `ring` | 31.7% | 282 / 393 |
  | `bauhaus` | 27.8% | 305 / 187 |

  In every row the pixels transparent in the golden and painted by
  `flutter_svg` equalled that variant's whole transparent count (1236 for the
  80×80 trio, 1572 `ring`, 220 `beam`), the reverse zero: **the mask was not
  applying.** Isolated to one attribute: a hand-written mask with `rx="40"`
  masks (1241 transparent px), `rx="80"` gives a degenerate shape (3021),
  `rx="160"` — what we emit, because upstream writes `rx={size * 2}` — and
  `rx="999"` give **no mask**. SVG 1.1 §9.4 clamps `rx` to half the width;
  `flutter_svg` does not (`mask-type`/`maskUnits` make no difference).
  `marble` loses its blur too: `vector_graphics_compiler`'s parser has no
  `filter` element (the only "filter" in its 2449 lines is
  `'color-interpolation-filters'`); `mix-blend-mode: overlay` survives.
- *What they chose:* the widget in `0.1.0`, against publishing the finished
  SVG-only release and shipping the widget as `0.2.0`. Their reason was the
  direction, not the schedule: *"매력적이겠지만 맞는 방향으로 가야함"*. The
  rejected option was cheaper and rejected on purpose — re-proposing it needs a
  new fact, not a new argument.
- *What it cost:* the first publish waited on #58 → #80 → #78, #80 then having
  no design; `0.2.0` and `0.3.0` moved out by the same amount.
- *What it did not decide:* a general-purpose SVG renderer. The rasterizer
  stays narrow and refuses what it cannot draw — that refusal is what makes the
  determinism claim provable; a renderer that must accept arbitrary input
  degrades silently, the failure that produced this entry. Whether to report
  the `rx` clamp to `flutter_svg` is a separate, unfiled question.

**3. The execution model: raster leaves `build()`, `compute()` is the
mechanism — user ruling, 2026-08-10.** (Its "web does not wait" half was
superseded the same day — see [banded-rasterisation](banded-rasterisation.md).)
- *What reopened it:* #80's completeness pass measured that
  `rasterAvatarImage` then contained **no `await`** — `async`/`unawaited` had
  moved only the decode, never the cost — so the widget shipped a synchronous
  raster inside `build()`, which #80's own body had excluded by measurement.
- *What they were shown:* `rasterizeScene` wall-clock after warm-up (#80):
  `marble` 22 / 43 / 124 ms at 80 / 120 / 210 px; `beam` 14 (at 36) / 83 / 206;
  `pixel` 3 / 20 / 57 — against a 16.7 ms frame; and three options: **A** off
  the UI thread (frame back on native, nothing on web), **B** yield once then
  run (nothing measurable), **C** accept and document (ships now; the ticket's
  premise stays falsified).
- *What they chose:* **C rejected first**, before the mechanism — C was the
  agent's standing recommendation and its argument (a later fix is additive)
  still stands unrefuted; it lost on priority, not logic. **B eliminated by
  reading the SDK** when they pushed back that it looked weak:
  `_isolates_io.dart` — `compute` *is* `Isolate.run`, so on native `compute`
  is A; `_isolates_web.dart` — `await null; return callback(message)`, a
  microtask that drains before the browser paints, so on web `compute`
  degrades exactly to B. `compute` chosen for what the SDK carries: the web
  branch is Flutter's to maintain (no platform `import` in `lib/`), and no size
  threshold is needed — 3 ms off the frame beats 3 ms on it — so the package
  invents no policy.
- *Then measured in a browser* (throwaway app, `setInterval` outside Dart
  recording missed ticks; Chrome 151, release): `marble` direct vs `compute`,
  dart2js 168/147, 522/530, 1990/1982 ms and WasmGC 368/365, 1315/1275,
  5061/5159 ms at 120/240/480 physical px. Missed gap matched Dart's stopwatch
  within 8 ms in all twelve runs; Long Tasks API saw one long task each.
  **`compute` moves nothing on web** — measured. Two side facts: web is ~4x
  native at the same size; WasmGC is 2.2–2.6x *slower* than dart2js.
- *Validity condition, measured:* isolate hop decomposed, 7 reps under
  `flutter test`: spawn alone 0.3 ms median; + 25 600 B returned 0.4; +
  176 400 B 0.4. Under a millisecond and flat in buffer size (same isolate
  group — no serialisation), so no threshold; `compute` was not measurably
  slower than direct at any size.

**4. The asynchronous half ships unproven — user ruling, 2026-08-10.**
- *What they were shown:* four behaviours with no test, verified by reading
  (listed under Known holes), the obstacle structural and measured (see Design
  model, "proof bar"). **A** — ship, keep them named in `test/widget_test.dart`'s
  header, add a seam later additively. **B** — add a testing seam now (injected
  decoder or test-only hook in `lib/`), before `0.1.0` freezes the surface.
- *What they chose:* **A**, on the argument this repo keeps reaching for —
  **"A can become B and B cannot become A"**: a public surface can be added
  later and not withdrawn.
- *What it costs, stated:* the completeness pass on that very change found a
  defect of exactly this kind — the one-raster-at-a-time bound deleted in
  silence while 752 tests stayed green (war story: [lessons.md, "Going
  asynchronous deletes guarantees nobody wrote down (#80)"](../../agents/lessons.md)).
  The next change to this widget has the same blind spot; the mitigation is
  that it is written down.
- *What it does not decide:* how a seam would look; nothing about the binding —
  if a future Flutter lets `pumpWidget` and real callbacks cohabit, the
  question dissolves and nothing needs reversing.

## Design model

From the source and the rulings above (status: **ruling-governed, no record**).

**Inputs and validation, at `build`.** `_checkPalette` refuses any entry
`parseCssColour` cannot read (`ArgumentError` naming `colors`); an empty
palette is deliberately *not* refused — that is S-2 (`beam` throws from the
raster, five variants degrade). `size` must be finite and positive, checked
*before* the multiply because `.round()` on a non-finite double throws an
`UnsupportedError` naming nothing (S-4's rule: the seam names the argument);
`(size × dpr).round() < 1` gets its own message. No upper bound on `size`, a
decision: the package refuses what it cannot honour, and a large avatar it can
honour slowly — cost is O(area), `marble` holds ~86 B of `Float64` per output
pixel, and the budget is the caller's (stated in `BoringAvatar.size`'s
doc-comment). The ratio is read with `MediaQuery.devicePixelRatioOf`, not
`MediaQuery.of`, so a keyboard or text-scale change does not cost a re-raster.
No `title` parameter: `<title>` is filtered out before raster, so the widget
passes `title: null`; accessibility goes through `Semantics(image: true)` with
an optional `semanticLabel` (not defaulted to `name`, which is often an id).

**`_AvatarKey` — five inputs decide *what*, one decides *how finely*.**
`pixels` (physical side; logical size and ratio never appear separately) vs
`name`, `colors`, `version`, `variant`, `square`. `sameDrawingAs` compares all
but `pixels`; `==` adds `pixels`. Colours are compared **by content and
copied** (`List.unmodifiable`): an inline list literal in `build()` is a new
object every frame, and identity would re-raster forever; copying stops a later
mutation from changing what is on screen.

**`_sync` — blank on change, keep on resize.** If an image is up and the new
key is not `sameDrawingAs` the settled one, the image is dropped (disposed in a
post-frame callback) — a recycled row must not show the previous person's face
under the new name. When only `pixels` moved, the old image stays (scaled) until
the sharper one lands — otherwise every size or ratio change flashes. No
`setState` here: it runs inside `build`.

**`_drawLatest` — one raster at a time, latest wins.** `_drawing` is the bound:
before the raster went async concurrency was structurally one; going async
removed that silently, and without the flag every rebuild with a new key
(animated `size`, rotation, recycled row) would start another `compute`, each
holding O(area) buffers and, on web, a slice of the one thread. The loop
re-reads `_wanted` after each raster, so a burst of ten sizes draws once, not
ten times. An image arriving after unmount or for a superseded key is disposed,
not assigned. A replaced image is disposed post-frame (the frame being painted
may still hold it — the framework's own image widget does the same).

**`_rasterFailed` — report and drop.** A raster that throws is marked settled
*as failed* (retrying would report forever; a different key is picked up next
turn), reported via `FlutterError.reportError` with library `boring_avatars`,
and the stale image is cleared — both failures were live before: the error
vanished into the zone, and the old avatar stayed on screen under new fields.

**`rasterAvatarImage` — where the isolate boundary can go.** Top-level
`_rasterBytes` (a named target, not a closure) receives a `_RasterRequest`
record of primitives and enums — what makes it a legal `compute` message —
builds the scene, awaits `rasterizeSceneAsync`, then premultiplies (the buffer
is straight alpha, `PixelFormat.rgba8888` is premultiplied), sliced on
`defaultRasterSlice`. The `ui.Image` decode stays on the calling thread because
an engine resource cannot cross an isolate.

**The proof bar is `rasterAvatarImage` inside `runAsync`, not `pumpWidget` —
because `pumpWidget` was measured shut, not because it is easier.** A raster
started from `build()` lives in the test binding's fake-async zone while
`compute` and `decodeImageFromPixels` complete on real callbacks. All three
pump arrangements fail: inside `runAsync` it deadlocks past seven minutes
without failing; one pump after arrives with no image; two pumps hang at 3m30.
`decodeImageFromPixelsSync` would remove the callback and is "not implemented
on Skia" — the test backend. A future *created inside* `runAsync` has none of
that, which is what a caller of `rasterAvatarImage` is. (War story:
[lessons.md, "A pump cannot bridge two zones, and a hang is not a failure
(#80)"](../../agents/lessons.md).) The bar: produced `ui.Image` bytes equal the
goldens, premultiplied, worst channel delta 0 — as layer 3.

**Outside input:** `size` (unbounded above by decision), `name` (any string),
`colors` (any list). Work and memory scale with `pixels²`; concurrency is
bounded to one raster per widget.

### Observed at the screen (2026-08-10, both paths)

The example app ([example-app](example-app.md), #78) discharges it, and the two
platforms are different code — `compute` is an isolate on native and a
main-thread call on web. **Web:** built, served, looked at in Chrome at
1280×900: all six variants render, `beam` draws faces, the palette cycles, the
SVG panel shows the document the avatars were rasterised from. **Native
(Windows):** run by the user with `flutter run -d windows`, reported working
(the agent cannot — it opens a window). **Fourteen concurrent rasters** are on
screen at first paint, because the variant picker is drawn by the thing it
picks — not planned as a test of the one-raster-per-widget bound, but it is
one, and it held.

### Raster cost record (one machine; absolute numbers move up to 7x)

#80's recorded costs could not be reproduced in the session that measured the
hop (`marble` @80 ~2x; an AOT build measured *slower* than JIT at 210 px, which
cannot be true) and were flagged **unverified, not wrong**; #58 was ruled out
as a regression (`pixel` 8.2 → 6.9 ms, `marble` 43.5 → 46.9 ms, back to back).
**Re-measured 2026-08-10** over eight alternating JIT/AOT runs outside
`flutter test`: inside a *single* AOT process `marble` @80 measured 39.3 ms and
286.2 ms minutes apart — the noise was the machine, and a minimum over nine
reps does not defend against minutes of contention. Absolute cost is not
measurable closer than an order of magnitude here (README says so); ratios
measured back to back are; AOT vs JIT stays unadjudicated (the difference is
below the drift). `marble` 80/120/210 = 33.4 / 90.5 / 233.1 ms in the quietest
AOT run against 33 / 80 / 237 recorded — "unverified" discharged. In the later
banding run `pixel` @80 3.5 vs #80's 3 ms and `marble` @80 25.8 vs 22 ms — close;
the two larger sizes stayed ~1.7x their recorded figures, which remains open.
The cost discontinuity at the variant's design size found in the same run is
**moved** to [coverage](coverage.md).

## Code

- `lib/src/widget/boring_avatar.dart` — `BoringAvatar` (fields and their
  doc-comments, incl. the `size` cost table), `_AvatarKey`,
  `_AvatarKey::sameDrawingAs`, `_RasterRequest`, `_rasterBytes`,
  `rasterAvatarImage`, `_BoringAvatarState` (`_wanted`, `_settled`,
  `_drawing`, `_image`, `dispose`, `_checkPalette`, `_sync`, `_drawLatest`,
  `_rasterFailed`, `build`).
- Tests, `test/widget_test.dart`: header (the four unproven behaviours, named);
  `_bytesOnScreen` ("… is handed to Flutter byte-identical", every `clara`
  golden case through `rasterAvatarImage` in `runAsync`); `_noLeak` ("every
  image the hand-off creates can be released" — proves the function, not the
  widget); groups "the palette this surface accepts is narrower, and it says
  so", "a size that is not a size is refused, naming the argument", "a parent
  tighter than `size` puts Flutter's sampler back in".
- Example: `example/` (see [example-app](example-app.md)).

## Reference behaviour

- Flutter SDK `foundation/_isolates_io.dart`, `_isolates_web.dart`,
  `isolates.dart` (`ComputeCallback`) — read at 3.41.9 (#80), re-read at 3.47.1.
- `flutter_svg` / `vector_graphics_compiler` vs SVG 1.1 §9.4 `rx` clamp and
  §15 filters — measured #78, 2026-08-09 (table above).
- `rendering/image.dart` (`RenderImage`): the framework widget this one mirrors
  for post-frame disposal, clone ownership and `hitTestSelf` — see
  [pixel-placement](pixel-placement.md).

## Cross-cutting invariants

- [frozen-selector-output](../invariant/frozen-selector-output.md) — the widget
  is pinned to the same goldens as layer 3; `_rasterBytes`'s premultiply is the
  only transformation allowed between golden and `ui.Image`.
- [selector-coverage-copies](../invariant/selector-coverage-copies.md) —
  `_bytesOnScreen` maps `-second-index` golden keys to `v1_10_1` by hand.
- [physical-pixel-rounding](../invariant/physical-pixel-rounding.md) — `_BoringAvatarState.build` sizes the buffer with `(size * dpr).round()`.
- [version-required-everywhere](../invariant/version-required-everywhere.md) — `BoringAvatar`'s `required this.version`, guarded by its own source-text test.

## Blast radius

- [banded-rasterisation](banded-rasterisation.md) — "a slow avatar is late, not
  stalled" and the no-ceiling `size` decision hold only while the raster yields
  with a macrotask; and the premultiply here shares its slice constant.
- [pixel-placement](pixel-placement.md) — `_sync` keeps an old-resolution
  buffer up across a ratio change; placement's filter predicate is what keeps
  that scaled interval honest.
- [colour-declarations](colour-declarations.md) — `_checkPalette`'s contract is
  exactly `parseCssColour`'s grammar.
- [public-svg-surface](public-svg-surface.md) — the widget's parameters mirror
  `boringAvatarSvg`'s vocabulary "so an avatar moved between them is the same
  avatar"; `size` is deliberately narrower (`double`, not `num | String`).
- [scene-model](scene-model.md) — `_RasterRequest` must stay primitives and
  enums to cross `compute`; the scene is built inside the isolate.
- [goldens](goldens.md) — `_bytesOnScreen` reads `test/goldens/*.rgba` and the
  `clara` case roster (asserts 13 cases, 6 square).
- [example-app](example-app.md) — the only place the async half is observed
  (fourteen concurrent rasters).

## Known holes / open

- **Four behaviours unproven, verified by reading only** (user ruling A,
  2026-08-10), named in `test/widget_test.dart`'s header: (1) `_rasterFailed`
  reports and drops the stale image (the error surviving the isolate hop *is*
  tested); (2) `_drawLatest`'s one-raster-at-a-time bound; (3) blank on a
  picture change, keep on a resolution change (both branches need an `_image`
  first, which never arrives under the binding); (4) the widget-level leak.
  Opening them needs an injected decoder or a test-only hook in `lib/` — a
  public-surface judgement not taken.
- **#80's larger-size costs** (`marble` @120/@210) stayed ~1.7x their recorded
  figures; open.
- **AOT vs JIT** unadjudicated — below this machine's run-to-run drift.
- **`_checkPalette`'s rationale** has aged since #64 and was flagged, not ruled
  (see [colour-declarations](colour-declarations.md)).
- Whether to report the `rx` clamp to `flutter_svg` — unfiled.
