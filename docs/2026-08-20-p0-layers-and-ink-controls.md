# P0 — Layers, mode/library icons, and the ink controls

Founder decision, 2026-08-20. These six sit **above** the previously-listed P0
work (delete/edit a work, `pageSize` persistence, `.anyInput` fallback, tool
persistence, crash-durability tests) and above all of M4.

---

## 1. Layers

Marking the score always lands on a layer. Layer 1 exists from the start and is
the default — a user who never opens the layer control never learns the concept.

- Up to **10** layers per part (tentative cap).
- Each layer has an independent **visibility** toggle. Hiding all of them shows
  the clean engraving — that is the feature's whole point.
- The **active** layer receives new ink. Exactly one is active at a time.
- Erase, lasso, and undo/redo act on the **active layer only** (decided). A
  hidden layer can never be damaged by a stroke you can't see. This falls out
  of the architecture rather than being policed: the canvas is handed *only*
  the active layer's drawing, so PencilKit cannot reach the others.
- Within a layer, highlighter composites under ink (today's rule). Across
  layers, composite in index order, 1 at the bottom.
- Export flattens **visible layers only**, in the same order.

### Decided
- Control lives **in the writing toolbar** — a layer stack at the bottom of the
  right-edge rail. Tap a number to make it active, tap its eye to hide it.
- Layers belong to the **part**, and their visibility and active index persist
  on `Part` (SwiftData) so a score reopens exactly as it was left.

### Storage impact
`StrokeJournal` keys on `partID-pageIndex` today. It gains the layer index.

## 2. Mode icon (top-right)

One persistent icon, top-right, that toggles the reading mode both ways:

- In **Perform** it shows the pencil — tap enters Study.
- In **Study** it shows the Perform glyph — tap returns to Perform.

Replaces the current hold-half-a-second gesture on the Perform-mode chip and
the `Perform | Study` capsule in the top chrome. The two-finger double-tap
stays as the eyes-free path.

## 3. Library icon (top-right, beside the mode icon)

To the **right** of the mode icon, separated by deliberate space so a hurried
hand cannot hit the wrong one. Tap goes to the Library. Replaces the
`← Library` text button at top-left.

Spacing floor: 44pt hit targets with **≥28pt of clear space between them**.

Decided: both icons are **always present at whisper weight** — the mode chip's
current resting opacity (0.28 light / 0.35 Stage), brightening on touch.

> Tension accepted knowingly: this puts two always-visible controls on the
> Perform screen, which the M2 design doc defined as "the page and nothing
> else." Mitigation is weight, not absence — hold both at the mode chip's
> current resting opacity (0.28 light / 0.35 Stage) so they read as a whisper.

## 4. The writing toolbar never fades

Remove the 3-second idle dim from `ToolRailView` (the `dimmed` state, the
`wakeToken`, and the `.task` that drives them). The rail is always at full
strength while Study is open.

## 5. Pencil thickness flyout

**Long-press the pencil** in the writing toolbar and a secondary panel slides
out. Four thicknesses, each drawn as a **dot at its true relative size**:

| | width | note |
|---|---|---|
| 1 | 1.5pt | thinner |
| 2 | **3.0pt** | **current — the default** |
| 3 | 5.0pt | thicker |
| 4 | 8.0pt | thickest |

Selection persists across launches. The ladder is **fixed, not per-style**: a
line style does not get to resize your nib. Where an ink type cannot reach a
width PencilKit clamps it, but the selection stays put and returns intact.
3pt is honoured exactly by all four styles.

## 6. Line style and colour

Same flyout. Four styles:

| | style | |
|---|---|---|
| 1 | **solid** | **current — the default** |
| 2 | calligraphic | width responds to direction/pressure |
| 3 | dotted | |
| 4 | fine dotted | tighter, smaller dots |

Colour is **not** in this panel: free colour choice is the fifth swatch on the
main toolbar, beside graphite/red/blue/green. A colour is a colour; there is no
reason four of them live in one place and the rest somewhere else.

The panel itself is a bare vertical strip to the left of the toolbar — nibs
above, styles below, no headings. Each control is a picture of the mark it
makes, and a word on top of that only costs room the rail has not got.

---

## The storage change

Only **layers** change the journal. Everything in items 5 and 6 rides inside
`PKStroke` natively, so there is no parallel stroke store and no index-aligned
sidecar to keep in sync through lasso and erase:

| attribute | carried by |
|---|---|
| thickness | the stroke's own point sizes — `InkRenderer` already renders per-point width |
| colour | `stroke.ink.color` |
| line style | `stroke.ink.inkType` — four types used as carriers (below) |

### Line style carriers
`PKInkType` gained `.monoline`, `.fountainPen`, `.watercolor` and `.crayon` in
iOS 17; the deployment target is 17.0, so all are available unconditionally.

Carriers are chosen for the width range they allow, **measured rather than
assumed**:

| ink type | valid width range |
|---|---|
| `.pen` | 0.88 – 25.66 |
| `.pencil` | 2.4 – 16.0 |
| `.marker` | 7.5 – 60.0 |
| `.monoline` | 0.5 – 4.0 |
| `.fountainPen` | 1.5 – 14.0 |
| `.watercolor` | 10.0 – 80.0 |
| `.crayon` | 10.0 – 50.0 |

| style | ink type | rendering |
|---|---|---|
| solid (default) | `.pencil` | unchanged — today's behaviour |
| calligraphic | `.fountainPen` | width responds to direction; native input feel |
| dotted | `.pen` | `InkRenderer` applies a dash pattern |
| fine dotted | `.monoline` | smaller dots, wider gaps |

The first pass used `.monoline` for dotted and `.crayon` for fine dotted, which
capped dotted at 4pt and gave "fine" a 10pt *minimum* — the fattest of the
four. `.pen` is wide and otherwise unused; `.monoline`'s low ceiling is exactly
right for the finest style.

The last two are *carriers*, not descriptions: `InkRenderer` is the sole
rasterizer for display and export, so what those strokes actually look like is
entirely ours (`setLineDash` on a path we already control). Documented here
because the choice is otherwise inscrutable in the source.

> **Verify on hardware.** PencilKit renders live strokes itself on device, so a
> dotted stroke may draw solid under the tip and snap to dotted on lift. Added
> to the hand protocol in `TESTPLAN.md`.

### The journal format
Per page, per layer, the record becomes:

```
PageInkRecord { schemaVersion, pageWidth, pageHeight, drawingData }
```

keyed `{partID}-L{layer}-page{N}`. This is also where the authored `pageSize`
finally lands (PRD 7.3) — the v2 cross-edition thesis depends on it and no
format has carried it yet. Legacy `{partID}-page{N}.pkdrawing` files are read
forward into layer 1 on first load, so existing ink survives untouched.

## Relationship to M6

M6 listed "Layers — mine / section / this-program, per-layer visibility and
export." Item 1 is that feature pulled to P0 with **numbered** layers instead
of named roles. Named/role-based layers remain an M6 refinement on top.

---

## 7. Shared margins  *(added 2026-08-20)*

A **full page** of blank paper to the **right** of the score and another
**below** it — right from the reader's point of view, under the writing hand.

- The margin belongs to the **part, not the page**: what is written beside
  page 1 is still there beside page 5. Fingering charts, a conductor's note
  from Tuesday, a worked-out bowing — none of which want rewriting per page.
- It **costs the score no size**. Fit is measured against the page; the margins
  hang off the container outside the viewport, so they appear only when the
  paper is moved. Panning is Study-only.
- Same white as the page. A margin shaded like a desk reads as scenery; blank
  paper reads as somewhere to write.
- Journal slots -1 (side) and -2 (bottom), per layer, so margins honour layer
  visibility like everything else.
- The bottom margin's coordinate space is fixed at two pages wide, so rotating
  the iPad rescales what is written rather than reflowing it onto other notes.

**Consequence:** swipe-to-turn becomes Perform-only. In Study a horizontal drag
moves the paper to reach the margin and cannot also turn the page. Edge taps,
the pedal and the scrubber still turn in both modes.

**Export** asks: the part alone (default), or with margin notes as one extra
page at the end. Working notes are not music, and a stand partner expects a
clean part at the original page size.
