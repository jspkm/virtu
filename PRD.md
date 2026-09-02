# Virtu — Product Requirements

**A sheet-music reader for classical musicians.** Universal app, iPad-first.

Status: **in build** — M0 and M1 shipped; M2/M3 partial; a P0 block sits ahead
of M4 (see §6.0 and `PLAN.md` Part IV).
Design reference: `Virtu.dc.html` + `README.md` (Claude Design handoff)
Last revised: 2026-08-20

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

> **Status: kept, and then some.** Fingers never ink, and the surrounding
> gestures are hardened past the rule (§7.2). The escape hatch shipped
> 2026-09-01 and closes the P0 recorded here: a Pencil-less iPad is offered
> "Draw with a finger" on the Tools screen, never on by default, and the
> offer disappears the moment a Pencil writes.

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

| Surface | Purpose | Handoff § | Status |
|---|---|---|---|
| **Library** | Choose what to play. Works addressed by composer / title / catalogue / edition / part — never by filename. | Screens § 1 | **DONE** — plus the personal shelf, sorts, and programmes. Binning with a recycle bin and full metadata correction both shipped; the P0 recorded here until 2026-09-01 was stale. |
| **Reading** | Play from the score. Two-page spread, edge taps to turn, centre tap to hide all chrome. | Screens § 2 | **DONE** — plus the Perform/Study wall, Corner Peek, Stage, pedals, scrubber. |
| **Annotation** | Non-modal tool rail: pencil, pen, highlighter, text, erase; four inks. No "done" button; page turns keep working while marking. | Screens § 2 | **PARTIAL** — everything but **text**. Layers, nib widths, line styles and free colour go past the spec. |
| **Find** | One field over the shelf. (Public-archive and in-score search are later — §6.) | Screens § 3 | **NOT BUILT** — the rail destination is a stub reading "Coming in M1". |
| **Tools** | Metronome, tuning reference, page-turn preferences. | Screens § 4 | **PARTIAL** — the metronome and the tuner are built (2026-08-28); the tuner also listens, which the handoff did not draw. Both are short of the bench specified in §5.1, and page-turn preferences are not built. The refusal in §6.0(3) is withdrawn. |

One of five rail destinations currently leads nowhere. Either build it or take
it out of the rail — a dead end at the stand costs more than a missing
feature.

---

### §5.1 — The bench, specified

The Tools screen is a bench with three things on it. The metronome and the tuner shipped
2026-08-28 as the minimum that answered a musician's request; this section specifies what
they must become to be worth a professional's trust, and what is built today.

A working musician does not carry two apps because one of them *nearly* does the job. The
test for everything below is the same as everywhere else: it must hold up at the stand.

#### The tuner

**Reference calibration.** A4 is continuously adjustable from **415.0 Hz to 456.0 Hz** in
0.5 Hz steps — baroque pitch at the bottom, sharp continental and brass-band pitch at the
top. Presets remain for the values people actually name (415, 430, 432, 435, 440, 442,
444, 446, 450, 456), and an explicit **Reset to 440** is always one tap away and visible
only when the reference is not 440. The reference is the only calibration in the product,
and everything the tuner says is relative to it.

> **BUILT, PARTIAL** — four fixed presets (442/440/432/415) that the setter *snaps* to.
> The continuous range, the steppers and the reset are not built.

**Target note.** Two modes, because they fail differently:

- **Auto (chromatic)** — the tuner names the nearest note. Right when you are close, and
  wrong in the one case that matters most: a string a semitone flat is confidently named
  as the note below, and the needle tells you that you are perfectly in tune with the
  wrong pitch.
- **Pinned** — you choose the note you are tuning to, from all twelve, and the reading is
  measured against *that* note in whichever octave is nearest. A slack D string reads as
  D, eighty cents flat, and stays D while you bring it up.

> **BUILT, PARTIAL** — auto only. Pinning is not built.

**Accidental spelling.** All twelve pitch classes are addressable, spelled with **sharps
or flats at the musician's choice** — a violinist in E major thinks D♯ and a clarinettist
in E♭ thinks E♭, and neither should have to translate. The choice applies everywhere a
note is named: the readout, the target picker, and the fork.

> **NOT BUILT** — sharps only, hardcoded.
>
> **Typographic note.** No bundled face carries U+266F/U+266D, so the accidentals resolve
> through the system font cascade and must be set as their own `Text` runs to sit
> correctly against the letter. §12 owns this.

**The reading.** Note, octave, signed cents, and the heard frequency; in tune is within
**±5 cents**, at which point the reading and the needle take the accent colour. The needle
is steadied in the data, never by a long view animation — a needle smoothed enough to hide
jitter is smoothed enough to lag the string.

> **DONE** — verified at 0.04 cents through a real microphone.

#### The tuning fork

A sounded reference, separate from the tuner because giving a pitch and checking a pitch
are two different jobs and the musician is doing exactly one of them at a time.

**Any of the twelve pitch classes, in octaves 4, 5 or 6** — C4 (261.6 Hz at A440) to B6
(1975.5 Hz) — computed from the A4 reference above, so a baroque player's fork is a
baroque fork. The sounding pitch is shown in hertz beside the note.

The tone is the fundamental plus four quiet partials, looped over a whole number of
cycles so the wrap is silent and the pitch is exactly the number displayed. It **stops
whenever the tuner starts listening, and cannot sound while the tuner listens** — an iPad's
microphone and speaker are a hand apart, and a tuner that hears its own fork reports, with
total confidence, that you are perfectly in tune.

> **BUILT, PARTIAL** — sounds A at the reference only. Note and octave selection are not
> built.

#### The metronome

**Tempo: 15 to 500 BPM**, named in the composer's vocabulary rather than a number —
*grave, largo, adagio, andante, moderato, allegro, vivace, presto, prestissimo*. The range
is not vanity: 15 is a conductor subdividing a grave, and 500 is a fiddle player checking a
reel at pitch. Coarse adjustment is a slider mapped **logarithmically**, because tempo
perception is logarithmic and a linear slider across 485 BPM cannot resolve a single beat
at the bottom; fine adjustment is ±1 steppers; tap tempo remains.

> **BUILT, PARTIAL** — 30 to 220, linear slider, no steppers. The word ladder stops at
> *presto* and has no *grave* or *vivace*.

**Meter: 1 to 7 beats to the bar**, beat one accented. One beat is a legitimate setting —
it is a plain pulse with no downbeat pattern, which is what you want when subdividing.

> **BUILT, PARTIAL** — 2 to 6.

**Rhythm.** Every beat may be subdivided, and the subdivision is a third, quieter voice
under the accent and the beat:

| | Clicks per beat | Where they fall |
|---|---|---|
| **Quarter** | 1 | the beat alone |
| **Eighths** | 2 | ½ |
| **Triplets** | 3 | ⅓, ⅔ |
| **Sixteenths** | 4 | ¼, ½, ¾ |
| **Swing** | 2 | ⅔ — the shuffle, not an even eighth |
| **Dotted** | 2 | ¾ — dotted-eighth and sixteenth |

> **NOT BUILT.** The click is one voice at one click per beat.

**What does not change.** The clock stays sample-accurate (§10): the bar is synthesised
into a buffer with every click at its exact sample offset and looped, so the gap between
two beats is a property of the file and not of when a timer fired. Subdivisions are more
offsets in the same buffer. At the fast end the click must shorten so that consecutive
clicks cannot overlap — 500 BPM in sixteenths is a click every 30 ms, shorter than the
click itself.


---

## §6 — Milestones

The design describes the destination. v1 is a subset. Several designed features quietly depend on score recognition and are staged accordingly. Each milestone has a gate; do not begin the next milestone until the current gate is met.

### §6.0 — Build status, 2026-08-20

Marked per item below. Five things are true across the whole document and are
easier to state once:

1. **"Done" here means implemented and passing the automated suite** (97 tests,
   `Tests/VirtuInkTests.swift`). Where hardware is the only possible proof, the
   item says so — `PLAN.md` Part V half 2 is the gate, and it has been
   exercised on an iPad mini but not signed off end to end.
2. **The rendering architecture deviates from §7.1**, deliberately and under
   duress: PencilKit's renderer draws nothing for programmatically-set drawings
   on iPadOS 26.x, so pages render through a bitmap `PageRenderer` and all
   committed ink through our own `InkRenderer`, on both display and export.
   `PDFView` is not used. This was the M0 spike's real finding.
3. **One M2 item is explicitly refused**, not merely unbuilt: iCloud sync,
   because a merge bug that eats annotations ends the product (§0.3). §8.2
   still specifies sync behaviour in detail and is retained as a description
   of the destination, not of v1.

   **The metronome and the tuning reference were also refused, and that
   refusal was reversed on 2026-08-27.** Both now ship. The refusal was
   reasoned from the premise that every professional already owns a dedicated
   one, and it survived only until a working musician used Virtu and went
   looking for them *inside* Virtu — which is the only evidence this document
   accepts (§0.5). Two further things had been true the whole time and were
   overlooked: the design handoff draws both tools in full on the Tools
   screen, and `VFont.bpmTools` had been sitting in the type scale waiting
   for one of them. The tuner goes past the handoff by also listening; a
   reference pitch tells you what to aim at, and the musician's complaint was
   about not being told how far off she was.
4. **The tuner has been heard end to end, but only in the simulator, and
   its first run can deadlock.** Played a 220Hz tone into the host
   microphone: the tuner named A3 and held 220.005Hz — 0.04 cents — for
   eleven seconds, then followed a change to D3 within one analysis. Naming,
   octave, cent accuracy, steadiness and re-latching are therefore observed
   behaviour rather than inference. An iPad's own microphone and its input
   processing are still untested.

   **The deadlock is the open risk.** Three times, `AVAudioEngine.inputNode`
   aborted the process inside `AURemoteIO::Initialize` ("RPC timeout.
   Apparently deadlocked"). The crash reports show it is a lock-ordering
   collision: the simulator's UI-sound device runner holds the
   `AQIONodeManager` lock through a one-time initialisation while the input
   unit waits on it, and the main thread gives up after nine seconds. Every
   observed abort was on a run that raised the microphone permission alert;
   once permission was granted, a dozen cold starts opened the input
   cleanly. The likely trigger is therefore **granting permission and
   opening the input in the same moment** — which is the path every new user
   takes exactly once. Unproven, and the first thing to watch on hardware.
5. **The seam (§9) was not built.** M2 shipped **Corner Peek** in its place —
   hold the forward tap zone to preview the next page, release to commit. The
   substitution was recorded in the M2 reading-experience design, consolidated away
   on 2026-09-01: Corner Peek answers "what is ahead", the seam answered "what is
   behind", and only the first shipped.
   The seam remains unbuilt and unretired.

### M0 — Skeleton · ~1 week · Simulator only — **DONE**

The minimum app that builds, runs on the iPad Simulator, and proves the critical integration spike.

- **DONE** — Xcode project: universal app (iPad + iPhone), SwiftUI lifecycle, deployment target iPadOS/iOS 17. Generated from `project.yml` (XcodeGen).
- **DONE, with the deviation in §6.0(2)** — the spike ran and returned a finding rather than a clean pass. Ink quality and coordinate lockstep are sound, but PencilKit will not display a drawing it did not just receive from a live pencil, so the display path is ours. `PDFView` is not used.
- **SUPERSEDED** — replaced by the M1 library and navigation.
- **DONE** — stroke round-trip, now through the full journal (§8.1) rather than the minimal placeholder.
- **DONE** — builds for the iPhone device family; no iPhone-specific layout, per §0.9.

**Gate: MET**, with the §6.0(2) deviation on record. Ink is Notability-grade and does not drift through zoom or page turns — but it is our renderer that draws it, not PencilKit's.

### M1 — "Does she stop using forScore?" · ~5 weeks · TestFlight, N=1 — **MOSTLY DONE**

The minimum that tests the actual hypothesis.

- **PARTIAL** — PDF import is the Files picker only. There is no share-sheet target, no `CFBundleDocumentTypes`, and no drag-and-drop: Virtu cannot currently receive a PDF from another app. For a product whose adoption story is "one piece at a time out of forScore" (§0.5, §3), this is the narrowest possible door.
- **DONE** — library grid, real first-page thumbnails, metadata entered on import.
- **DONE** — two-page spread, edge tap zones, centre tap to hide chrome, thumbnail strip.
- **DONE, and past scope** — pencil, highlighter, lasso, erase, undo/redo; four preset inks plus free colour choice; four nib widths and four line styles; annotation layers (§6.0 and the P0 spec).
- **DONE** — journal, compaction, silent replay on launch. Crash *recovery* is implemented; crash recovery is not yet *tested* — see §8.4.
- **DONE** — export flattens visible layers into a copy.
- **HOLDS** — no sync, and no settings screen. The metronome held here until 2026-08-28, when the refusal was reversed and it shipped early with the tuner; see §6.0(3).

**Gate: NOT EVALUATED.** No TestFlight build has gone out, so the one question this milestone exists to answer is still unanswered.

### M2 — Conservatory build · ~6 weeks · TestFlight, N≈20

- **NOT BUILT** — the seam. Corner Peek shipped instead; see §6.0(5) and §9.
- **DONE** — metronome. On a sample-accurate clock per §10, with beats to the bar past the handoff's fixed four. Refused until 2026-08-27; see §6.0(3).
- **DONE, PAST SCOPE** — tuning reference: the handoff's four references (A 442/440/432/415) as a sounding drone, *and* a listening tuner that names what it hears and shows the error in cents. Refused until 2026-08-27; see §6.0(3). The listening half is **UNVERIFIED ON HARDWARE** — see §6.0(4).
- **DONE** — Stage mode. Not an inversion: a luminance remap (paper to #0A0908, notation to warm white), and the default graphite ink flips to chalk so it cannot vanish on the dark page.
- **DONE, UNVERIFIED ON HARDWARE** — pedals arrive as keyboards and the key-command path handles them. Never tested against an actual AirTurn or PageFlip.
- **REFUSED** — iCloud sync. See §6.0(3); contradicts this line *and* §8.2.
- **PARTIAL** — fountain pen (as the calligraphic line style), four inks, lasso select and move: all done. **Text annotation is not built**, which also means §M4's "handwriting search over text annotations" has nothing to search.
- **NOT BUILT** — Tools screen. The rail destination is a stub reading "Debug panel — M1".

**Gate: NOT EVALUATED** — no cohort.

### M3 — App Store · ~8 weeks

- **NOT BUILT** — onboarding. A one-time hint line in the reading view is the whole of it.
- **DONE** — programmes, the "Next performance" panel, the set editor, and cross-piece paging on gig day.
- **NOT BUILT** — purchase flow.
- **PARTIAL** — the empty library state is designed and built. A failed import prints to the console and tells the musician nothing.
- **NOT BUILT** — accessibility pass. Controls carry labels; no VoiceOver walkthrough, no Dynamic Type in chrome, no contrast audit.
- **NOT MEASURED** — no crash reporting is wired up, so the ≥99.8% gate cannot currently be evaluated at all.

### M4 — **NOT STARTED** (one item arrived early: portrait layout is built — single page in portrait, spread in landscape)

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

> **OUTCOME (2026-08-20).** It proved *half* workable, and the half that failed
> was surfaced rather than papered over. PencilKit accepts pencil input
> correctly and records geometry faithfully, but on iPadOS 26.x it renders
> nothing for any drawing set programmatically — verified on simulator and on
> device. Committed ink therefore displays and exports through `InkRenderer`,
> ours; `PDFView` is not used and pages render through a bitmap `PageRenderer`.
> The recycling and zoom hazards listed above are handled; rotation and
> page-size changes do not resample, because strokes live in PDF-point space
> and are transformed only for display.
>
> The cost of that split is a two-renderer display-ownership problem — both
> PencilKit's layer and ours can draw the same stroke — which is now the single
> largest source of bugs in the app and the reason the ink regression suite
> exists. See `Virtu/Reading/ReadingPageView.swift`.

### 7.2 Input policy

```
if pencilEverPaired {
    canvas.drawingPolicy = .pencilOnly     // §0.2 — the wedge
} else {
    canvas.drawingPolicy = .anyInput
}
```

**Status:**

- **DONE** — `AnnotationInput.policy(pencilEverPaired:fingerDrawing:)` resolves
  §0.2's two halves in one place, and a Pencil-less iPad is no longer silently
  inert. `pencilEverPaired` has no API behind it; the proxy is having seen a
  Pencil write, latched on the ink observer's first pencil touch.

  **Worth knowing, because it caught the first implementation out:** setting
  `PKCanvasView.drawingPolicy` does not decide who may ink. PencilKit stopped
  participating in inking on 2026-08-20 (§6.0(2)) and its recognizer now runs
  only for the eraser and the lasso. The gate that admits a touch to the ink
  pipeline is our own recognizer's `allowedTouchTypes`. Both are derived from
  the one policy so they cannot drift apart.
- **DONE, and hardened past the spec** — finger contact is navigation only.
  Beyond that: the scroll view's pan and pinch are finger-only, so a stray
  pencil touch cannot move the page out from under a mark, and in Perform the
  canvas takes no touches at all.
- **NOT BUILT** — pencil double-tap to toggle the eraser.
- **HOLDS** — squeeze / hover remain out of scope.

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

**Status: MOSTLY DONE.** Ink lives in `StrokeJournal` as files, not in SwiftData.
Journal format v2 (2026-08-20) is keyed per **(part, layer, page)** — the
`AnnotationLayer` concept above is now a real, user-facing feature, numbered
1–10 with per-layer visibility.

| field | status |
|---|---|
| `drawingData` | **DONE** — PDF-point space, never screen space |
| `pageSize` | **DONE** — added in v2; nothing reads it yet, exactly as instructed |
| `schemaVersion` | **DONE** |
| `pageIndex`, layer | **DONE** — both in the storage key |
| `updatedAt`, `deviceID` | **NOT STORED** — file mtime is the only timestamp. The SwiftData `AnnotationLayer` model that declares them is orphaned: nothing reads or writes it. Either wire it up or delete it. |

Source PDF never modified, export flattens into a copy: **DONE**.

### 7.4 Required editing behaviours

These are the "Notability-level" bar. All are PencilKit-native except where noted.

- **PARTIAL** — pressure-responsive: `InkRenderer` strokes each segment at its own recorded width, which is what makes handwriting look handwritten. **Tilt is recorded but not rendered.**
- **DONE** — lasso select, move and delete. Scale is PencilKit's own and unverified.
- **PARTIAL** — erase by whole stroke (vector) only. **The pixel eraser and the user-selectable choice between them are not built.**
- **UNVERIFIED** — undo/redo work, including two- and three-finger taps and toolbar buttons. Neither the ≥50 depth nor survival across page turns has been tested, and the canvas is destroyed and rebuilt on every normalization, which is exactly where such a guarantee would quietly break.
- **NOT DONE** — ink and engraving are rasterized at zoom-1 resolution and scaled up, so writing small while zoomed in is soft. Now more pressing: as of 2026-08-20 a zoomed page can be panned, so musicians can reach the corners they could not reach before, and will write there.
- **DONE** — highlighter composites under ink, within a layer.
- **DONE** (2026-08-20) — tool, colour, nib and line style all persist across launches.

---

## §8 — Reliability requirements

"forScore is buggy" is the competitive claim. Claims need engineering behind them.

### 8.1 Durability

- Every stroke is persisted within **250 ms of pencil-up**. Append-only journal per page; periodic compaction into the canonical `PKDrawing` blob.
- Journal writes are atomic and `fsync`'d. A crash mid-write loses at most the in-flight stroke.
- On launch, any journal newer than its compacted blob is replayed silently. **No dialog. No "recovered document" banner.** The user sees their marks and nothing else.
- No Save button anywhere in the product.

**Status: BUILT, UNPROVEN.** Append-only journal per (part, layer, page),
`FileHandle.synchronize()` before the compacted write, atomic writes, silent
replay on launch, and no Save button anywhere: all **DONE**. Journals written
before the v2 format are replayed to the v1 path and read forward, so the
format change cost nothing.

What is **not** done is the evidence. The 250 ms budget has never been measured
— persistence fires from `canvasViewDrawingDidChange`, which is plausible but
unmeasured — and the kill-mid-stroke test in §8.4 does not exist. §0.3 says
this is the product; right now it is the part of the product with the least
proof behind it.

### 8.2 Sync

- CloudKit private database. Annotation layers and work metadata sync; PDF binaries sync only if the user opts in per work (they can be large and are often licensed material).
- **Conflict resolution is union of strokes, never last-writer-wins.** If the same page is edited on two devices, the user gets both sets. Losing a bowing to a merge is unacceptable; a duplicate is merely annoying.
- Sync state is never surfaced as a blocking UI. At most, a quiet indicator in Settings.

**Status: NOT BUILT, AND NOW REFUSED.** `PLAN.md` Part IV lists cloud sync under
"Still refusing to build" — the reasoning being §0.3 itself: a merge bug eats
annotations, and eaten annotations end the product. AirDrop plus annotated-PDF
export is the sharing story instead.

That is a defensible call, but it is a **contradiction with this section as
written and with §6 M2**, and it costs the union-merge design above, which is
the good answer to the hard part. Resolve deliberately: either strike sync from
M2 and §8.2, or un-refuse it. Leaving both statements standing is how a
requirement gets quietly lost.

### 8.3 Budgets

| Metric | Target |
|---|---|
| Crash-free sessions | ≥99.8% at submission, ≥99.9% steady state |
| Strokes lost, ever | 0 |
| Cold launch to last-read page | <1.2 s on iPad Pro M1 |
| Page turn to first paint | <100 ms for a cached spread |
| Ink latency | Match PencilKit's native floor; no added frame |
| Import, 60-page PDF | <8 s to a usable library entry |

**Status: NOT MEASURED — none of them.** No crash reporting is wired up, no
launch or turn timing is instrumented, and no import has been timed. Page turns
are architected for the budget (pre-rendered ±1 spread, so a turn is pure
compositing) but that is a design intention, not a number. "Strokes lost, ever:
0" is the one that matters most and the one §8.4 was supposed to prove.

### 8.4 Testing

- **NOT BUILT** — kill the app mid-stroke, at 50 randomized points; assert zero stroke loss on relaunch. The single most important missing test in the project.
- **NOT APPLICABLE while sync is refused** — two-device concurrent edit, assert union.
- **PARTIAL** — the hand-on-glass test now lives in `PLAN.md` Part V half 2, an 11-step protocol run on a physical iPad with a real Pencil. It has been exercised during development and has caught real defects, but it has never been run end to end as a release gate, and there has been no TestFlight to gate.

**What does exist:** 32 automated tests in `Tests/VirtuInkTests.swift`, covering
geometry round-trips, ink rendering and position, canvas input space, the
display-ownership state machine, layer isolation, journal v2, line-style
carriers and the nib ladder. That suite is the reason several regressions in
this document's own features were caught before reaching hardware — but it
tests the ink pipeline, not durability under crash, which is what §0.3
actually promises.

---

## §9 — The seam (carried-over system)

The design calls this "the single most important novel behaviour." It is also the only v1 feature that needs geometry from the page, so it needs a technical note.

> **Status: NOT BUILT.** M2 shipped **Corner Peek** instead — hold the forward
> tap zone past 150 ms to slide in a preview of the *next* page, release past
> 400 ms to commit the turn, release earlier to cancel free. Note that this
> solves the opposite problem: Corner Peek looks *forward* before you turn, the
> seam carries the last system *backward* after you have turned. A player who
> needs the final bars of the page they just left is still unserved.
>
> The seam is the only v1 feature needing page geometry, and it is described in
> the design handoff as the single most important novel behaviour. It is
> neither built nor retired. `Tokens.swift` still carries a `seamStrip` radius
> and nothing uses it.

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

**Status.** `Work`, `Part`, `Programme` (built as `Program`/`ProgramItem`) and
the annotation layers are **DONE**, in SwiftData. Divergences worth knowing:

- **`PageGeometry` does not exist** — it was for the seam (§9), which was not
  built. Nothing computes system rects at import.
- **`Preferences` does not exist as a type.** What persists, persists ad hoc in
  `UserDefaults`: shelf name, tool, colour, nib, line style, and the one-time
  hint flag, the metronome's tempo and meter, and the tuner's reference A.
  `tuningPreset` is therefore live, though it persists as hertz rather than as
  an enum case — the same four values, stored so that a future free reference
  is a wider setter rather than a migration. `seamHoldSeconds`, `halfPageTurns`
  and `fingerDrawing` still have nothing to configure; `stageMode` is live but
  resets each launch, and `bluetoothPedal` is always-on with no switch.
- **Layer state lives on `Part`** (`layerCount`, `activeLayerIndex`,
  `hiddenLayerIndices`), so a score reopens exactly as it was left.

Metadata on import: attempt to parse composer / title / catalogue from the PDF's title page and embedded metadata, then **always show a confirmation sheet**. Per the design copy — *"You confirm; nothing is filed silently."* That promise is load-bearing; a wrongly-filed score is a lost score.

> **DONE, both halves.** The confirmation sheet always appears and cannot be
> skipped, and a wrongly-filed score can be corrected in the work-info sheet or
> binned and restored from the recycle bin. The second half was recorded here as
> an open P0 until 2026-09-01, by which time it had already shipped.

---

## §12 — Design system

Tokens, type scale, spacing, radii, and motion are specified exactly in the design handoff `README.md` and must be transcribed once into `DesignSystem/` as the single source of truth. Do not duplicate hex values inline.

Summary for orientation only — **the handoff is authoritative**:

- **Palette**: warm paper `#F2EFE8` / plate `#FFFDF8` / ink `#16151A`, red-pencil accent `#B33F26`, dark rail `#161519`. Stage mode is a full token swap, not a filter.
- **Type**: Newsreader (serif — titles, work names, tempo words), Archivo (sans — all controls), JetBrains Mono (figures — catalogue numbers, BPM, page numbers). All OFL, bundle them.
- **Surfaces use borders, not shadows.** Keep it that way.
- **Motion**: four named curves, below. No page-curl skeuomorphism.

### §12.1 — Motion and haptics

Absorbed from `docs/2026-08-15-design-language.md` on 2026-09-01, which this replaces.
The one-line summary that stood here until then ("120 ms control transitions, 220 ms
spread turn") disagreed with both this table and the shipped code; **this table is what
the code implements.**

| Curve | Timing | Used for |
|---|---|---|
| **Turn** | 90 ms, `easeOut(0,0,.2,1)` | page turns only |
| **Settle** | 260 ms, `cubic(.32,.72,0,1)` | mode transitions, chrome reveal, panels — the signature motion |
| **Snap** | `spring(0.32, damping .86)` | tool rail, loupe, swatch selection — tactile, touch-triggered |
| **Drift** | 180 ms, `ease(.4,0,.2,1)` | ambient opacity fades (idle-dim, peek cancel, tuner lock) |

Indicators are not animations: the metronome lamps and the tuner needle run at 60 ms and
100 ms linear respectively, because anything slower lags the thing it is reporting.

**Haptics.** Mode switch = light on gesture recognition, medium on settle completion — a
deliberate two-beat "tap…click," like a mechanical mode dial. Page turn = **none in
Perform** (hard rule: zero risk of a felt "error buzz" mid-concert), `.selection` in Study
on tap-zone turns only (a swipe already has kinesthetic feedback). Ink/swatch selection =
`.selection`. Undo/redo = `.rigid`. Corner Peek commit = the same tick as a turn; cancel =
none.

**Never animates in Perform.** Page-turn easing beyond the 90 ms Turn curve (no spring, no
overshoot, ever); idle chrome pulsing; onboarding or coach-marks; any haptic beyond the
single Study-only turn tick; orientation reflow (snaps instantly at 0 ms — Study *does*
animate this with Settle). Theme swaps never happen automatically on a timer or a sensor,
only on a deliberate toggle.

### §12.2 — Mode, chrome and Stage

**The always-visible state signal, spending no chrome.** In Study only, the page carries a
1.5 pt hairline inset 4 pt from its edge, accent at 35% opacity (paper) / 50% (Stage), and
its corner radius softens from 0 pt to 6 pt — the page stops being the screen and becomes
an object placed on a surface. In Perform the stroke is absent entirely. Internally the
metaphor is **music stand** (Perform) versus **desk** (Study); never surface "stand/desk"
as UI copy.

**Perform chrome is zero, with one exception:** a page readout, bottom-centre, mono 11 pt,
"12 / 34", fading 40% → 15% after 4 s idle and never to 0 — page-position anxiety costs
more than that sliver. **Study chrome is binary:** the top bar and the scrubber reveal and
dismiss together, never partially. The tool rail is tied to *mode*, not chrome state, so
hiding chrome to see more page never strands the tools.

**Stage is orthogonal to Perform/Study**, giving a valid 2×2 — a teacher marking at night
wants Stage+Study; a musician outdoors in daylight wants Paper+Perform. Fusing them would
remove real use cases. Stage is a **luminance remap**, not a colour invert (which flips
noteheads to a photo negative, alien to printed music) and not sepia-on-black: background
to `#0A0908`, notation to warm white preserving relative contrast, printed colour keeping
hue while gaining lightness. Swap rasters on toggle; never a live per-frame filter.

**Stage + Perform, the pit-orchestra case:** the page readout's floor drops further,
40% → 20%; paper grain (3% in Paper) drops to 0%, since grain reads as sensor noise on
true black. No other pairing-specific logic is needed.

**Stage Manager:** below roughly 820×600 pt, force portrait single-page logic regardless of
window aspect. Perform disables resize *animation* — window changes snap instantly, since a
mid-performance resize is rare but must never be a visual event.

> **Superseded by what shipped, and recorded so nobody re-derives it:** the design
> language's ink-preset table (four fixed `PKInk` configs) and its five-tool list were
> replaced by the P0 ink controls — four preset inks plus free colour choice, four nib
> widths, four line styles, and a fixed first swatch per tool. See §7. The Loupe and the
> radial eraser picker described there are still unbuilt (PLAN Part IV, M4).

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
| Stage | Status |
|---|---|
| M0 | **PASSED**, with the §6.0(2) deviation — ink is at parity, but our renderer draws it |
| M1 | **NOT EVALUATED** — no TestFlight build has gone out |
| M2 | **NOT EVALUATED** — no cohort |
| M3 | **NOT REACHED** |
| M5 | **NOT REACHED** |

| Stage | Success | Kill |
|---|---|---|
| M0 | PencilKit over PDFKit delivers Notability-grade ink; no coordinate drift through zoom | Ink quality or integration is unworkable → kill the project |
| M1 | Hannah uses Virtu for her current piece two weeks unprompted | She drifts back to forScore → stop, diagnose, do not build M2 |
| M2 | ≥6 of 20 conservatory testers weekly at week 4 | <3 → the wedge is thinner than believed; reassess before App Store work |
| M3 | 200 paying users in 6 months; ≥1 teacher distributing marked parts to students | <50 in 6 months → maintain, do not expand |
| M5 gate | Users asking, unprompted, for cross-edition mark transfer | Nobody asks → the score layer stays unbuilt |

**The technical kill is now M0, not a side note.** If PencilKit-over-PDFKit cannot deliver ink quality at parity with Notability, the entire premise fails and no amount of design saves it. M0 exists to answer this before anything else is built.

> **The M0 kill did not fire, but it did not pass cleanly either.** Ink quality
> and coordinate fidelity are there. What failed was PencilKit's *renderer*, and
> the workaround — owning display and export ourselves — is now the app's main
> source of bugs. Worth watching as a slow version of the same risk.
>
> The more pressing observation: **M1's gate has never been evaluated.** The
> project is building M2, M3 and P0 features on top of a hypothesis that was
> supposed to be tested at M1 and was not. §6 says do not begin the next
> milestone until the current gate is met. That instruction is being disregarded
> — deliberately or by drift, but it should be one and not the other.

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
