# Virtu — Interaction & Motion Spec: Reading Modes, Ink, Chrome, Stage

## 1. The Mode Model

**Naming:** *Perform* (rehearsal/performance) and *Study* (markup). Internally, think physical metaphor — **music stand** (Perform: nothing but the page) vs **desk** (Study: tools within reach) — but never surface "stand/desk" as UI copy; it's the design rationale, not the label.

**Always-visible state signal (no persistent chrome):** In Study mode only, the page carries a **1.5pt hairline stroke** inset 4pt from its edge, accent-terracotta at 35% opacity (paper) / 50% (stage). In Perform mode this stroke is absent entirely. This single cue, always in peripheral vision, tells the user their mode without spending any chrome. Additionally, page corner radius softens from 0pt (Perform, page = screen) to 6pt (Study, page reads as an object placed on a surface).

**Primary switch — discoverable:** A pill toggle in the top chrome (replaces the M1 "markup toggle" 1:1). Two icon states, no persistent labels: `eye.fill` (Perform) / `pencil.tip` (Study). Tap to toggle.

**Primary switch — effortless/always-reachable:** A **two-finger double-tap** anywhere on the page toggles mode instantly, regardless of chrome visibility. Deliberately a finger gesture (never pencil — pencil is reserved for marks) and deliberately two fingers (won't collide with single-finger page-turn taps).

**Transition animation (Perform→Study):** page scales 100%→98.5% over 260ms (*Settle* curve, see §5) as if recessed onto a desk; writable-edge stroke fades in (0→1 opacity, 180ms, 80ms delay); floating tool rail slides up from bottom (24pt→0, spring response 0.32/damping 0.86). Reverse for Study→Perform, but faster (exits always resolve quicker than entries: 160ms rail exit, 120ms stroke fade).

**Haptics:** light `.impact` fires the instant the two-finger gesture is recognized; medium `.impact` fires when the settle animation completes — a deliberate two-beat "tap…click" rhythm, like a mechanical mode dial engaging.

**Pencil behavior by mode:**
- *Perform:* Pencil contact does **nothing** — no hover preview, double-tap is a no-op, squeeze (Pencil Pro) disabled. This is a hard safety rule: no accidental mark mid-concert.
- *Study:* Pencil hover (M2/Pencil Pro, iOS 17) shows a ghost preview (12pt above surface) of current tool width/color. Double-tap uses system default `.switchEraser` — don't reinvent a convention every Notability/GoodNotes user already knows. Squeeze (Pencil Pro, gated by hardware) opens a radial quick-tool palette.

**Stage Manager:** Below a minimum content size (~820×600pt), force portrait-single-page layout logic regardless of window aspect. Perform mode disables resize *animation* — window changes snap instantly (0ms), never reflow with motion, since a mid-performance resize is rare but must never be a visual event.

## 2. Page Display & Navigation

**Layout:** Portrait = single page, margin 0pt (Perform, edge-to-edge under safe area) / 24pt (Study, room for rail + palm rest). Landscape = two-page spread, 2pt gutter rendered as an 8pt soft inner-shadow gradient (12% opacity) — never a hard rule line. Page width = `(screenWidth − margins − gutter) / 2`; height computed from source PDF aspect, clamped and centered vertically.

**Turn interaction (unified tap + swipe):** Left 20%/right 20% = invisible prev/next tap zones (kept from M1); center 60% = chrome toggle. A fast horizontal swipe anywhere (velocity >400pt/s, dx >60pt) also turns the page and takes priority over tap-zone logic. All navigation gesture recognizers gate on `UITouch.type != .pencil` — pencil never navigates.

**Turn animation — crossfade, not curl, not slide:** page curl is decorative noise; a slide implies scrolling continuity that's wrong for notation tracking. Instead: simultaneous 90ms crossfade (outgoing 1→0 opacity, incoming 0→1) with a 4pt directional micro-offset that settles to 0 — reads as a "flick," not a journey. Curve: *Turn* (easeOut, 90ms). No shadow, no 3D, no spring/bounce — ever. **Latency budget: <120ms** touch-to-rendered, achieved by always keeping ±1 page pre-rendered/cached so the turn is pure compositing, never live PDFKit decode.

**Thumbnail scrubber:** bottom chrome, Study mode default / long-press-summoned in Perform. ~48pt-wide thumbnails at page aspect, 4pt gutter, momentum scroll with page-snap, current page marked by a 2pt accent underline, `.selection` haptic tick per page crossed while dragging.

**The "peek" problem — Corner Peek:** Route the existing next-page tap zone by hold duration on the same recognizer: release <150ms = instant turn (as above); hold 150–400ms = a small preview card (15% of page width, bottom-right corner, 8pt radius, 85% opacity, shadow `0,2,8,rgba(0,0,0,.15)`) slides in over 140ms showing the next page's opening system, tracking finger position while held; release past 400ms auto-commits the turn (90ms crossfade), release before that snaps back with no haptic (cancels are free). This replaces the clumsy "half-page turn" real musicians do by curling a physical corner — same intent, zero visual clutter.

## 3. Ink Experience — Study Mode

**Presentation:** edge-docked, not Procreate-floating — a floating palette drifts and obscures notation exactly where precision matters (near barlines). Dock right edge, vertically centered, 56pt wide, auto-height, 12pt corner radius, `ultraThinMaterial`, 1pt hairline border (accent, 15% opacity). Idle-dims to 30% opacity after 3s, restores to 100% on touch or pencil-hover proximity (within 40pt).

**Tools (5):** Fingering pencil (`PKInkType.pencil`), Highlighter (`PKInkType.marker`), Correction pen (`PKInkType.pen`), Text/stamp box, Eraser. Below: **3 ink swatches, per tool**, 28pt circles, selected state = 2pt ring offset 3pt outside + `.selection` haptic. **Slot 1 is fixed** and is the tool's own colour (graphite `#26221E` for the pencil, `#E8A33D` for the highlighter) — it cannot be re-coloured, so it can never be lost. **Slots 2 and 3 are the musician's**, changed by holding the swatch (0.4s, `.rigid` haptic) to open the system colour picker, and persisted per tool. Defaults: pencil `#C0392B` / `#2563C7`; highlighter `#7FBF3F` / `#5FB8DE`. The palettes differ by tool on purpose — a wash and a line want different colours. Amended 2026-08-21; supersedes the flat four-preset row and the separate custom-colour control.

**Eraser model:** stroke eraser (`PKEraserTool(.vector)`) by default — whole-stroke deletion, since partial scrubbing leaves ragged marks against clean engraving. Long-press the eraser icon opens a 2-item radial (Stroke / Precision `PKEraserTool(.bitmap)`, 8pt radius), 120ms fade+scale-in.

**Undo/redo:** two-finger single tap = undo, two-finger double tap = redo (matches Notability/Pages muscle memory; keeps pencil free to draw). Fallback icon (`arrow.uturn.backward`, 36pt target) at top of the rail for discoverability.

**Zoom-to-annotate — the Loupe:** double-tap-and-**hold with the pencil** on a spot summons a 120pt circular magnifier at 3x zoom, offset 60pt above the touch point so the hand doesn't block it (iOS text-loupe pattern, repurposed for drawing). Drawing while active writes at full precision into the underlying full-res space. 120ms scale-in (0.8→1.0, ease-out). Solves tiny-fingering precision without a pinch-zoom-draw-unzoom cycle.

**Ink presets (PKInk configs):**

| Preset | Type | Width | Paper hex | Stage hex |
|---|---|---|---|---|
| Fingering (graphite) | `.pencil` | 2.0pt | `#4A4238` @85% | `#C9C2B4` @80% |
| Phrase highlighter | `.marker` | 14pt | `#E8A33D` @28% | `#E8A33D` @20%, normal blend |
| Correction (red) | `.pen` | 1.6pt | `#C0392B` @90% | `#E8564A` @85% |
| Accent/expression | `.pen` | 1.8pt | `#B5654A` @90% | `#D68868` @88% |

## 4. Chrome Architecture

**Perform:** zero persistent chrome, page bleeds under `.ignoresSafeArea(.all)`, status bar hidden, `.persistentSystemOverlays(.hidden)` to suppress the home-indicator false-touch zone. **One exception:** a tiny page readout, bottom-center, JetBrains Mono 11pt, "12 / 34," 40%→15% opacity after 4s idle, never fully 0 — page-position anxiety costs more than this sliver of chrome.

**Study:** top bar (44pt, `ultraThinMaterial`: back, title, mode pill, export) and bottom bar (scrubber) reveal/dismiss **together as one binary state** — tap-center or two-finger swipe from top edge — never partial. The floating tool rail is independent of chrome visibility (tied to *mode*, not chrome state), so hiding nav chrome to see more page never strands the tools.

**Nav rail in reading views:** collapses to a 12pt "ghost edge" sliver (8% opacity), expands on pencil-hover or edge-swipe — standard iPadOS sidebar-collapse (Notes, Files), never fully hidden (zero affordance = lost users), never full-width during reading.

**"Paper on a stand, not an app with a document":** no visible frame around the page in Perform (page = background); 3% opacity fine-grain paper texture (overlay blend); Study-only ambient vignette (radial, transparent center → 4% black edges); the writable-edge stroke does double duty as the "this is a surface" cue.

## 5. Motion & Haptic Language

| Curve | Timing | Used for |
|---|---|---|
| **Turn** | 90ms, easeOut(0,0,.2,1) | page turns only |
| **Settle** | 260ms, cubic(.32,.72,0,1) | mode transitions, chrome reveal, panels — the signature motion |
| **Snap** | spring(0.32, damping .86) | tool rail, loupe, swatch selection — tactile, touch-triggered |
| **Drift** | 180ms, ease(.4,0,.2,1) | ambient opacity fades (idle-dim, peek cancel) |

**Haptics:** mode switch = light on gesture recognition, medium on settle completion. Page turn = none in Perform (hard rule — zero risk of a felt "error buzz" mid-concert), light `.selection` in Study on tap-zone turns only (swipe already has kinesthetic feedback). Ink/swatch selection = `.selection`. Undo/redo = `.rigid`. Corner Peek commit = same tick as a turn; cancel = none.

**Never animates in Perform:** page-turn easing beyond the 90ms Turn curve (no spring, no overshoot, ever); idle chrome pulsing; onboarding/coach-marks; any haptic beyond the single Study-only turn tick; orientation reflow (snaps instantly, 0ms — Study *does* animate this with Settle, 260ms); theme swaps never happen automatically on a timer or sensor, only on deliberate toggle.

## 6. Stage Mode

Stage (true-black theme) is **orthogonal to Perform/Study** — recommend clearly, don't fuse them. This yields a valid 2×2: a teacher marking a score at night wants Stage+Study; a musician performing outdoors in daylight wants Paper+Perform. Forcing Stage↔Perform removes real use cases.

**What pure black means:** not a color invert (flips noteheads to a "photo negative" reading, alien to printed music) and not sepia-on-black (unneeded color cast). Instead: **luminance remap**, precomputed per page and cached alongside the paper raster — background drops to `#0A0908`, notation remaps to warm-white `#EDE7DC` preserving relative contrast, and any printed color content (e.g. a red rehearsal mark) keeps hue while gaining lightness. Swap rasters on theme toggle; never a live per-frame filter.

**Brightness:** on first entering Stage, if device brightness >40%, show a one-time non-blocking toast — "Stage Mode looks best around 30% — Adjust" — ramping `UIScreen.brightness` to 0.3 over 400ms only on explicit tap. Never auto-adjust silently (a borrowed/shared iPad shouldn't get dimmed without asking).

**Stage + Perform composition (the flagship pit-orchestra case):** page-number readout's floor drops further, 40%→20% max opacity; paper-grain texture (3% in Paper theme) drops to 0% in Stage, since grain reads as sensor noise on true black rather than texture. No other pairing-specific logic is needed — Stage is purely a luminance layer sitting under interaction-mode rules, so gesture, chrome, and motion behavior compose unchanged in every quadrant.
