# example-app

## What it is
`example/` is a separate Flutter package (`boring_avatars_example`,
`publish_to: 'none'`, path dependency on `../`) that recreates the controls
from boringavatars.com — variant picker, palette cycle, round/square — with
every avatar drawn through `BoringAvatar`, plus two panels showing the widget
call and `boringAvatarSvg`'s document for the same avatar. It is published
inside the package archive (pana scores it; it is the answer to "show me this
in an app"). It also holds #110's real-engine placement test and #117's spike.
Platforms checked in: `macos/`, `windows/`, `web/` (no Android, iOS or Linux).

## Governing decisions
[ADR-0002](../../adr/0002-when-the-box-and-the-pixel-grid-disagree.md) governs
what `integration_test/pixel_snap_test.dart` and `spike/spike_117_layer_scope.dart`
measure (where the widget's buffer lands); it does not govern the demo app.
The demo itself has **no** governing record. Its inclusion in `0.1.0` (#78) is
in [release-and-publishing](release-and-publishing.md)'s release table.

## Design model
- **Why not `flutter_svg`** (measured #78, `example/README.md`): it does not
  clamp `rx` as SVG 1.1 §9.4 requires, so every variant's circular mask comes
  out square, and it has no `<filter>`, so `marble` loses its blur — all six
  variants draw wrongly. Not `Canvas` either (GPU- and Flutter-dependent). This
  is the demo-side statement of why the package rasterises itself.
- **The demo pins `BoringAvatarsVersion.v1_6_1`** in every `BoringAvatar`, in the
  code strip and in the SVG strip (read from `main.dart`); it does not track
  `latest`. `version` has no default in the API.
- **`integration_test/pixel_snap_test.dart`** runs #110's placement assertion on
  a **real engine** (Impeller/Angle on Windows, CanvasKit in a browser) rather
  than the test binding, because a backend-independence claim checked on one
  backend is an argument. The size is derived from the device ratio so that
  `size × dpr` is exactly half a pixel past an integer — a machine at 100%
  would otherwise pass without entering the condition. The capture boundary
  sits outside the padding (a tight boundary is itself a clip — it reported
  61×60 and the harness, not the engine, had eaten the row), and the avatar is
  `square` because a disc's topmost row can round to zero coverage and read as
  a lost row (disc 61×60 vs square 61×61, same engine, same buffer). Owned by
  [pixel-placement](pixel-placement.md).
- **`spike/spike_117_layer_scope.dart`** is an instrument kept by ADR-0002's
  validity condition for R6 ("the engine rounds the enclosing layer"):
  measured Windows 150% and macOS 200% byte-identical, web 150% not; **iOS and
  Android unmeasured**; delete the file once those two are measured (its own
  header). Owned by [pixel-placement](pixel-placement.md).
- **Not shipped**: `.pubignore` excludes `example/integration_test/` and
  `example/spike/`; the rest of `example/` ships.
- **No unit/widget suite.** `example/test/` does not exist at HEAD: the
  `flutter create` `widget_test.dart` arrived with macOS support (`07afe0c`) and
  was deleted in `d77c817` (both 2026-08-19). The gate for this package is
  `cd example && flutter analyze` only ([gates](gates.md)).
- **Generated registrants are tracked** (`example/windows/flutter/*`,
  `example/macos/Flutter/*`); analysing on Windows rewrites their line endings
  — the CRLF restore in [gates](gates.md).
- **Input bounds:** fixed in-code lists (`_palettes` 4, `_names` 8); no
  external input.

## Code
- `example/lib/main.dart` — `BoringAvatarsDemo`, `_HomeState`,
  `_VariantPicker`, `_PalettePicker`, `_ShapePicker`, `_Gallery`, `_CodeStrip`,
  `_SvgStrip`, `_CopyButton`, `_palettes`, `_names`
- `example/integration_test/pixel_snap_test.dart` — `'the avatar occupies whole
  device pixels on this engine'`
- `example/spike/spike_117_layer_scope.dart`
- `example/pubspec.yaml` — `integration_test` dev dependency
- `example/analysis_options.yaml`
- `example/{macos,windows,web}/`

## Reference behaviour
- boringavatars.com — the controls the demo recreates (visual reference only;
  never compared by any harness).

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the demo
  pins `v1_6_1`, so what it shows must never move.

## Blast radius
- [gates](gates.md) — a new platform directory adds a path to the CRLF restore;
  a new `test/` directory owes a gate line.
- [release-and-publishing](release-and-publishing.md) — anything new under
  `example/` ships unless `.pubignore` names it.
- [public-svg-surface](public-svg-surface.md),
  [widget-lifecycle](widget-lifecycle.md) — the demo is written against the
  public API; a signature change breaks `cd example && flutter analyze`.

## Known holes / open
- **No automated check of the demo's behaviour**; "observed at the screen"
  needs a person driving `flutter run`.
- The integration test runs only on demand on a real device; nothing records
  when it last ran per backend.
- The spike's iOS/Android measurement is owed by ADR-0002's validity condition.
