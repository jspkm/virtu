# Virtu M2 — The Reading Experience, Designed

Synthesis of two expert reviews: [the performer's product vision](2026-08-15-performer-vision.md)
(10-year forScore user's critique + roadmap) and [the interaction/motion spec](2026-08-15-design-language.md)
(ADA-bar iOS design language). This document records the decisions and the M2 scope.
Where the two documents disagreed, the resolution is noted.

## Decisions

### D1. Two modes with a hard wall: Perform and Study
- `Perform`: the page and nothing else. No chrome, no tool UI, pencil completely inert,
  no haptics, no animations beyond the 90ms page-turn crossfade. Center tap does
  **nothing** (forScore's original sin was ambient chrome on center tap).
  Only persistent element: a faint page readout "12 / 34" bottom-center (mono 11pt,
  dims to 15% opacity when idle, never fully gone).
- `Study`: full annotation surface — tool rail, scrubber, chrome, loupe.
- Switching: **two-finger double-tap** anywhere toggles (both directions, finger-only
  gesture, can't collide with page-turn taps or pencil). Plus a visible mode pill in
  Study chrome. Entering Perform plays a one-time 260ms "settle" transition;
  in-Perform nothing ever animates without user cause.
- Mode indicator without chrome: in Study the page shows a hairline accent stroke
  inset 4pt and 6pt corner radius ("page on a desk"); in Perform the page is
  edge-to-edge with no frame ("page is the screen").
- Resolution: performer doc called the modes "Stage/Study"; design doc showed
  Stage-the-theme must stay orthogonal to mode (teacher marking scores at night =
  Stage+Study). **Perform/Study are modes; Stage remains the dark theme.** 2×2 valid.

### D2. Page display
- Portrait: single page, always. Landscape: two-page spread. (Shipped in the interim
  fix; M2 refines margins per mode: 0pt Perform, 24pt Study.)
- Page turn: 90ms crossfade with 4pt directional micro-offset. No curl, slide,
  spring, or shadow. Latency budget <120ms via a pre-rendered ±1 page cache —
  turns are pure compositing, never live PDF decode.
- Turn inputs: edge tap zones (kept) + fast horizontal swipe + Bluetooth pedal +
  keyboard arrows. All gated to non-pencil touches. Redundant turn paths are a
  safety system.
- **Corner Peek** (the half-page-turn answer): hold the next-page tap zone 150ms+
  to slide in a preview card of the next page's opening system; release past 400ms
  commits the turn, release earlier cancels free. Classic top/bottom half-page turn
  becomes a per-piece option in M3.

### D3. Ink (Study only)
- Tool rail: edge-docked right, 56pt wide, ultraThinMaterial, idle-dims to 30%
  after 3s. (Replaces both the current floating rail and the system PKToolPicker —
  one tool surface, not two.)
- Four presets tuned for score marking (graphite fingering pencil 2.0pt,
  phrase highlighter 14pt, correction red 1.6pt, expression 1.8pt) with paper/stage
  color pairs specified in the design doc.
- Eraser: stroke eraser (`.vector`) default; precision bitmap eraser via long-press.
- Undo: two-finger tap; redo: three-finger tap (PencilKit system gestures) +
  rail fallback buttons.
- Loupe zoom-to-annotate: pencil double-tap-and-hold summons a 120pt 3× magnifier;
  ink commits at true scale. This is how fingerings become legible.
- Pencil double-tap: system `.switchEraser`. Hover preview on M2 Pencils.

### D4. Stage theme
- Luminance remap (not invert, not sepia): paper → #0A0908, notation → warm-white
  #EDE7DC, precomputed and cached per page, swapped on toggle.
- Brightness suggestion toast on first entry (never silent adjustment).
- Perform mode keeps the screen awake (`isIdleTimerDisabled`) while reading.

### D5. What we are NOT building (explicit)
Metronome/tuner, reflow, face gestures, audio sync, cloud sync, OMR/AI, hot corners,
the 100-stamp library. Every feature must justify itself "at the stand, in the dark,
in bar 340."

## M2 scope (in order)

1. **Mode wall v2** — rename state to perform/study, two-finger double-tap toggle,
   settle transition, Perform hygiene (no center-tap, idle timer off, page readout,
   status bar hidden), haptics per spec.
2. **Turn engine** — page image cache (±1 pre-rendered), crossfade turn, swipe
   gesture, keyboard/pedal input (UIKeyCommand: arrows, page up/down, space),
   Corner Peek.
3. **Ink v2** — docked tool rail replacing PKToolPicker + old rail, four presets,
   stroke eraser default, undo/redo gestures, loupe.
4. **Stage remap** — luminance-remapped page rendering + brightness toast.
5. **Scrubber** — real page thumbnails (rendered async), page-snap, accent underline.

Deferred to M3: programs/setlists with cross-piece paging, import ritual polish,
per-part cropping, links/cuts-as-navigation, layers (mine/section/program),
curated stamp row + fingering micro-mode, classic half-page turn option.

## Open questions for the founder

1. Corner Peek replaces the classic half-page turn in M2 — acceptable, or is the
   classic forScore-style half-page turn needed from day one?
2. The performer doc wants leaving Perform to take slightly more intention than
   entering. Current design: the same two-finger double-tap both ways. Add a
   press-and-hold-corner alternative, or keep symmetric?
3. Default mode when opening a work: currently Perform (safe). Right call?
