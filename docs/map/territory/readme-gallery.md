# readme-gallery

## What it is
`tool/readme/generate.dart` draws the six PNGs under `docs/images/` that the
README's gallery shows — one per resolved variant, `Clara Barton` with
upstream's default palette, at 256 px — through **this package's own
rasterizer**, not a browser. Added in `0.3.3` (commit `5544c2b`).

## Governing decisions
**None.** Adjacent: the `0.3.3` CHANGELOG entry states the intent (the images
are evidence for the sentence beside them: what `BoringAvatar` puts on screen,
not what upstream draws).

## Design model
- **Drawn by our rasterizer on purpose**: a Chrome screenshot would show what
  upstream draws; these show the widget's output. The two agree — that is what
  [calibration](calibration.md) / [crosscheck](crosscheck.md) measure — but
  only one is evidence for the README's claim.
- **Generated, never hand-edited.** Deterministic: re-running with no source
  change rewrites the same bytes, `git status` stays clean. Run deliberately
  when the rasterizer or the roster changes; review the diff.
- **Roster**: `BoringAvatarsVariant.values` filtered to `resolved == self` — the
  two deprecated aliases are skipped (they would write a second `beam`).
  `version: BoringAvatarsVersion.latest` (`v1_10_1` at HEAD), `square: false`,
  `title: null`.
- **256 px**, not 80: displayed at ~120 CSS px, a 2× screen asks for 240;
  rendering at display size would show the browser's upscaler, not this
  rasterizer's edges.
- **Own PNG encoder** (`_encodePng`) — no dependency.
- **Served from GitHub `main`**: the README references
  `https://raw.githubusercontent.com/kihyun1998/boring_avatars/main/docs/images/variant-<name>.png`;
  `docs/` is excluded from the archive by `.pubignore`.
- **Input bounds:** fixed in code.

## Code
- `tool/readme/generate.dart` — `_palette`, `_name`, `_size`, `main`,
  `_encodePng`
- `docs/images/variant-{marble,beam,pixel,sunset,ring,bauhaus}.png`
- `README.md` — the gallery table

## Reference behaviour
**None** — by design it is not compared to upstream; parity is measured
elsewhere.

## Cross-cutting invariants
- [frozen-selector-output](../invariant/frozen-selector-output.md) — the gallery
  draws `latest`, which moves when a new selector ships; the images then change
  although no shipped selector did.

## Blast radius
- [goldens](goldens.md) — a rasterizer change that moves a visible pixel moves
  goldens *and* makes these images a picture of the old code; nothing but a
  deliberate re-run updates them.
- [version-selectors](version-selectors.md) — a new `latest` means the gallery
  is stale until regenerated.
- [variant-dispatch](variant-dispatch.md) — the roster is the enum filtered by
  `resolved`; a new alias or variant changes the file set.
- [release-and-publishing](release-and-publishing.md) — `docs/images/` is on the
  Step 6 sweep list.

## Known holes / open
- **No check that the images match the code.** Nothing regenerates or compares
  them; a stale gallery is silent.
- **Every published version's pub.dev README shows `main`'s images**, not the
  images of the version it describes.
