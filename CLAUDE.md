# CLAUDE.md

## Working discipline — theflow

Substantive changes (a ported upstream state, a bug fix, a behavior change)
follow the **`theflow`** skill — run `/theflow` at the start. This repo's
bindings (module map, the upstream version ladder, reference routing, boundary
rule, proof methods, surfaces, gate matrix) live in
**`docs/agents/theflow.md`**; per-incident evidence in
**`docs/agents/lessons.md`**. Read both before starting; add new war-stories to
lessons.

## Package philosophy

`boring_avatars` is a **bit-exact Dart port of
[`boring-avatars`](https://github.com/boringdesigners/boring-avatars)**. Given
the same name, palette and variant, it produces the same avatar the npm package
produces — the same numbers, the same SVG, the same pixels.

1. **The reference is the specification.** Not a cross-check, not an
   inspiration. A derivation that disagrees with upstream is wrong by
   definition.
2. **Every supported upstream version is selectable at runtime.** Scope is
   `1.6.1` onward — where upstream replaced `getNumber` with `hashCode` — which
   is 99.6% of what npm actually installs. npm needs a downgrade to render a
   1.7.0 avatar; this package needs a parameter.
3. **Additive forever, one release per *output state*.** Upstream versions
   share a selector — and a release — when **a caller gets the same thing out
   of them**, not when their source happens to match. Measured, not read: the
   nine in-scope releases from `1.6.1` to `2.0.4` produce **three** distinct
   results, so there are three releases and not nine. `1.11.0` is excluded
   outright; it writes its own props onto the `<svg>` element and no other
   version does. A new state is a new selector value, never an edit to a
   shipped one — and every release re-proves that the already-supported states
   still render byte-identically.

   **This table is the single source for the mapping.** Release, selector and
   covered versions are one fact in three vocabularies; `docs/agents/theflow.md`
   points here rather than restating it, so there is one place to edit when a
   new upstream release lands.

   | Release | Selector | Covers | The one thing that changes |
   |---|---|---|---|
   | `0.1.0` | `v1_6_1` | 1.6.1, 1.6.2, 1.6.3 | — (everything is built here) |
   | `0.2.0` | `v1_7_0` | 1.7.0, 1.8.0, 1.9.0, 1.10.0 | `<title>` becomes optional |
   | `0.3.0` | `v1_10_1` | 1.10.1, 1.10.2, 1.11.1, 1.11.2, 2.0.0 – 2.0.4 | `pixel`'s colour index |

   **Collapsing the releases does not collapse the evidence** — every covered
   version is *measured*, by rendering it and comparing the result. What is one
   per release is the committed **fixture**, because a second copy of identical
   bytes is not a second measurement. The measurements behind the grouping, the
   reason `1.11.0` is excluded, the work each release earns, and the two
   superseded plans are in `docs/agents/theflow.md` ("The states in scope",
   "Release plan").
4. **Deterministic everywhere.** The same input yields the same bytes on every
   platform, GPU, Flutter version and rendering backend.

## Identity & invariants (the boundary)

- **Three layers, declared seams, all owned here.** `data` (name → numbers and
  colors, pure, no Flutter import) → `scene` (backend-neutral drawing
  description) → `raster` (deterministic software rasterization). The `scene`
  seam exists so the SVG emitter and the rasterizer share **one** copy of the
  geometry; two emitters deriving it independently is a divergence seed.
- **The rasterizer is ours on purpose.** Delegating to `Canvas` would make the
  output depend on Skia-vs-Impeller, GPU, platform and Flutter version — and the
  package could then make no claim about its own output at all. Software
  rasterization on a `Uint8List` is what makes point 4 above true.
- **Layer 1 is frozen on publish.** A shipped selector's values are a contract:
  changing them silently rewrites the profile picture of every user of every app
  that depends on this package. That irreversibility — not difficulty — is what
  makes `lib/src/js/` and `lib/src/variants/` the **sacred surface** where the
  completeness pass is unconditional.
- **The palette is the caller's.** `colors`, the `version` selector, `square`,
  size, layout and caching are injected policy. The package never assumes a
  palette.
- **A suspected upstream bug is never adjudicated by the agent.** Neither
  "replicate silently" nor "fix silently". It goes to the user with the
  reference `file:line`, both values, and the visual difference; their ruling is
  recorded as an *event* in the divergence ledger in `docs/agents/theflow.md`.

## Environment

Claude Code and the user share the same Windows machine. On `PATH`: Flutter
3.41.9, Node v26.4.0, npm 11.17.0 — run `flutter test` / `analyze` /
`dart format` and the Node parity harness directly. Ask the user only for
anything that opens a window (`flutter run`). **There are no CI gates** — the
gates in `docs/agents/theflow.md` (Step 7) are the only gates and run here. The
single GitHub Actions workflow is an upstream *watcher*, not a gate.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`kihyun1998/boring_avatars`), managed
via the `gh` CLI; external PRs are not a triage surface. See
`docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage` / `needs-info` / `ready-for-agent` /
`ready-for-human` / `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root (created lazily).
See `docs/agents/domain.md`.
