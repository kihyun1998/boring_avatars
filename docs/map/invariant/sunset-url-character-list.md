# Sunset url character list

## The fact
The characters for which `sunset`'s gradient reference is repaired (ruling S-1)
are those `_breaksUrlToken` in `lib/src/variants/sunset.dart` encodes:
**`'`, `"`, `(`, `)`, `\`, `%`, DEL, and every code point at or below `0x20`**
(controls and space). Every surface that tells a reader which names diverge
from upstream must name that same list.

## Why it is cross-cutting
The list is code in one place and prose in four, and no test reads the prose:

| Copy | List at 0593e28 |
|---|---|
| `_breaksUrlToken` (`sunset.dart`) | `'` `"` `(` `)` `\` `%`, controls, space, DEL. **The source** |
| `boringAvatarSvg` doc-comment (`avatar.dart`) | `'` `"` `(` `)` `\`, control characters. **No `%`** |
| `docs/fidelity.md` §1 | `'` `"` `(` `)` `\`, control characters. **No `%`** |
| README "Where it differs on purpose" | `'` `"` `(` `)` `\`. **No `%`, no controls** |
| [aggregate/upstream-divergences](../aggregate/upstream-divergences.md) S-1 row | includes `%` (corrected at map init) |

The divergence is the user's ruling. A reader deciding whether their users'
names are affected reads the prose, not `_breaksUrlToken`. `sunset_parity_test.dart`
pins the corpus names that are repaired, but only names in the corpus, and the
corpus has no `%`.

## Territories it holds in
- [sunset](../territory/sunset.md) — `_breaksUrlToken`, `sunsetUrlReference`
- [public-svg-surface](../territory/public-svg-surface.md) — `boringAvatarSvg`'s doc-comment, which ships as the pub.dev API reference
- [release-and-publishing](../territory/release-and-publishing.md) — README and `docs/fidelity.md`

## What a violation looks like
A user whose name contains `%` reads the README and concludes that their
`sunset` avatar is byte-identical to upstream. It is not, because the reference
is percent-encoded.

## Discovery history
- S-1 was ruled on 2026-07-29 (maintainer). The ruling's own "what it costs"
  paragraph lists `%`. The ledger row and the three reader-facing prose copies
  never did.
- Found at map init (2026-10-22) by comparing the ledger row with the code.
- Promoted to an invariant at map init (maintainer, 2026-10-22).

## Where it will recur
Whenever `_breaksUrlToken` changes, or a new upstream state puts a caller's
string into another id, a list of affected characters gets written. Write it
once in code and have prose either quote all of it or link to it.
