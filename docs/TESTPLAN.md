# Virtu Test Plan

"Done" = **both** halves pass. Neither substitutes for the other.

## Half 1 — Automated (every build, before any install)

```bash
xcodebuild test -project Virtu.xcodeproj -scheme Virtu \
  -destination 'platform=iOS Simulator,id=<booted-ipad>'
```

27 tests in `Tests/VirtuInkTests.swift`: data integrity, geometry round-trips,
ink-layer rendering and position, canvas input space (inset/offset), display-
ownership state machine (normalization timing, lasso handoff, tool idempotence),
layer isolation and persistence, journal v2 (authored page size, pre-layer ink
read forward), line-style carriers, the nib ladder, and tool persistence.

## Half 2 — Hand protocol on hardware (every ink-touching build)

PencilKit's internal render layer is not inspectable, pencil input cannot be
synthesized, and the simulator does not render interactive PencilKit content.
These checks exist ONLY here. Run on the physical iPad with a real Pencil,
in Study mode, ~1 minute:

1. **Write** a word with the pencil.
   - Ink appears live under the tip while writing.
   - On lift: exactly ONE copy, exactly where written, dark and legible.
   - Wait 2s: still one copy (no late double-render after normalization).
2. **Highlight** a phrase.
   - One translucent band, correct position, ink stays readable through it.
3. **Erase** one stroke with one swipe — whole stroke gone, neighbors intact.
4. **Lasso** a marking, drag it elsewhere.
   - Selection visible while dragging; lands once at the new spot;
   - NOTHING remains at the old spot; wait 2s — still true.
5. **Turn the page away and back** — all marks exactly as left, single copies.
6. **Two-finger tap** — last stroke undone. Three-finger tap — restored.
7. **Perform mode** — pencil contact leaves no mark; marks remain visible.
8. **Layers** — mark on layer 1, add layer 2, mark again.
   - Hide layer 1: only the layer-2 marks remain. Hide both: clean engraving.
   - Show both: everything returns, single copies, original positions.
   - With layer 2 active, erase across a layer-1 mark — layer 1 is untouched.
   - Export with layer 1 hidden: the PDF carries only what was on screen.
9. **Line styles** — draw with each of the four.
   - **The paper rule**: the stroke under the tip IS the chosen style, and
     pen-up changes NOTHING — no snap, no restyle, no shift, no blink. The
     pencil pipeline is ours end to end (PencilKit no longer records inking
     strokes), so any pen-up change at all is a bug, not a refinement.
   - Ink stays under the tip at speed — predicted touches cover the gap. Any
     visible lag between tip and ink is a failure.
   - Each of the four nibs draws a visibly different thickness, in every style.
10. **Zoom and write in a corner** — pinch in, pan to the bottom-right of the
    page, write there. The corner must be reachable and the ink must land under
    the tip at that zoom.
11. **No edit menu** — long-press the page in *both* modes. "Select All /
    Insert Space" must never appear.

Any surprise at any step = not done, regardless of the green suite.

## Known OS constraints (iPadOS 26.x — do not re-litigate)

- PencilKit renders programmatically-set drawings as BLANK (device + sim);
  committed ink displays via `InkRenderer` (ours).
- PencilKit DOES render interactive content on device (live strokes, floating
  selections) — hence single-display-ownership in `ReadingPageView`.
- Assigning `canvas.drawing` a value equal to the current one is a PencilKit
  no-op — normalization must pass through an empty drawing first.
- Since 2026-08-20, PencilKit does not participate in inking at all: its
  recognizer runs only for eraser and lasso. Inking is observed, previewed and
  committed by our own pipeline — one stroke, one renderer, no handoff.
