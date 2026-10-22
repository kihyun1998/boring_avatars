# pixel-placement

## What it is

Where the widget's finished buffer lands on the device pixel grid, and with
which sampler. The buffer is rasterised at `(size × dpr).round()` physical
pixels; this territory paints it onto whole device pixels of the space the
widget paints into (`snappedAvatarRect`), decides whether the hand-off may
honestly claim `FilterQuality.none` (`avatarLandsOnePixelPerPixel`), and owns
the render object that does both (`PixelSnappedImage` /
`RenderPixelSnappedImage`), which replaces `RawImage`. It also owns the
measurement apparatus that placement claims are checked with: the `widget_test`
placement harness, the on-device integration test, the web Playwright
measurement, and the #117 spike. What the buffer *contains* is
[widget-lifecycle](widget-lifecycle.md) and the raster territories.

## Governing decisions

- [ADR-0002 — when the box and the pixel grid disagree](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md)
  (Accepted 2026-08-18, user ruling on #110; amended 2026-08-18 on #117).
  Conformance items: #110 (PRs #111–#114), #117.
  - **R1** grid alignment beats containment: the buffer is drawn on whole
    device pixels even if that overshoots the box by up to one device pixel.
  - **R2** the drawn extent comes from the box (`round(box × dpr)`), not the
    buffer — a squeezing parent keeps squeezing the drawing.
  - **R3** tangency is not tradeable: the avatar is a circle inscribed in its
    box; option C (`floor − 1`) is rejected here.
  - **R4** alignment is best-effort at paint time; a layer moved without a
    repaint (scroll) goes stale, accepted (flutter/flutter#111302).
  - **R5** (#117 additional ruling) where one buffer pixel cannot cover one
    device pixel, do not claim `FilterQuality.none`; use `low`. The user chose
    "half a pixel of blur instead of a fold in the broken interval".
  - **R6** (#117 correction) snap on the grid of **the space the canvas is
    in** (`local`), not the screen (`localToGlobal`) — the engine already
    rounds the enclosing layer, so correcting for it too applies it twice.
  - *What the user was shown for R1–R4* (the `Round or Floor` brief,
    2026-08-18): A `round` / B `floor` / C `floor − 1`; the 105-combination
    render measurement (`RawImage` 21 wrong → now 6) as *measured*, the
    35-combination overflow counts (A 25 / B 17 / C 0) as *arithmetic*; that B
    closes only 8 of 25 because the origin still has to sit on a boundary; that
    C costs tangency; that B and C narrow the accepted `size`; and the unknown
    (whether real callers clip exactly at the box — the one reporter does not:
    its `ClipRRect` is 15 logical px away). The scroll limitation was found
    after the brief and shown before the ruling; it applies equally to A, B, C.
    **They chose A — keep `round`.** A caller who later wants containment gets
    an **opt-in flag, never a moved default** (R3, the ADR's last table row —
    the reason the record exists).
  - *What they were shown for R5:* the reported root (antialiased round clip)
    disproved on a real-engine screen capture; raster costs (`marble` 45 px
    26 ms, 66 px 38 ms, 108 px 93 ms, 240 px 374 ms, debug JIT); three options
    and their costs; the unknown of what broke 1:1 in the reporting app (found
    after the ruling: compositing-layer origin, which motivated R6).
  - *Rejected alternatives on record:* wrapping the avatar in its own
    `RepaintBoundary` (no effect measured; adds a layer, can *create* R4);
    baking the fraction into the buffer (a frame late; only fixes the
    stationary case); drawing vectors via `Canvas` (identity change, refused
    by `CLAUDE.md`).
- `CLAUDE.md` invariant 4 (determinism across backends) is the reason the
  snap is done here rather than left to the backend's rounding.

## Design model

From ADR-0002 and the source (status: **record-governed**).

**Three things cannot all hold when `size × dpr` is fractional**: buffer 1:1 on
device pixels, drawing inside the box, drawing filling the box. 68 does not fit
in 67.5. R1 + R3 pick the first and third.

**`snappedAvatarRect(local, box, dpr)`** — pure; `left`, `top`, `width`,
`height` each `round(v × dpr) / dpr`. Guarantees: all four are whole device
pixels, and the result is within half a device pixel of layout. Width from the
box (R2): taking the buffer's extent painted a 240-px avatar across a
20-logical box (caught by #110's completeness pass, mutation B1). Snaps
`local` (R6): with no enclosing layer, `local` *is* the screen position and the
two rules are bit-identical, so #110 lost nothing.

**Non-finite guard: adopted, then deleted as a no-op.** Read from
`RenderEditable._snapToPhysicalPixel` (Flutter's caret snap, same expression):
a degenerate ancestor (`Transform.scale(0)`) gives a non-finite position.
`0.3.1` computed `onGrid(at) − at` and had to branch the non-finite case out;
after R6 rounding alone carries `NaN`/`∞` through unchanged, so the branch
decided nothing — the mutant deleting it survived the whole suite (case B3,
retired). The caret snap uses `localToGlobal` and does not contradict R6: a
caret is painted by the object that computes it, with no layer of its own, so
its two spaces coincide.

**`avatarLandsOnePixelPerPixel(toScreen, box, buffer, dpr)`** — R5's
predicate. True only when the transform to screen is a pure translation (exact
comparisons on the 2-D linear part and perspective terms — a scale of
`1.0000001` resamples as much as `1.1`; non-finite fails every comparison, the
safe direction) **and** `round(box × dpr)` equals the buffer on both axes. A
fractional translation is deliberately *not* misalignment (the snap absorbs
it). False cases: scale, mirror, rotation, projection, a squeezed box, and the
interval after a ratio change while `_sync` keeps the older buffer up. This
narrows invariant 4's claim without spending it: where false, which column
nearest-neighbour keeps was already the sampler's.

**`RenderPixelSnappedImage`** — mirrors `RenderImage`'s checklist (war story:
[lessons.md, "Replacing a framework render object inherits its whole checklist
(#110)"](../../agents/lessons.md)): holds a *clone* and disposes it;
`set image` drops a value that `isCloneOf` the current one (else an unchanged
avatar would swap handles every frame); intrinsic size is the buffer's logical
side, constrained by the parent's tight `SizedBox`; `hitTestSelf` returns
`true` (measured: 0 taps vs `RawImage`'s 1 under `GestureDetector`, mutation
B2). `paint` takes `getTransformTo(null)` once (the same walk `localToGlobal`
does, and the only place the linear part is visible), snaps `offset`, records
`debugPaintedDestination` inside an `assert`, and draws with `isAntiAlias =
false` in both branches (edge treatment held fixed so the filter change stays
attributable) and `FilterQuality.none` or `low`.

**The backend rounds for you, so a rendered pixel cannot price the snap.**
Skia with `isAntiAlias` off already rounds a destination rect whose width is
whole device pixels: deleting the origin snap left every rendered row green
(measured #110). Leaning on that is the Skia-vs-Impeller dependence invariant 4
refuses — and the engine's own layer snapping was removed once
(flutter/flutter#111145) — so the snap stays, asserted where it is *made*
(`snappedAvatarRect`, `debugPaintedDestination`). War story: [lessons.md, "A
mutant the backend kills for you is a mutant your test cannot (#110)"](../../agents/lessons.md).

**Accepted residues.** (a) Clip at exactly the box: where `round` rounds up
(45 logical at 1.5 = 67.5 holding 68), a tight clip shaves the excess — 105
combinations of ratio × inset × clip, `RawImage` wrong in 21, this in 6, the 6
a subset of the 21. (b) Scroll staleness (R4): after a 7.3-logical scroll at
1.5, `paint` had not re-run and the recorded destination was **11.2 device
pixels** stale; a stationary row is on the grid, a scrolling one not until it
repaints. (c) Web: Chrome does not round the enclosing layer and its surface
is fractional, so nothing lands whole whatever this package does.

### The placement harness and its traps (#110, `test/widget_test.dart`)

Placement is separable from how the buffer is made: hand `PixelSnappedImage`
an image built in `runAsync`, screenshot the enclosing `RenderRepaintBoundary`
at `pixelRatio: dpr`, and extent, position and partial-coverage count are
readable in **device** pixels (at the default `pixelRatio: 1.0` the artefact is
resampled away). The four async behaviours are unreachable because they are
asynchronous; placement never was.

- **The ancestor is a parameter.** `paint`'s offset is relative to the
  enclosing layer, and `ListView` gives every child one. A twelve-row sweep
  over ratio × inset stayed green with the defect intact under an inner
  boundary — 69 device px for a 68-px buffer, 272 partly covered. The sweep
  now runs per ancestor (`_pixelSnap`'s `ancestors` map; war story
  [lessons.md, "The sweep varied everything except the backdrop (#110)"](../../agents/lessons.md),
  and #83's "A harness that never ran in the condition cannot have cleared it").
- **`toImage` is upstream of the composite.** `RenderRepaintBoundary.toImage`
  re-rasterises the subtree offscreen and never composites onto the window —
  where the layer rounding happens. Every #110 measurement went through it,
  which is why R6 was invisible until #117 (28 fixture cells clean through it
  while the screen showed 94-level differences; the `toImage` fixtures were
  deleted). **Only a screen capture validates R6.** War story: [lessons.md,
  "The instrument was upstream of the defect…(#117)"](../../agents/lessons.md).

### On a real backend

**Integration test** — `example/integration_test/pixel_snap_test.dart`, under
`IntegrationTestWidgetsFlutterBinding`, on whatever engine the device has. Run
manually (needs a device, opens a window):
`cd example && flutter test integration_test/pixel_snap_test.dart -d windows`.
**Measured 2026-08-18, Windows at ratio 1.5:** a 61-px buffer painted 61×61 at
(21, 21) where `inset × ratio` is 20.5. Green. Three load-bearing choices, each
cost a red run:
- *Size derived from the ratio* — the defect needs `size × dpr` fractional, not
  the ratio; at 100% every integer `size` lands whole and the test would pass
  without entering the condition. It solves for a box half a device pixel past
  an integer.
- *`square: true`* — extent is read off alpha; a disc's top row can quantise to
  zero coverage in the scanline integrator (measured 61×60 for the disc vs
  61×61 square, same engine and buffer).
- *Capture boundary outside the padding* — `toImage` renders `Offset.zero &
  size` of its boundary, so a tight boundary *is* a clip at the box; measured
  that way it read 61×60 at (0, 1), the harness reproducing the clip limitation.

(The test still captures with `toImage`, so it checks extent/origin on a real
engine but not post-composite layer rounding — see Known holes.)

**Web** — integration tests are closed (`flutter test -d chrome`: *"Web devices
are not supported for integration tests yet"*; `flutter drive` needs a
`chromedriver` the machine lacked). Build the example for web, serve it, drive
a Playwright context with a **real `deviceScaleFactor`**, measure the
device-resolution screenshot:
`cd example && flutter build web --release` then
`browser.newContext({deviceScaleFactor: 1.25})`, `screenshot scale:'device'`.
**Measured 2026-08-18, Chrome 151 at 1.25:** canvas 1375×1125 for a 1100×900
viewport; every avatar exactly `(size × dpr).round()` device px — picker
`size: 30` → 37×37 (all five unselected), gallery `size: 72` → 90×90.
- **Do not fake the ratio** by overriding `window.devicePixelRatio`: Flutter
  sized its canvas at 1.25 while the browser stayed at 1.0 and rescaled it by
  0.8, smoothing away every one-pixel artefact — a run that could not detect
  the defect.
- **The ratio is not the nominal number.** Chrome hands Flutter
  `1.2499999701976776` (float32 round-trip): `30 × dpr` = 37.4999991 → 37, where
  nominal 1.25 predicts 38. Measuring 37 and expecting 38 reads as one lost
  column from arithmetic alone. Take the ratio the platform reports.
- **Measurement traps:** selecting avatar pixels by *saturation* drops the
  half-covered edge column (blends toward white, reads desaturated — 37 where
  the true extent is 38); the *selected* picker entry carries a selection ring
  and measures 48×48 — not a case. Measure against the local background at zero
  tolerance and read the per-column profile before believing an extent.

**R6 per backend** (ADR-0002, screen captures via
`example/spike/spike_117_layer_scope.dart`, enclosing layer half a device pixel
off): Windows 1.5 — current byte-identical to reference, `0.3.1` 2921/4356
differ up to 196; macOS 2.0 — byte-identical, `0.3.1` 1289/7744 up to 136; web
CanvasKit 1.5 — neither exact, current width 66 (correct) vs `0.3.1` 67, a
non-regression; iOS/Android unmeasured. The spike's vector-disc control (1937
px, max 1) rules out the variant winning by landing on an integer by accident.

**Outside input:** the device pixel ratio and the ancestor transform — both
from the platform/layout, unbounded; non-finite values are handled (they pass
through the snap and fail the predicate).

## Code

- `lib/src/widget/boring_avatar.dart` — `snappedAvatarRect`,
  `avatarLandsOnePixelPerPixel`, `PixelSnappedImage`
  (`createRenderObject`, `updateRenderObject` — clone per rebuild),
  `RenderPixelSnappedImage` (`set image`, `set devicePixelRatio`,
  `_intrinsic`, `computeDryLayout`, `performLayout`, `hitTestSelf`,
  `debugPaintedDestination`, `paint`, `dispose`); the call site in
  `_BoringAvatarState::build` (`SizedBox` is layout, `PixelSnappedImage` is
  drawing — deliberately different rectangles).
- Tests, `test/widget_test.dart`: `_pixelSnap` (per-ancestor sweep "the buffer
  lands on the device pixel grid whole, …"; "the snap is taken against the
  screen, not the enclosing layer"; "the destination rectangle is on the grid
  by construction"; "a box the parent squeezed keeps squeezing the drawing";
  "the avatar answers a hit test"; "the reported case, on the picture that
  reported it" — `marble` 45 @1.25, 56 not 57), `_resampleFallback` ("the
  unfiltered hand-off is claimed only where it is true" — the predicate's
  enumeration; "and the predicate reaches the pixels" — 7 repeated columns
  without the fallback, 0 with it).
- `example/integration_test/pixel_snap_test.dart` — "the avatar occupies whole
  device pixels on this engine".
- `example/spike/spike_117_layer_scope.dart` — the R6 instrument, four columns;
  kept until iOS and Android are measured, then to be deleted (its own header).
- `tool/mutate/cases/110-pixel-snap.json` — groups A (roundings, coordinate
  space) and B (`RenderImage` checklist), see [mutation-harness](mutation-harness.md).

## Reference behaviour

- Flutter `rendering/editable.dart` — `RenderEditable._snapToPhysicalPixel`
  (prior art for the expression and the non-finite guard; present at 3.47.1).
- Flutter `rendering/image.dart` — `RenderImage` (clone ownership, `isCloneOf`,
  `hitTestSelf`, `paintImage`'s `isAntiAlias`).
- flutter/flutter#111302 (no repaint guarantee when a layer moves; "Flutter
  currently lacks a public API for pixel-perfect alignment") and #111145 (engine
  layer pixel-snapping removed) — R4 and the reason not to lean on the backend.
- Real-engine screen captures, 2026-08-18 (#117): Windows 1.5, macOS 2.0,
  Chrome CanvasKit 1.5 — tables in ADR-0002.

## Cross-cutting invariants

- [variant-design-size](../invariant/variant-design-size.md) — only at a
  physical side equal to the viewBox side is the device scale 1; placement's
  "one buffer pixel per device pixel" is a separate 1:1 and must not be
  conflated with it.
- [physical-pixel-rounding](../invariant/physical-pixel-rounding.md) — `snappedAvatarRect` and `avatarLandsOnePixelPerPixel` must round the same way as the buffer.

## Blast radius

- [widget-lifecycle](widget-lifecycle.md) — `pixels = (size × dpr).round()` is
  computed there and must equal the rounding here, or the predicate answers
  about a rectangle nothing draws; `_sync`'s keep-on-resize interval is a
  predicate-false case by design.
- [example-app](example-app.md) — the integration test and the spike live in
  the example; the web measurement is taken on its picker and gallery.
- [mutation-harness](mutation-harness.md) — case file 110's A3 meaning was
  inverted at #117; its notes still name `debugGlobalDestination`.
- [goldens](goldens.md) — placement must never alter buffer bytes; the
  `_bytesOnScreen` proof is upstream of placement and would not see a sampler
  change.

## Known holes / open

- **iOS and Android are unmeasured** for R6 ("the engine rounds the enclosing
  layer"); if false there, the `0.3.1` behaviour was right on those backends.
  Run the spike's four columns on each.
- **Web lands nothing whole** at fractional ratios; outside the package's reach.
- **Scroll staleness** (R4) — closes only if Flutter adds an API
  (flutter/flutter#111302) or restores layer snapping (#111145).
- **Clip at exactly the box** — 6 of 105 combinations; opt-in if a caller
  reports it (B and C were never rendered; re-run the 105-sweep first).
- **The integration test captures with `toImage`**, so it cannot see the
  compositing step R6 is about; only a screen capture can.
- **Stale surfaces left by #117's R6 reversal** (outside this note): the
  `widget_test.dart` group is still titled "the snap is taken against the
  screen, not the enclosing layer" and its comment names
  `debugGlobalDestination` — the body asserts the reversed rule and the field
  is now `debugPaintedDestination`; `tool/mutate/cases/110-pixel-snap.json`
  and `docs/agents/lessons.md` also name `debugGlobalDestination`.
