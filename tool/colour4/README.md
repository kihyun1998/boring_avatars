# tool/colour4 — the #95 measurement, re-runnable

The Chrome ground truth behind `raster_colour4_test.dart` and
`system_colours.dart`. Two probes, two independent sources — the same
two-source rule `named_colours.dart` follows:

- **`gen.mjs` + `read.mjs`** — an 86-swatch strip rendered through the
  calibrate harness's own headless Chrome and read back pixel by pixel. Every
  notation family, the out-of-gamut discriminators that fixed the clip model,
  the refusal cases (the probe SVG has no root `fill="none"`, so a refusal
  shows as inherited black — the `zzz` control is the baseline), and the #95
  completeness pass's five behavioural discriminators.
- **`sys.mjs`** — the 42 system colours (19 current + 23 deprecated) resolved
  through `getComputedStyle` via playwright-core (run it from `tool/crosscheck`,
  which owns the dependency), plus the none-component and comma-form
  discriminators. Exact channel values, no PNG rounding; this is the source
  `system_colours.dart` is generated from, with the strip as the cross-check.

```bash
node tool/colour4/gen.mjs /tmp/c4
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  node tool/calibrate/render.mjs /tmp/c4
node tool/colour4/read.mjs /tmp/c4
cd tool/crosscheck && node ../colour4/sys.mjs
```

A TOOL, not a gate — the same rule as `tool/calibrate`. `flutter test` reads
the committed tables and never runs Node. Reference run: Chrome
**151.0.7922.108**, macOS, light mode, 2026-08-11. System-colour values are UA
discretion, so on another OS, theme or Chrome the `sys.mjs` output may
legitimately differ from the frozen table — that is the validity condition in
`system_colours.dart`'s header, not a failure of this tool.
