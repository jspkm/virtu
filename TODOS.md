# TODOS

Deferred work with a named trigger. Items that expire on a future event live here
because the design doc that deferred them gets archived when its block ships.
Everything else deferred by a block lives in that block's "NOT in scope" table.

---

## macOS as the second platform (iPad first, then macOS)

**What:** Ship Virtu on macOS after iPad. **iPhone is cut, not deferred** — it is not a
target.

**Why:** Decided 2026-08-21. Musicians prepare and organise repertoire at a desk and read
it at a stand. The Mac is the preparation surface; the iPad is the stand.

**Current state:** `project.yml:50` is being set to iPad-only (eng review Issue 12), and
`:53` has `SUPPORTS_MAC_DESIGNED_FOR_IPAD: false`. **PRD §0.9 still says "Universal app,
iPad-first" meaning iPad plus iPhone, and PRD §6 M4 still lists "iPhone layout." Both are
now wrong and need amending** to iPad-first, macOS later, no iPhone.

**The question that has to be answered first, and it is not a layout question:**
a Mac has no Apple Pencil. §0.2 hardcodes `.pencilOnly` and says fingers never draw. So
either

- macOS is a **reading, library and programme surface** and annotation stays on the iPad,
  which is coherent and cheap and probably right; or
- macOS is a **writing surface**, which needs an input story that does not exist anywhere
  in the product today: trackpad, mouse, a Wacom tablet, or Sidecar with the iPad as the
  input device.

Decide that before any Mac layout work, because it decides whether this is a port or a
second product.

**Approach options, in rough order of cost:** "Designed for iPad" (flip `:53`, near-free,
poor Mac feel) → Mac Catalyst (moderate, shares the UIKit code) → native macOS target
sharing a `VirtuKit` framework (PRD §10 already mandates `VirtuKit`; `VirtuKit/Sources` is
currently empty).

**Trigger:** after the iPad build has real users. Do not start before M1's gate is answered.

**Depends on:** the annotation-input decision above; PRD §0.9 and §6 M4 amendments.

---

## `pencilEverPaired` escape hatch (PRD §7.2, open P0)

**What:** `PKCanvasView.drawingPolicy` is hardcoded to `.pencilOnly` rather than being
conditional on whether a Pencil has ever been paired. A device with no Pencil cannot draw
at all and is given no reason why.

**Why it matters more now:** PRD §7.2 calls this "reads as broken." Two triggers make it
live rather than theoretical:

1. **A colleague cohort.** The moment a TestFlight link goes to musicians beyond Hannah,
   anyone on a Pencil-less iPad gets an app whose Study mode is silently inert.
2. **macOS.** There is no Pencil on a Mac at all, so this hatch is a prerequisite for the
   Mac build under either option above.

**Current state:** the policy is a hardcoded default, not a preference. §0.2's rule is
intact and should stay intact — the hatch is the missing piece, not a relaxation of the
rule. It is roughly a 20-line conditional beside the hardcoded policy.

**Deferred because:** Hannah owns a Pencil, so it does not block the day-14 test.

**Trigger:** whichever comes first — a colleague cohort, or macOS work starting.

**Depends on:** nothing.

---

## The seam: decide or retire (PRD §9)

**What:** The carried-over system strip. On a forward turn, the last system of the page
you just left is pinned to the top of the new spread for about four seconds, then fades.
It is neither built nor retired. **Decide which.**

**Why it matters:** `design_handoff_virtu/README.md` lists it as design argument #2 and
calls it, in its own words, "the single most important novel behaviour in the product." It
solves a real problem: a page turn eats a phrase. M2 shipped **Corner Peek** instead, which
solves a different problem, previewing what is *ahead* rather than retaining what is
*behind*. PRD §6.0(4) records the substitution and states the seam "remains unbuilt and
unretired."

**Why the current state is the worst one:** it is not shipped, so no musician benefits, and
it is not retired, so the authoritative design document keeps promising it and every future
design session re-derives the same confusion. Two milestones have passed in this state.

**Cost if built:** it needs staff-line and system geometry detection. PRD §0.7 permits this
as the *single* exception to "no recognition engine in v1", precisely because the seam needs
it. It must degrade silently to no-seam when detection fails.

**Trigger:** decide after the day-14 test. That test is the first time a working musician
turns pages in Virtu under real practice conditions, so it is the first evidence about
whether turns actually eat phrases for her. If she never mentions it, retire the seam in
the PRD and strike the claim from the handoff. If she does, it has earned its recognition
exception.

**Depends on:** nothing technical. It is blocked on a decision nobody has made.
