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

Selection persists across launches.

## 6. Line style and colour

Same flyout. Four styles:

| | style | |
|---|---|---|
| 1 | **solid** | **current — the default** |
| 2 | calligraphic | width responds to direction/pressure |
| 3 | dotted | |
| 4 | fine dotted | tighter, smaller dots |

Plus a free **colour choice** alongside the four preset swatches, so the user
is not confined to graphite/red/blue/green.

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

| style | ink type | rendering |
|---|---|---|
| solid (default) | `.pencil` | unchanged — today's behaviour |
| calligraphic | `.fountainPen` | width responds to direction; native input feel |
| dotted | `.monoline` | `InkRenderer` applies a dash pattern |
| fine dotted | `.crayon` | tighter, smaller dash pattern |

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
