# Virtu Roadmap — after M3

North star test (from the performer vision): *hand the iPad to a violinist five
minutes before a run-through of the Schubert — repeats, fast turns, dim hall —
with no explanation. If anything on that screen surprises them before the
double bar, it's a bug.* Every feature below must justify itself at the stand,
in the dark, in bar 340.

Shipped so far: M0 spike · M1 library/reading/ink/journal · M2 mode wall,
turn engine, pedal keys, Corner Peek, ink v2, Stage remap, scrubber ·
M3 personal shelf, programs with cross-piece paging, set editor
(dated performances + undated collections), mode discoverability.

> **2026-08-20:** Stamps are parked by founder decision until the core writing
> experience is great — the strip UI and placement were removed from the app;
> the glyph engine survives in `Virtu/Annotation/StampLibrary.swift` for
> revival. An ink regression suite now gates changes (`Tests/VirtuInkTests`).

## P0 — before M4  *(founder decision, 2026-08-20)*
Layers, the top-right mode/library icons, a toolbar that never fades, and the
pencil thickness/style/colour flyout. Full spec:
[P0 — Layers, mode/library icons, and the ink controls](2026-08-20-p0-layers-and-ink-controls.md).

Layers and the per-stroke style/width data land as **one** journal format
change — one migration of existing ink, not two — and carry the authored
`pageSize` (PRD 7.3) with them.

## M4 — Ink you'd show your stand partner  *(needs real hardware)*
The Pencil-only thesis, cashed in. Simulator cannot fake a Pencil, so this
milestone is built against a physical iPad.

1. **Curated stamp row** — the ~12 marks that are 95% of real use: down-bow ⊓,
   up-bow ∨, eyeglasses, breath comma, fermata, accent, pp–ff dynamics, circle.
   One row, tap to arm, tap to place, drag to nudge. Never a stamp "library."
2. **Fingering micro-mode** — arm it and a tiny 0–4 picker rides the pencil;
   each tap places a crisp numeral. Faster than writing, always legible.
3. **Lasso-move** — marks land wrong constantly; select-and-nudge is the
   difference between a clean part and chicken scratch.
4. **Scoped erase** — "clear my practice highlights, keep my bowings."
5. **The Loupe** — deferred from M2: pencil-summoned 3× magnifier, ink commits
   at true scale.
6. **Hardware tuning session** — latency on ProMotion, pencil feel per preset,
   a real AirTurn/PageFlip pedal against the key-command path.

## M5 — The part that plays itself  *(structure over ink)*
1. **Cuts as navigation** — cross out a passage in Study; Perform's page turns
   skip it. Ink that changes behavior: the first "only Virtu does this."
2. **Rehearsal-mark anchors** — conductor says "letter K," you're there in one
   tap while the paper players flip. Authored in Study, jumped from the
   scrubber.
3. **Movements with page anchors** — "go to mvt. III" from the work card.
4. **Repeat/D.S. links** — tap source, tap destination, done.
5. **Classic half-page turn** — per-piece portrait option alongside Corner Peek.

## M6 — Repertoire ops  *(the librarian story)*
1. **Import ritual v2** — filename parsing with aggressive autocomplete,
   batch import, margin cropping at import (persistent, per part).
2. **Multi-part works** — cello I/II, score↔part, instant switching.
3. **Layers** — mine / section / this-program, per-layer visibility and export.
   A librarian distributes a bowed part whose bowings can't be erased.
4. **Share the bowed part** — annotated-PDF export polish + AirDrop flow.

## Craft debt (continuous, cheap, compounding)
- Accessibility pass: VoiceOver labels, Dynamic Type in chrome.

> Shipped since this list was written: bundled fonts, app icon, the ghost-sliver
> rail, and Stage-remapped scrubber thumbnails.

## Still refusing to build
Metronome/tuner (commodity clutter), cloud sync (AirDrop covers sharing;
sync bugs eat annotations and eaten annotations end the product), OMR/AI,
audio/video sync, face-gesture turns, reflow. Each would trade stand-trust
for feature-list length.
