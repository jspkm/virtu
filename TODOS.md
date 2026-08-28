# TODOS

Deferred work with a named trigger. Items that expire on a future event live here
because the design doc that deferred them gets archived when its block ships.
Everything else deferred by a block lives in that block's "NOT in scope" table.

---

## Dead persisted state — decide, then migrate

**What:** A dead-code sweep on 2026-08-28 cleared everything unreferenced
except four things that are **persisted SwiftData schema**, where deleting is
a migration rather than housekeeping. All four are dead today:

| | State |
|---|---|
| `Part.furthestPageIndex` | **Write-only.** `AppState.recordProgress()` still updates it on every turn; nothing reads it. Its only reader was the work card's progress rule, removed 2026-08-28 at the user's request. |
| `AnnotationLayer` (whole `@Model`) | **Never written.** Ink lives in `StrokeJournal` as files (§8.1); this model's `drawingData`, `pageWidth`, `pageHeight`, `deviceID` are all inert. It survives only in the `Schema` and as `Part.annotationLayers`. |
| `AnnotationLayer.updatedAt` | Unreferenced even within the dead model. |
| `Work.year` | Never set, never shown. The import sheet does not ask for it. |

**Why it was left rather than removed:** dropping a stored property discards
whatever a musician's store already holds. `furthestPageIndex` in particular
holds real practice history, and if the progress rule ever comes back it
cannot be recomputed. That is the user's call, not a cleanup's.

**The cost of leaving it:** `recordProgress()` is a write path with no reader,
which the next person to touch page turns has to prove is safe to disturb, and
`AnnotationLayer` invites someone to assume ink is in SwiftData when the whole
integrity story is that it is not.

**Also removed in that sweep, and recoverable from git if wanted:**
`Virtu/Annotation/StampLibrary.swift` — 242 lines defining a `Stamp` glyph set
(articulations, fingerings) and a `GlyphPen`, referenced by nothing. Stamps are
not in the shipped tool rail, so this was speculative work that never landed.

**Trigger:** before the next SwiftData migration, or whenever the progress rule
is reconsidered.

**Depends on:** deciding whether practice progress returns to the shelf.

---

## The metronome refusal is reversed — amend the PRD

**What:** A metronome now ships, on the Tools screen (`Virtu/Tools/`). The PRD
refuses it: §6.0(3) marks it **REFUSED**, §5's surface table calls two of
Tools' three contents refused, and `docs/ROADMAP.md` and the performer vision
both file metronome/tuner under "commodity clutter." **Those lines are now
wrong and need amending.**

**Why it was reversed:** 2026-08-27 user feedback from a working musician —
"can't find metronome/tuner tool." The refusal was reasoned from the premise
that every pro already owns one; the first musician to actually use Virtu went
looking for it inside Virtu. The design handoff had never given it up either:
`Virtu.dc.html` carries a full Tools metronome, and `VFont.bpmPanel` /
`VFont.bpmTools` have been sitting in the type scale the whole time. What
shipped follows that handoff exactly, plus a meter picker it lacked.

**Why this is filed here rather than left implicit:** TODOS.md already records
what the unbuilt-and-unretired seam costs — every future design session
re-derives the same confusion. A built-but-still-refused metronome is the same
trap pointing the other way.

**Still open:**
- The **tuner** is not built. The handoff draws it beside the metronome
  (an A/442 reference with pitch buttons); the user's ask covered it. It needs
  a microphone permission string and pitch detection, and was deliberately
  split out so the metronome could land first.
- **No running indicator outside Tools.** The click keeps going when you leave
  the screen — PRD §5 requires exactly that — but nothing anywhere else says
  so, and there is no way to stop it without walking back to Tools.
- **No background audio mode.** PRD §10 says the metronome "must survive
  backgrounding"; `UIBackgroundModes: [audio]` was NOT added, because it is an
  App Store review surface nobody asked for. The screen is kept awake while it
  runs, which covers the practice-room case. Decide whether the PRD line meant
  more than that.

**Trigger:** amend the PRD before the next design session touches Tools.

**Depends on:** nothing.

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
