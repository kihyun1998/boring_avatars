# Aggregate — upstream divergences (the S-ledger)

**This note owns no detail.** It lists the maintainer's rulings on suspected
upstream defects. Each event (what was shown, what was chosen, the quote, the
cost, and that it is the maintainer's to reverse) lives in the territory note it
governs.

| Ref | Upstream `file:line` @ tag | What it does | Ruling | Decided | Event |
|---|---|---|---|---|---|
| **S-3** | `avatar-marble.js:56` @ v1.6.1; still `avatar-marble.tsx:59` @ v2.0.0–`master` | the first path takes its colour, translation and rotation from `properties[1]` and its **scale from `properties[2]`**. Fixing it would change 11 of 20 corpus names and 3 in 4 of all hashes | **reproduce it: the reference is the specification** | 2026-08-07 | [marble](../territory/marble.md#governing-decisions) |
| **S-1** | `avatar-sunset.js:20,36,41` @ v1.6.1; same construction at `avatar-sunset.tsx:21,39–40,44,55` @ v2.0.0–`master` | builds a gradient id from the caller's name and references it as `url(#…)`. A name with `'`, `"`, `(`, `)`, `\`, `%` or a control character makes the reference unreadable, so the browser paints nothing | **repair it: do not reproduce the blank** | 2026-07-29 | [sunset](../territory/sunset.md#governing-decisions) |
| **S-2** | `avatar-beam.js:9,17` + `utilities.js:42` @ v1.6.1; `avatar-beam.tsx:18` + `utilities.ts:42` @ v2.0.x | an empty palette makes `getContrast(undefined)` call `.slice`, giving a `TypeError` and no document. Only `beam` does this: 20 of 20 names, against 0 of 100 for the rest | **reproduce the failure, as a Dart-idiomatic exception** | 2026-08-06 | [beam](../territory/beam.md#governing-decisions) |
| **S-4** | `avatar.js:18` @ v1.6.1: `size = 40`, forwarded untyped to `width={props.size}` | a `size` that is neither a number nor a string is not validated. `true`/`false`/`null` drop `width`/`height`, `[80]` becomes `width="80"`, and `{}` becomes `width="[object Object]"` | **throw; do not reproduce the degradation** | 2026-08-08 | [public-svg-surface](../territory/public-svg-surface.md) |
| **S-5** | `index.tsx:29` @ v2.0.0–`master` (theflow.md said `:30`; re-read at every 2.0.x tag and `master`): `AVATAR_VARIANTS[variant] \|\| AvatarMarble` | an unknown variant string that is an `Object.prototype` key (`'constructor'`, `'toString'`, …) resolves to the inherited function, and React crashes. 1.10.1–1.11.2 degrade the same string to marble | **keep the degrade; do not reproduce the 2.0.x crash** | 2026-08-14 | [variant-dispatch](../territory/variant-dispatch.md) |

Five rulings. A row is appended only after the maintainer has seen the case and
ruled on it.

## Why they sit together

The five share a process, not a mechanism. Each is a place where upstream's
output looked like a defect, and each was settled by the maintainer as a product
judgement rather than by a derivation. No territory reads another's ruling. What
links them is the rule below, and the fact that two pairs went opposite ways for
reasons that have to be read side by side.

## How a divergence is decided, and why opposite rulings are consistent

**The process rule** (carried from theflow.md's reasoning bindings and ledger
preamble; it applies to every future candidate):

- **The reference is the specification.** A derivation that disagrees with
  upstream is wrong by definition, however elegant it is. The general
  default, "our own measurement outranks prior art", is inverted in this repo.
- **A suspected upstream bug is never adjudicated by the agent**, in either
  direction. That rules out both "replicate silently" and "fix silently". The
  case goes into the maintainer's approval batch with four things:
  - the `file:line` in the pinned reference tree;
  - the value upstream actually produces;
  - the value a "corrected" version would produce;
  - what the difference looks like on screen.
- **The maintainer rules per case, and the ruling is recorded as an *event*.**
  The record says what they were shown, what they chose (with their words),
  what it costs, and that it is theirs to reverse. A ruling is a product
  judgement, not a derivation, so a later adversarial pass with a stronger
  argument does **not** reopen it. Writing "the user decided X on <date>, shown
  Y" is what stops that re-litigation.
- **Never dismiss a divergence candidate on a feeling.** Cite the ground (the
  reference line, an existing ledger row, or the lens's own `INERT` /
  `DELIBERATE` grade), or carry the candidate to the batch.

**Why opposite rulings are not a contradiction.** Two pairs were ruled in
opposite directions. Each pair answered a different question.

- **S-1 (repair) vs S-3 (reproduce).** S-1 repaired `sunset` because upstream's
  own output was **a blank avatar**, a defect the user could see. In S-3 both
  outputs are perfectly good avatars, and the only argument available was about
  the author's *intent*. "Fix the bug" does not carry over from the first case
  to the second. A visible defect earns a repair, and a guessed intent does not.
- **S-2 (reproduce the throw) vs S-4 (throw where upstream degrades).** In S-2,
  upstream itself failed and emitted **no bytes**, so throwing was the only
  output that matched. "Byte-identical" was vacuous there. In S-4, upstream
  emits a perfectly good document and the port refuses it. S-2 asked "do we
  reproduce a crash" and S-4 asked "do we reproduce a coercion". Upstream's S-4
  behaviour is not a designed degrade: React prints `Received true for a
  non-boolean attribute` to tell the author they made a mistake. Reproducing it
  would mean reproducing a bug report.
- S-5 sits with S-2 and S-4 as a crash-vs-degrade judgement. The difference is
  that upstream disagrees *with itself* inside one selector's covered range, so
  the reference cannot arbitrate.

## What is not reproduced, and where each one lives

[`docs/fidelity.md`](../../fidelity.md) ("The three things that are not
reproduced") is the user-facing statement. Each item's home:

1. **A `sunset` name containing quotes or brackets**: ruling S-1, in
   [sunset](../territory/sunset.md). fidelity.md's character list omits `%`,
   which the repair also encodes (see that note's Known holes).
2. **A `size` that is not a size**: ruling S-4, in
   [public-svg-surface](../territory/public-svg-surface.md).
3. **The document's internal ids** (`useId()` from 1.8.0 for the mask, and from
   1.10.2 for `marble`'s filter). This is not a ruling: no fixed bytes exist to
   reproduce, because the id depends on the component's position in the React
   tree. The port emits the literals 1.7.0 writes. It lives in
   [svg-emission](../territory/svg-emission.md) and
   [version-grouping](../territory/version-grouping.md).

Separately, upstream's own bugs *are* reproduced. The one that changes what a
reader sees is S-3 (fidelity.md, "Upstream's own bugs are reproduced, not
corrected").
