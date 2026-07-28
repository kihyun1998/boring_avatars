# lessons — war stories, indexed by theflow step

Per-incident evidence for the rules in [`theflow.md`](theflow.md). Each entry is
a *precedent*: a rule that caught (or failed to catch) a real defect, with the
issue number that proves it happened.

**Empty so far — this repo has no incidents.** That is the honest state, not an
oversight.

Do not seed this file with anticipated problems. The enumerated JS/SVG semantics
traps live in `theflow.md`'s **hidden-state list**, which is *pre-incident*
enumeration. A row moves here — with its issue number — the first time it
actually catches something in this codebase.

## Step 1 — verify references against real source

### A file existing is not the feature existing (#1 → closed #8)

Working #1, the variant roster was drafted from the **git tree file listing** —
`avatar-turbulence.js` is there from v1.2.0 to v1.5.2, so `turbulence` went into
the plan and got its own ticket (#8), sized as the project's heaviest item
(`feTurbulence`'s spec PRNG plus `feDisplacementMap`).

Reading `avatar.js` — the **dispatch** — killed it. `turbulence` appears **zero
times across all 28 tags**. Its blob SHA never changed (`4055bd`) for the same
reason: nothing referenced it. No caller could render it, so there is no upstream
output to reproduce and not even a layer-1 fixture can be generated. #8 closed as
not planned.

The same read produced three more corrections the file listing could not have
shown: `eye` is dispatched **only** at v1.2.0 though its file survives to v1.5.2;
`geometric`/`abstract` mean three different things by era (real variants → 
unreachable → deprecated aliases); and an unknown variant **degrades to the era
default rather than throwing**.

**The rule this earns:** for a port, the reference's *entry point* is the
authority on what exists. A component file tells you how something is
implemented, never whether it is reachable. Read the dispatch before the
components.

**And on sampling:** the first sweep read 14 of 28 tags and was about to be
called done. The exhaustive sweep is what makes "zero in every version" a fact
instead of a strong guess — for an enumeration that *is* the deliverable, sample
size is not a detail.

## Step 2 — mechanism / policy boundary

_(none yet)_

## Step 3 — TDD and the test-trust gate

_(none yet)_

## Step 4 — real round-trip proof

_(none yet)_

## Step 5 — adversarial completeness pass

_(none yet)_

## Step 6 — surface sweep

_(none yet)_

## Step 7 — gates, release, downstream

_(none yet)_
