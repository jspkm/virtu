# Virtu — Product Requirements

**A sheet-music reader for classical musicians.** Universal app, iPad-first.

Status: pre-build
Design reference: `Virtu.dc.html` + `README.md` (Claude Design handoff)
Last revised: 2026-08

---

## §0 — Working agreement

> Copy this section into `CLAUDE.md` at the repo root. Everything below §0 is specification; §0 is the set of rules that must not be broken without an explicit decision.

### 0.1 The pitch is one sentence

**A music reader you can actually write in.**

Not "forScore with more features." Not an AI music platform. The user's complaint — verified with a real cellist — is that writing in the incumbent is physically bad: you cannot rest your hand on the glass. Every scoping decision resolves against that sentence.

### 0.2 Fingers never draw

`PKCanvasView.drawingPolicy = .pencilOnly` whenever an Apple Pencil has ever been paired with the device. This is a **default, not a preference**. Finger contact is always navigation, never ink.

The incumbent ships this as a buried setting because fifteen years of users draw with their fingers and changing the default would break them. We have no installed base. We just do the right thing.

A "let me draw with my finger" escape hatch may exist in Settings for Pencil-less users, but it is never the default when a Pencil is present, and it is never auto-enabled.

### 0.3 A stroke is never lost

Not on crash, not on force-quit, not on battery death, not on sync conflict, not on low storage. Every stroke is durable within 250 ms of pencil-up (§8). There is no Save button and there is never a "restore unsaved changes?" dialog.

This is the product. Ship late rather than ship this wrong.

### 0.4 Local-first, always

Everything works with the device in airplane mode on a dark stage. Sync is additive and never authoritative over local state. A sync failure is invisible to the user and retried; it never blocks, blanks, or reverts a page.

### 0.5 We are the workbench, not the library

Users will keep forScore. They adopt Virtu **one piece at a time** — the work they are currently studying — and migrate the rest over months or never. Every design decision assumes the user has another reader installed and is not leaving it. Nothing in the product may assume, require, or nag toward full migration. See §3.

### 0.6 Simpler than the incumbent, not richer

The target user asked for *less*, done properly. Any proposed feature must answer: does this help someone play from, or write on, the page in front of them? If it does not, it is out. Feature parity with forScore is explicitly **not** a goal.

### 0.7 No recognition engine in v1

No OMR, no measure detection, no note reading, no MusicXML. The one exception is staff-line/system geometry for the seam (§9), which is classical CV, runs on-device, and must degrade silently to "no seam" when it fails.

Musical-coordinate features are v2 and are gated on v1 having real users.

### 0.8 The score is the interface

Chrome is dismissable to zero. When chrome is hidden, nothing but paper is on screen — no floating buttons, no persistent handles, no badge. Hiding chrome must never stop a running metronome or drop the selected pen.

### 0.9 Universal app, iPad-first

Virtu is a **universal app** (iPad + iPhone), but the design target for v1 is **11″ iPad Pro landscape (1194 × 834 pt)**. iPhone layouts are undesigned and deferred past v1. The app must build and run on iPhone from M0, but no iPhone-specific layout work is in scope until after the iPad experience ships and has real users.

### 0.10 The design handoff is authoritative on appearance

Colors, type, spacing, radii, and timings in `README.md` are exact. Do not improvise. Where this PRD and the design handoff disagree on *scope*, this PRD wins; where they disagree on *appearance*, the handoff wins.

---

## §1 — Why this exists

Classical musicians read from iPads. The incumbent, forScore, has been the default for fifteen years and is a competent, well-run product. Users complain about it constantly and almost never leave.

The specific, repeatable complaint that opened this project: **you cannot rest your hand on the screen while writing.** A musician annotating a part hovers their hand, which is fatiguing and degrades their handwriting, dozens of times per practice session. Modern note-taking apps (Notability, GoodNotes) solved this years ago.

This is structural, not neglect. forScore is a *reader* first, so finger contact is ambiguous — page turn, pan, or palm? A note-taking app has no such ambiguity. And forScore's installed base includes many users who draw with a finger because they own no Pencil, so making the correct behaviour the default would break them.

We start clean. The correct behaviour is our default on day one.

**Secondary, verified complaints to confirm before building around them:**

- General instability / lost annotations. Needs to be resolved into a specific list before it drives any engineering.
- Ink quality relative to Notability: pressure response, lasso-select-and-move, stroke erase, zoomed-in precision, real multi-level undo. Most of this comes free with PencilKit.

---

## §2 — Users

| | |
|---|---|
| **Primary** | Conservatory-level and serious amateur classical performers. Annotate heavily, own an Apple Pencil, already use forScore, work on 1–3 pieces intensively at a time. |
| **Secondary** | Private teachers, who mark up their own copy and want the student to receive it. Teachers are the distribution channel — one teacher reaches fifteen students. |
| **Explicitly not** | Orchestral librarians (that was a different product), pop/rock musicians, worship bands, choral directors, anyone whose primary need is setlist management. |

Design placeholder persona in the handoff is "Nadia." Replace with real content; do not ship a fictional name.

---

## §3 — The coexistence model

This is the most important non-visual requirement and it is not in the design handoff.

**The user has forScore installed and is not uninstalling it.** They will try Virtu on the *next* piece they are assigned. The library will be small — one to five works — for months. Everything must feel correct at N=1.

Requirements this imposes:

1. **Import must be trivial and must work from forScore.** forScore exports annotated PDFs and supports the share sheet and drag-and-drop. Virtu must accept:
   - Share-sheet import (`Open in Virtu`) — implement a Share Extension
   - Files app / iCloud Drive / Dropbox via `UIDocumentPickerViewController`
   - Drag-and-drop onto the library grid and onto the import panel
   - AirDrop
2. **An annotated PDF imported from forScore arrives flattened.** Their marks are pixels in the page, not editable strokes. This is expected and acceptable. Display them as part of the page; new Virtu strokes layer on top. Do not attempt to extract them in v1.
3. **No migration flow, no migration prompt, no "import your whole library" wizard, no progress counter toward migration.** Ever. If the user wants to bring in fifty works they can select fifty files.
4. **No empty-library guilt.** The library at N=1 must look deliberate, not broken. The design's three-column grid needs a genuinely good 1-item and 0-item state — both currently undesigned (§15).
5. **Export must be first-class.** A user must be able to get an annotated PDF *out* of Virtu at any time, into forScore or anywhere else. No lock-in. Lock-in is what we're competing against.

---

## §4 — Non-goals

Do not build these. Do not propose building these.

- Note/pitch/rhythm recognition, MusicXML, MEI
- Playback, transposition, part extraction from a score
- Score following, audio-to-score alignment
- Audio recording synced to annotations
- A chatbot, copilot, or "ask the score" interface
- Cloud accounts, social features, sharing feeds, a marketplace
- A store for purchasing sheet music
- Android, web, macOS (iPhone is in scope as a universal binary but layout design is deferred past v1)
- Feature parity with forScore

---

## §5 — Product surface

Five surfaces, fully specified for appearance in the design handoff. Scope per release is in §6.

| Surface | Purpose | Handoff § |
|---|---|---|
| **Library** | Choose what to play. Works addressed by composer / title / catalogue / edition / part — never by filename. | Screens § 1 |
| **Reading** | Play from the score. Two-page spread, edge taps to turn, centre tap to hide all chrome. | Screens § 2 |
| **Annotation** | Non-modal tool rail: pencil, pen, highlighter, text, erase; four inks. No "done" button; page turns keep working while marking. | Screens § 2 |
| **Find** | One field over the shelf. (Public-archive and in-score search are later — §6.) | Screens § 3 |
| **Tools** | Metronome, tuning reference, page-turn preferences. | Screens § 4 |

---

## §6 — Milestones

The design describes the destination. v1 is a subset. Several designed features quietly depend on score recognition and are staged accordingly. Each milestone has a gate; do not begin the next milestone until the current gate is met.

### M0 — Skeleton · ~1 week · Simulator only

The minimum app that builds, runs on the iPad Simulator, and proves the critical integration spike.

- Xcode project: universal app (iPad + iPhone), SwiftUI lifecycle, deployment target iPadOS/iOS 17
- **PencilKit-over-PDFKit spike**: a single hardcoded PDF rendered in a `PDFView`, one `PKCanvasView` overlaid, `.pencilOnly` drawing policy. Confirm ink quality and coordinate-space lockstep at multiple zoom levels. This is the §7.1 hazard check.
- Single-screen app: opens straight to the reading view with the bundled PDF. No library, no navigation, no chrome beyond the PencilKit tool picker.
- Stroke round-trip: draw, quit, relaunch — strokes reappear. Minimal file-based persistence (not the full journal yet).
- Builds and runs on iPhone Simulator too (default layout, no iPhone-specific design).

**Gate:** PencilKit over PDFKit delivers Notability-grade ink with no coordinate drift through zoom and page scroll. If it does not, this is a kill finding (§14). Do not proceed to M1.

### M1 — "Does she stop using forScore?" · ~5 weeks · TestFlight, N=1

The minimum that tests the actual hypothesis.

- PDF import (share sheet, Files, drag-and-drop)
- Library grid — real PDF first-page thumbnails, work metadata entered by hand on import
- Reading view: two-page spread, edge tap zones, centre tap to hide chrome, thumbnail strip
- **Annotation via PencilKit, `.pencilOnly` default** — pencil, highlighter, erase, undo/redo, three inks
- Stroke journaling and crash recovery (§8)
- Export annotated PDF
- No sync. No metronome. No settings screen beyond a debug panel.

**Gate:** Hannah uses Virtu for her current piece, unprompted, for two consecutive weeks. If she drifts back to forScore, stop and find out why before writing more code.

### M2 — Conservatory build · ~6 weeks · TestFlight, N≈20

- **The seam** (§9), behind a feature flag, default on
- Metronome (sample-accurate audio clock, background-safe)
- Tuning reference (A 442 / 440 / 432 / 415 — a sine generator, *not* a microphone tuner)
- Stage mode incl. PDF inversion
- Bluetooth pedal (AirTurn, PageFlip) for page turns
- iCloud sync of works and annotation layers
- Full tool rail: fountain pen, text, four inks; lasso select and move
- Tools screen with real preferences

**Gate:** ≥6 of 20 testers still opening it weekly at week 4, without prompting.

### M3 — App Store · ~8 weeks

- Onboarding (three screens maximum; the first thing it does is offer to import a PDF)
- Programmes / setlists — the "Next performance" panel in the design
- Purchase flow (§13)
- Empty, error, and failed-import states
- Full accessibility pass: VoiceOver, Dynamic Type in chrome, contrast
- Crash-free session rate ≥99.8% before submission

### M4

Half-page turns · part switcher for multi-part works · iPhone layout · portrait layout · IMSLP search and import · handwriting search over text annotations

### M5 — the score layer

Only if M3 has real users. Measure and rehearsal-mark detection; in-score "landmark" search; and the reason the engine exists: **a teacher marks their copy, and the marks land correctly on the student's different edition, at the student's engraving size.** That is the defensible product. It is not M3.

---

## §7 — The annotation engine

The core of the product. Get this wrong and nothing else matters.

### 7.1 Framework

**PencilKit** (`PKCanvasView`, `PKDrawing`, `PKToolPicker` — custom UI, not Apple's picker) composited over **PDFKit** (`PDFView` / `PDFPage`).

This is the highest-risk integration in the project. Known hazards, to be spiked in week one:

- One `PKCanvasView` per visible page, overlaid on the `PDFPage`'s bounds; coordinate spaces must be kept in lockstep through zoom and scroll
- Memory: canvases must be recycled outside the visible window, and `PKDrawing` for offscreen pages held as data, not live views
- Zoom: `PKCanvasView` has its own scroll/zoom that must be disabled and driven by the PDF view
- Rotation and page-size changes must not resample strokes

If PencilKit-over-PDFKit proves unworkable at acceptable quality, that is a v0.1 kill finding and must be surfaced immediately, not worked around.

### 7.2 Input policy

```
if pencilEverPaired {
    canvas.drawingPolicy = .pencilOnly     // §0.2 — the wedge
} else {
    canvas.drawingPolicy = .anyInput
}
```

- Finger contact when `.pencilOnly`: routed to navigation (tap zones, swipe, pinch-zoom). Never ink, never a stray dot.
- Pencil double-tap (Pencil 2) → toggle eraser, per system convention.
- Squeeze / hover (Pencil Pro) → out of scope for v1, do not block on it.

### 7.3 Stroke storage

Strokes are stored **per page, in PDF page coordinate space** — never screen space, never normalized to the current zoom.

```
AnnotationLayer
  id, workID, partID, pageIndex
  drawingData: Data          // PKDrawing.dataRepresentation()
  pageSize: CGSize           // the PDF page box these strokes were authored against
  schemaVersion: Int
  updatedAt, deviceID
```

Storing `pageSize` alongside the drawing is what lets a future version re-project strokes onto a different edition (v2). Do not omit it because v1 does not use it.

Layers are separate from the PDF file. The source PDF is never modified. Export flattens on demand into a copy.

### 7.4 Required editing behaviours

These are the "Notability-level" bar. All are PencilKit-native except where noted.

- Pressure- and tilt-responsive ink
- **Lasso select, then move / scale / delete a group of strokes**
- Erase by whole stroke *and* by pixel, user-selectable
- Multi-level undo/redo, ≥50 steps, surviving page turns within a session
- Zoom in and write small without ink coarsening
- Highlighter composites *under* ink, not over it
- Tool and colour selection persist across launches

---

## §8 — Reliability requirements

"forScore is buggy" is the competitive claim. Claims need engineering behind them.

### 8.1 Durability

- Every stroke is persisted within **250 ms of pencil-up**. Append-only journal per page; periodic compaction into the canonical `PKDrawing` blob.
- Journal writes are atomic and `fsync`'d. A crash mid-write loses at most the in-flight stroke.
- On launch, any journal newer than its compacted blob is replayed silently. **No dialog. No "recovered document" banner.** The user sees their marks and nothing else.
- No Save button anywhere in the product.

### 8.2 Sync

- CloudKit private database. Annotation layers and work metadata sync; PDF binaries sync only if the user opts in per work (they can be large and are often licensed material).
- **Conflict resolution is union of strokes, never last-writer-wins.** If the same page is edited on two devices, the user gets both sets. Losing a bowing to a merge is unacceptable; a duplicate is merely annoying.
- Sync state is never surfaced as a blocking UI. At most, a quiet indicator in Settings.

### 8.3 Budgets

| Metric | Target |
|---|---|
| Crash-free sessions | ≥99.8% at submission, ≥99.9% steady state |
| Strokes lost, ever | 0 |
| Cold launch to last-read page | <1.2 s on iPad Pro M1 |
| Page turn to first paint | <100 ms for a cached spread |
| Ink latency | Match PencilKit's native floor; no added frame |
| Import, 60-page PDF | <8 s to a usable library entry |

### 8.4 Testing

- Automated: kill the app mid-stroke, at 50 randomized points; assert zero stroke loss on relaunch.
- Automated: two-device concurrent edit of one page; assert union.
- Manual, before each TestFlight: write a full page of bowings with hand resting flat on the glass. Zero stray marks. This is the acceptance test for the entire product.

---

## §9 — The seam (carried-over system)

The design calls this "the single most important novel behaviour." It is also the only v1 feature that needs geometry from the page, so it needs a technical note.

**Behaviour** (appearance fully specified in the handoff): on a **forward** turn only, a strip pins to the top of the new spread showing the **final system of the page just left**, for a user-configurable hold (default 4 s, range 0–10, 0 disables). Never on a backward turn. Cleared immediately on a deliberate thumbnail jump.

**Implementation.** This needs system bounding boxes, which needs staff-line detection. That is the *easiest* part of optical music recognition and does not require the v2 engine:

1. Render the page to grayscale at ~150 dpi
2. Horizontal projection profile → peaks are staff lines
3. Group lines into staves (5 lines, consistent spacing), staves into systems (vertical proximity + shared barlines)
4. Persist system rects per page at import time, in page coordinate space
5. At turn time, the strip is a cheap crop of the cached page raster — no work on the hot path

**Requirements:**

- Runs at import, never during a page turn
- Must complete in <200 ms per page on-device
- **Must degrade silently.** If detection is low-confidence or fails, the seam simply does not appear for that page. No error, no placeholder, no fallback to "bottom 15% of the page" — a wrong crop is worse than none.
- Feature-flagged. If it proves unreliable across real editions, ship v1 without it.

Note the honest risk: this is the feature most likely to look magical in a demo and disappoint on a photocopied part.

---

## §10 — Architecture

| Layer | Choice | Notes |
|---|---|---|
| UI | **SwiftUI**, UIKit-hosted where needed | `PDFView` and `PKCanvasView` are UIKit; wrap them |
| PDF | **PDFKit** | Rendering, page geometry, text extraction for metadata guessing |
| Ink | **PencilKit** | §7 |
| Persistence | **SwiftData** or Core Data + custom journal | The journal (§8.1) is hand-rolled regardless; do not rely on the ORM for stroke durability |
| Sync | **CloudKit** private DB | §8.2 |
| Audio | **AVAudioEngine** | Metronome must use a sample-accurate clock, not `Timer`/`setInterval`, and must survive backgrounding and screen dim |
| Page geometry | **vImage / Accelerate** | §9 staff detection; no ML, no third-party CV dependency |
| Pedal | **Core Bluetooth** + HID keyboard events | Most page-turn pedals present as BLE keyboards; handle both |
| Min OS | **iOS / iPadOS 17** | Universal app. Gets modern PencilKit and SwiftData without carrying legacy paths |

**Third-party dependencies: none in v1.** Every capability above is first-party Apple. This is deliberate — the product promise is reliability, and each dependency is a reliability risk we do not control.

### Repo layout

```
virtu/
  Virtu/                  # app target
    Library/              # library grid, work metadata
    Reading/              # spread, tap zones, chrome, seam
    Annotation/           # PencilKit integration, tool rail
    Tools/                # metronome, tuning, preferences
    DesignSystem/         # tokens from the design handoff — one source of truth
  VirtuKit/               # framework: model, persistence, journal, import, page geometry
                          # NO UIKit/SwiftUI imports. Unit-testable headless.
  VirtuShare/             # share extension
  Tests/
  DesignReference/        # Virtu.dc.html + README.md, checked in, read-only
```

`VirtuKit` must never import the app target and must be testable with no UI present.

---

## §11 — Data model

```
Work
  id, composer, title, catalogueNumber, edition, year
  parts: [Part]
  createdAt, lastOpenedAt
  // NOTE: no "study progress %" — see §15.4

Part
  id, workID, name              // "cello", "piano reduction", "cello II"
  pdfFileURL, pageCount
  pageGeometry: [PageGeometry]  // §9, computed at import

PageGeometry
  pageIndex, pageSize
  systemRects: [CGRect]         // page coordinate space; empty = detection failed
  detectionConfidence: Float

AnnotationLayer                 // §7.3

Programme                       // v1.0
  id, name, date, venue
  items: [ProgrammeItem]        // ordered (workID, partID, note, duration)

Preferences
  seamHoldSeconds: Int = 4
  halfPageTurns: Bool = false
  bluetoothPedal: Bool = true
  showHints: Bool = true
  tuningPreset: enum = .a442
  stageMode: Bool = false
  fingerDrawing: Bool = false   // §0.2 — only settable when no Pencil paired
```

Metadata on import: attempt to parse composer / title / catalogue from the PDF's title page and embedded metadata, then **always show a confirmation sheet**. Per the design copy — *"You confirm; nothing is filed silently."* That promise is load-bearing; a wrongly-filed score is a lost score.

---

## §12 — Design system

Tokens, type scale, spacing, radii, and motion are specified exactly in the design handoff `README.md` and must be transcribed once into `DesignSystem/` as the single source of truth. Do not duplicate hex values inline.

Summary for orientation only — **the handoff is authoritative**:

- **Palette**: warm paper `#F2EFE8` / plate `#FFFDF8` / ink `#16151A`, red-pencil accent `#B33F26`, dark rail `#161519`. Stage mode is a full token swap, not a filter.
- **Type**: Newsreader (serif — titles, work names, tempo words), Archivo (sans — all controls), JetBrains Mono (figures — catalogue numbers, BPM, page numbers). All OFL, bundle them.
- **Surfaces use borders, not shadows.** Keep it that way.
- **Motion**: 120 ms control transitions, 220 ms `cubic-bezier(.4,0,.2,1)` spread turn, 60 ms linear metronome lamps. No page-curl skeuomorphism.

Stage mode requires the PDF itself to render inverted, not merely recolored. Budget real time for this — naive inversion of a scanned score looks dreadful, and this feature is for people reading in an orchestra pit who will notice.

---

## §13 — Pricing & distribution

**Recommendation: one-time purchase, no subscription.** The incumbent's price anchor is roughly $20 and the target audience — students and working musicians — is subscription-hostile. A one-time price also reinforces the positioning: the calm, careful, un-grabby option.

Suggested: **$24.99 one-time**, with a genuinely usable free tier capped at 3 works so the palm-rejection difference can be felt before paying.

Distribution is App Store only. There is no other channel, which is a known strategic weakness of this product and is accepted.

---

## §14 — Success and kill criteria

Revenue here is a signal, not income. The bar is set accordingly and honestly.

| Stage | Success | Kill |
|---|---|---|
| M0 | PencilKit over PDFKit delivers Notability-grade ink; no coordinate drift through zoom | Ink quality or integration is unworkable → kill the project |
| M1 | Hannah uses Virtu for her current piece two weeks unprompted | She drifts back to forScore → stop, diagnose, do not build M2 |
| M2 | ≥6 of 20 conservatory testers weekly at week 4 | <3 → the wedge is thinner than believed; reassess before App Store work |
| M3 | 200 paying users in 6 months; ≥1 teacher distributing marked parts to students | <50 in 6 months → maintain, do not expand |
| M5 gate | Users asking, unprompted, for cross-edition mark transfer | Nobody asks → the score layer stays unbuilt |

**The technical kill is now M0, not a side note.** If PencilKit-over-PDFKit cannot deliver ink quality at parity with Notability, the entire premise fails and no amount of design saves it. M0 exists to answer this before anything else is built.

---

## §15 — Open questions

1. **Portrait.** Undesigned. Single page, or continuous scroll? Deferred to v1.x, but decide before the reading view's layout hardens.
2. **Half-page turns.** A preference in the design, but the mid-spread layout was never drawn.
3. **Multi-part works.** The Dvořák carries a piano reduction; the part switcher is undesigned.
4. **Study progress.** The library card shows a progress bar. What does it measure? If there is no honest answer, cut it — a fake metric is worse than a plain card. Currently omitted from the data model on purpose.
5. **Empty and near-empty library.** Critical given §3: the library will hold one work for weeks. Undesigned.
6. **Failed import.** A corrupt, encrypted, or 400-page PDF. Undesigned.
7. **Licensed material.** Many parts are rented and copyrighted. Sync of PDF binaries defaults off for a reason; confirm this is the right default before v0.5.

---

## §16 — What this bets on

1. That palm rejection and ink quality are a real, felt, repeated pain — not one motivated user being kind to her father. Validated cheaply by App Store review analysis and five conversations with her peers, and that work should happen *before* v0.1.
2. That PencilKit over PDFKit reaches Notability-grade ink. Validated in week one.
3. That per-piece adoption works — that people will genuinely run two readers and let the better one win the next piece.
4. That "it just works" is a sufficient reason to switch in a category where the incumbent is entrenched but disliked.
5. That a one-time $25 purchase in a small market produces enough users to matter. This is the weakest bet, and it is the one that does not resolve until v1.0.

Bets 1 and 2 are cheap and early — bet 2 is now M0. Bet 5 is late and expensive. Sequence the work accordingly.
