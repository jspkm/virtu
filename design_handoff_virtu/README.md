# Handoff: Virtu — iPad sheet-music reader

## Overview

Virtu is a tablet-first sheet-music reader: a musician's library of scores, a
full-bleed reading view built around page turns, an annotation layer, unified
search/import, and practice tools (metronome, tuning reference).

The design argument, in priority order — implement in this order too:

1. **The score is everything.** Chrome is dismissable to zero. A tap in the
   middle of the reading view removes every control; only paper remains.
2. **Page turns never eat a phrase.** On a forward turn, the last system of the
   page you just left is carried over in a strip pinned to the top of the new
   spread for ~4 seconds, then fades. This is the single most important novel
   behaviour in the product.
3. **The library thinks in repertoire, not files.** Works are addressed by
   composer / title / catalogue number / edition / part — never by filename.
   Programmes (concert sets) are first-class and sit above the grid.
4. **Stage-ready.** A dark "stage mode" palette for pit lighting, reachable in
   one tap from any screen.
5. **Editorial typography** everywhere outside the score itself.

## About the design files

`Virtu.dc.html` in this bundle is a **design reference written in HTML** — a
working prototype of the intended look and behaviour. It is **not production
code to port**. The task is to recreate these screens in the target codebase's
own environment (SwiftUI / React Native / React, etc.) using its established
patterns, navigation, and component library. If no codebase exists yet, pick
the framework appropriate to the platform (SwiftUI is the natural choice for an
iPad-first score reader with PDF rendering and Bluetooth pedal support) and
implement the designs there.

Open it by serving the folder (it loads a sibling `support.js`) and browsing to
`Virtu.dc.html`. All five surfaces are interactive.

**Score notation in the prototype is procedurally generated placeholder
engraving** (an SVG function seeded per piece). In the real app every one of
those regions is a rendered page of a real PDF. Do not port the generator.

## Fidelity

**High-fidelity.** Colors, type, spacing, radii, and transition timings below
are final and exact. Recreate pixel-accurately, substituting the codebase's
existing primitives where they already match.

The prototype is drawn at a fixed **1194 × 834 pt** canvas (11″ iPad Pro,
landscape) inside a device bezel. The bezel is presentation only — discard it.
Layout is landscape-first; portrait is not designed (see Open questions).

---

## Design tokens

### Color — light ("paper")

| Token | Hex | Use |
|---|---|---|
| `paper` | `#F2EFE8` | App background, all screens |
| `plate` | `#FFFDF8` | Score pages, cards, inputs |
| `ink` | `#16151A` | Primary text, primary buttons |
| `muted` | `#75726B` | Secondary text, inactive labels |
| `faint` | `#A9A49A` | Tertiary / metadata text |
| `line` | `#E0DBD1` | Hairline dividers, card borders |
| `line2` | `#CFC9BD` | Stronger borders, control outlines |
| `accent` | `#B33F26` | Red-pencil accent: active page, progress, eyebrows |
| `blue` | `#2B3E5E` | Secondary tag color (IMSLP results) |
| `wash` | `#E9E5DC` | Filled panels, hover fill, tag backgrounds |
| `notation` | `#1A1A1F` | Engraved staves and noteheads |
| `rail` | `#161519` | Left nav rail, floating dark panels |
| `railink` | `#EDE9E1` | Text on rail |
| `railfaint` | `#8A857C` | Inactive rail icons/labels |

### Color — stage mode (dark)

| Token | Hex |
|---|---|
| `paper` | `#0B0B0D` |
| `plate` | `#131317` |
| `ink` | `#E6E2DA` |
| `muted` | `#8B877F` |
| `faint` | `#63605A` |
| `line` | `#26262B` |
| `line2` | `#35353B` |
| `accent` | `#D9694E` |
| `blue` | `#7C93BC` |
| `wash` | `#1A1A1F` |
| `notation` | `#C9C5BC` |
| `rail` | `#0B0B0D` |
| `railink` | `#E6E2DA` |
| `railfaint` | `#6B6862` |

Stage mode is a token swap only — no layout changes. `notation` inverting to a
light gray means score pages must be rendered through an invert/contrast filter
(or re-rasterized), not just recolored.

### Typography

Three families, one job each:

- **Serif — Newsreader** (Google Fonts; weights 300/400/500, italic 300/400).
  All titles, work names, page headings, tempo words. Never for UI controls.
- **Sans — Archivo** (400/500/600). Every control, label, eyebrow, body of
  running UI copy.
- **Mono — JetBrains Mono** (400/500). Catalogue numbers, BPM, page numbers,
  timestamps, Hz values, file sizes. Anything a musician reads as a *figure*.

Scale as used:

| Role | Family | Size | Weight | Tracking / notes |
|---|---|---|---|---|
| Screen title | serif | 38px | 400 | `letter-spacing:-.015em`, `line-height:1.1` |
| Section heading | serif | 20–21px | 400 | |
| Work title (card) | serif | 17px | 400 | `line-height:1.25`, `text-wrap:pretty` |
| Score title (on page) | serif | 15px | 400 | centered on plate |
| Now-playing title | serif | 17px | 400 | truncates with ellipsis |
| Tempo word | serif italic | 15–18px | 400 | |
| Eyebrow | sans | 10.5px | 600 | `letter-spacing:.14em`, uppercase, `accent` |
| Rail label | sans | 9.5px | 500 | `letter-spacing:.04em`, uppercase |
| Panel label | sans | 9.5–10.5px | 600 | `letter-spacing:.14em`, uppercase, `muted` |
| Control / button | sans | 12–13.5px | 500 | |
| Body | sans | 12.5–13px | 400 | `line-height:1.55` |
| Metadata | sans | 11–11.5px | 400 | `muted` |
| Search input | sans | 15px | 400 | |
| BPM (panel) | mono | 44px | 500 | `letter-spacing:-.02em` |
| BPM (tools) | mono | 60px | 500 | `letter-spacing:-.03em` |
| Catalogue no. | mono | 10.5px | 400 | `faint` |
| Page number | mono | 9px | 400 | |

Minimum type size anywhere: 9px (mono page numbers only). Nothing
interactive is below 11px.

### Spacing, radii, motion

- Spacing steps in use: 2, 4, 6, 7, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28,
  32, 34, 38, 40, 48. Treat 4px as the grid unit.
- Screen padding: `34px 40px 48px`.
- Radii: `3px` page thumbnails · `4px` score pages (outer corners only) ·
  `8px` small controls · `10px` buttons and list rows · `11px` tool buttons ·
  `12px` search input, seam strip · `14px` cards, panels · `16px` floating dark
  panels · `999px` pills, swatches, toggles.
- Hit targets: rail buttons 56×~48, annotation tools 44×44, tap zones 170px
  wide full-height. Nothing interactive smaller than 34×46 (page thumbnails).
- Transitions: `120ms ease-out` for color/background/border on controls;
  `150ms ease-out` for thumbnails and toggle tracks; `150ms cubic-bezier(.4,0,.2,1)`
  for toggle knob travel; `220ms cubic-bezier(.4,0,.2,1)` for the spread turn;
  `60ms linear` for metronome beat lamps.
- Named keyframes: `rs-fade` (opacity 0→1, 160–180ms ease-out) for chrome and
  overlays appearing; `rs-rise` (opacity 0→1 + `translateY(14px)`→0, 180ms
  `cubic-bezier(0,0,.2,1)`) for the metronome sheet.
- Elevation: only two shadows exist and both are presentation-layer (device
  bezel). **In-app surfaces use borders, not shadows.** Keep it that way.

---

## Global chrome

### Left nav rail

76px wide, full height, `rail` background, vertical flex, `padding:18px 0 14px`.

Top to bottom: wordmark (26×26 SVG — four staff lines with an `accent` vertical
stroke at x≈10), 14px gap, then four destination buttons, a flex spacer, the
stage-mode toggle, then a 30px round avatar (`#3A3833` fill, initials in
`railink`, 11px/600).

Each destination button: 56px wide, `padding:9px 0 7px`, `radius:10px`, icon
(20px, 1.6px stroke, round caps) above a 9.5px/500 uppercase label, 5px gap.
Active: `#FFFDF8` text on `rgba(255,255,255,.10)`. Inactive: `railfaint` on
transparent.

Destinations and their icons (all 24-viewbox line icons):

| Label | Screen | Icon |
|---|---|---|
| Library | library | Three vertical book spines, the third slanted |
| Score | reading | Pencil |
| Find | search | Magnifier |
| Tools | tools | Vertical strokes of descending height (a metronome scale) |

Stage toggle sits above the avatar, always `railfaint`, label "Stage". Icon is
a crescent moon in light mode, a sun in stage mode.

---

## Screens

### 1. Library — "Nadia's shelf"

Purpose: choose what to play, from repertoire and from the next concert.

Scrolling column, `34px 40px 48px` padding, three stacked blocks.

**Header row** — baseline-aligned, `space-between`, 24px gap, 28px bottom
margin. Left: eyebrow "Repertoire" (`accent`) · 9px gap · `h1` "Nadia's shelf"
(serif 38px) · 8px gap · one line of body copy, max-width 520px:
"Six works in study. Two performances scheduled this month." Right: three sort
pills — "Recently played" (default, active), "By composer", "By programme".
Pill: `padding:7px 14px`, `radius:999px`, 12px/500, `white-space:nowrap`,
`flex:none`. Active `ink`/`paper`; inactive `muted` text on transparent with a
`line2` border.

**Next performance panel** — `wash` fill, `1px line2` border, `radius:14px`,
`padding:22px 24px`, 34px bottom margin, horizontal flex, 32px gap, centered.
- Left column, 186px fixed, `border-right:1px line2`, `padding-right:24px`:
  eyebrow "Next performance" · serif 21px "Wigmore recital" · mono 11.5px
  `muted` "14 MAR · 19:30".
- Middle: three equal programme cards in a 10px-gap row. Card: `plate` fill,
  `1px line2`, `radius:10px`, `padding:13px 14px`; mono 10px `faint` roman
  numeral (I / II / III), serif 16px title, 11.5px `muted` "composer · duration".
  Hover: border → `accent`.
- Right: "Open set" button, stretch-aligned, `padding:0 20px`, `radius:10px`,
  `ink` fill, `paper` text, 13px/500.

Programme contents: I — Cello Suite no. 1, Bach · 18 min. II — String Quintet
in C, Schubert · 52 min. III — Piano Quartet no. 1, Brahms · 40 min.

**All works** — a heading row (serif 20px "All works" · a 1px `line` rule
filling remaining width · mono 11px `faint` count), 16px gap, then a
**3-column grid, 20px gap**.

Work card: `plate` fill, `1px line`, `radius:14px`, column flex, overflow
hidden. Hover: border → `accent`.
- **Preview** 148px tall, `border-bottom:1px line`, `position:relative`. The
  rendered first page sits inset `-14px 16px auto 16px` at 210px tall (so it
  bleeds off the top), 0.9 opacity, with a 52px bottom gradient
  `transparent → plate` fading it out. In production: the PDF's first page,
  same crop and fade.
- **Body** `padding:15px 16px 16px`, 6px gap: composer 11.5px `muted` · title
  serif 17px · a metadata row (mono 10.5px `faint` catalogue no. · a 3px round
  `faint` dot · 11px `muted` part name) · flex spacer · a footer row 12px above
  the bottom: a 2px `line` progress track (`radius:2px`) filled to the study
  percentage in `accent`, then mono 10px `faint` last-opened relative date.

Seed data (composer / title / catalogue / edition / part / pages / last opened /
progress):

1. J. S. Bach · Cello Suite no. 1 in G major · BWV 1007 · Bärenreiter,
   Schwemer/Woodfull-Harris · cello · 14pp · yesterday · 62%
2. Antonín Dvořák · Cello Concerto in B minor · Op. 104 · Henle, Del Mar ·
   cello, piano reduction · 62pp · 4 days ago · 28%
3. Franz Schubert · String Quintet in C major · D. 956 · Bärenreiter urtext ·
   cello II · 38pp · last week · 90%
4. W. A. Mozart · Piano Sonata no. 11 in A major · K. 331 · Wiener Urtext,
   Füssl · piano · 22pp · 2 weeks ago · 15%
5. Johannes Brahms · Piano Quartet no. 1 in G minor · Op. 25 · Henle · viola ·
   54pp · 3 weeks ago · 44%
6. Béla Bartók · Contrasts for violin, clarinet, piano · Sz. 111 · Boosey &
   Hawkes · violin · 31pp · a month ago · 5%

Tapping any card, programme card, or "Open set" enters the reading view at
spread 2 with chrome shown.

### 2. Reading view

Purpose: play from the score. Everything here defers to the paper.

**The spread.** Two 512 × 782 pages centered with a 2px gutter, in a container
padded `26px 30px`. Each page: `plate` fill, `1px line` border,
`padding:26px 22px`. The left page's right border is removed and its radius is
`4px 0 0 4px`; the right page is `0 4px 4px 0`. They read as one sheet folded
at the gutter.

Left page carries the work title (serif 15px, centered, y≈44) and an italic
serif 12px mark at the top-left reading `"<catalogue> · p. <n>"`; the right page
carries only `"p. <n>"`. Pages are numbered 1-based; spread *n* shows pages
`2n-1` and `2n`.

**Turn animation.** On turn, the spread container translates 26px against the
direction of travel and drops to 0.35 opacity over 220ms
`cubic-bezier(.4,0,.2,1)`; the new spread swaps in at ~220ms and settles back.
Deliberately restrained — no page-curl skeuomorphism.

**Tap zones** — three invisible full-height buttons, drawn above the spread:
- left 170px → previous spread
- right 170px → next spread
- everything between → toggle chrome

Clamp at spread 1 and `ceil(pages/2)`. Turns must also be driven by a
Bluetooth pedal (see Tools) and should accept swipe.

**The seam — the carried-over system.** ★ The signature interaction.

On a **forward** turn only, a strip appears pinned inside the spread area:
`left:30px; right:30px`, `top:72px` when chrome is visible and `top:14px` when
it is hidden, `z-index:5`. `plate` fill, `1px accent` border, `radius:12px`,
`padding:8px 18px 10px`, horizontal flex, 16px gap, centered, entering with
`rs-fade`.

Contents: a 9.5px/600 uppercase `accent` label "Carried over" · a 34px-tall
clipped render of **the final system of the page just left** · a mono 10px
`faint` page reference (`"p. <n>"`) on the right.

It self-dismisses after the hold duration (default 4s, user-configurable
0–10s in Tools; 0 disables). It never appears on a backward turn. In
production the strip is a cropped raster of the real last system — the crop
comes from staff-line detection on the outgoing page, so this requires system
segmentation at import time, not at turn time.

**Annotation rail.** Shown when Markup is on. Floating panel at `left:16px`,
vertically centered, `rail` fill, `radius:16px`, `padding:10px 8px`, column
flex, 6px gap, entering with `rs-fade` 160ms.

Five tools, each 44×44, `radius:11px`, 19px icon: Pencil, Fountain pen,
Highlighter, Text, Erase. Active: `#FFFDF8` on `rgba(255,255,255,.13)`;
inactive `railfaint` on transparent.

Below a 28px `rgba(255,255,255,.14)` divider (4px margin): four 26px round ink
swatches — red pencil `#B33F26`, blue `#2B3E5E`, green `#2D6A3F`, white chalk
`#EDE9E1`. Selected swatch gets a double ring:
`0 0 0 2px var(--rail), 0 0 0 4px #FFFDF8`.

Annotation is **non-modal**: the rail appears, the score stays live, page turns
keep working, and there is no "done" button. Strokes must be vector, per-page,
per-part, and survive re-import of a new edition where possible.

**Top chrome.** `padding:14px 20px`, horizontal flex, 16px gap, over a
`linear-gradient(to bottom, paper 55%, transparent)` scrim so it reads on
paper without a hard edge. Enters with `rs-fade` 160ms.
- "← Library" back button, 12.5px `muted`, `padding:6px 10px`, `radius:8px`,
  hover → `ink`.
- Title block, flex 1: serif 17px "composer — title", ellipsis-truncated; below
  it 11px `muted` "catalogue · edition · part".
- "Markup" toggle: 8px pencil icon + label, `padding:8px 14px`,
  `radius:999px`. On → `ink`/`paper`; off → `muted` text, `1px line2` border.
- Metronome toggle, same pill treatment, labelled `"♩ = <bpm>"` — the current
  tempo is always legible from the reading view.

**Bottom chrome.** `padding:16px 20px 14px` over a
`linear-gradient(to top, paper 62%, transparent)` scrim.

A centered row of one 34 × 46 thumbnail per page, 7px gap, `radius:3px`,
bottom-aligned. Current pages: `accent` fill, full opacity, **52px tall** (they
grow out of the row) with their mono 9px number visible 15px below in `accent`.
Other pages: `line2` fill at 0.55 opacity, number transparent. Tapping jumps to
that page's spread and clears the seam. In production these are real page
rasters, not solid fills — keep the height-and-number emphasis for the current
spread.

Below, 24px down, centered 11px `faint` hint: "Tap the edges to turn · tap the
centre to hide everything." Dismissable via a preference (`showHints`); hide it
permanently once the user has turned a page a few times.

**Metronome sheet.** Opens from the top-chrome tempo pill: `right:20px`,
`top:66px`, 268px wide, `rail` fill, `radius:16px`, `padding:18px`, entering
with `rs-rise`.
- Header row: 9.5px/600 uppercase `railfaint` "Metronome" and a 15px close ✕.
- Baseline row: mono 44px/500 BPM in `#FFFDF8`, 11px `railfaint` "BPM"
  (`letter-spacing:.1em`), spacer, serif italic 15px `railfaint` tempo word.
- Four beat lamps: equal-width 5px bars, `radius:3px`, 7px gap. Beat 1 is
  `accent` at 0.45 opacity resting, full opacity when it fires; beats 2–4 are
  `rgba(255,255,255,.22)` resting, `#FFFDF8` when they fire.
  `transition: opacity 60ms linear, background 60ms linear`.
- A 30–220 range slider, `accent-color:#B33F26`.
- Start/Stop (flex 1, `padding:11px`, `radius:10px`, 13px/500 — resting
  `#FFFDF8`/`#16151A`, running `accent`/`#FFFDF8`) and "Tap"
  (`padding:11px 16px`, `1px rgba(255,255,255,.18)` border, `railink` text,
  `white-space:nowrap`).
- Footer above a `1px rgba(255,255,255,.1)` rule: 11.5px `railfaint` copy with
  the mono marking inline —
  "Marked ♩= 88–96 in this edition. Your last three run-throughs sat at 91."
  This is the editorial move: the metronome knows what the edition asks for and
  what the player actually does.

Tempo words by BPM: <60 largo · <76 adagio · <96 andante · <112 moderato ·
<140 allegro · else presto (serif italic, lowercase).

Tap tempo: keep taps from the last 2600ms, average the intervals, set
`round(60000/avg)` clamped to 30–220.

### 3. Find — search & import

Purpose: one field that reaches the shelf, public archives, and the inside of
scores.

Single 760px-max column, standard screen padding. Eyebrow "Find & import",
`h1` "Search everything" (20px bottom margin).

**Input**: full width, 52px tall, `padding:0 18px`, `radius:12px`,
`1px line2`, `plate` fill, sans 15px, no focus outline ring — border → `accent`
on focus. Placeholder: "composer, catalogue number, or a landmark you remember".

**Scope chips** 12px below, 8px gap, wrapping: "My shelf" (active), "IMSLP",
"Publishers", "Parts I don't own". Same pill spec as the library sorts at
`padding:6px 13px`, 11.5px.

**Results** 34px below, a 2px-gap column. Row: `padding:15px 14px`,
`radius:10px`, `border-bottom:1px line`, horizontal flex, 18px gap, centered;
hover fills `wash`.
- Kind tag, `flex:none`, 9.5px/600 uppercase `letter-spacing:.1em`,
  `padding:4px 9px`, `radius:999px`. Three kinds:
  `shelf` → `wash` fill, `muted` text · `imslp` → `rgba(43,62,94,.1)`, `blue`
  text · `landmark` → `rgba(179,63,38,.1)`, `accent` text.
- Middle: serif 16px title, 11.5px `muted` sub-line 3px below.
- Right: mono 10.5px `faint` tail (catalogue no., measure range, or file size).

Seed results:
1. `shelf` — Cello Suite no. 1 in G major / "Bach · Bärenreiter · your markings
   from 3 Mar" / BWV 1007
2. `landmark` — "Prélude — the bariolage at m. 31" / "Landmark in your shelf ·
   flagged bow control" / m. 31–42
3. `imslp` — "Cello Suites — Alfredo Piatti edition, 1898" / "IMSLP · public
   domain · 2 volumes" / PDF 8.1 MB
4. `shelf` — Cello Concerto in B minor / "Dvořák · Henle · piano reduction
   attached" / Op. 104
5. `imslp` — "Six Suites a Violoncello Solo senza Basso" /
   "Bach-Gesellschaft Ausgabe, 1879 · facsimile" / PDF 22 MB

The `landmark` kind is the point of this screen: search reaches **inside** the
score — measure numbers, rehearsal marks, and the user's own flags — not just
titles. Build the index over annotations and measure positions from day one.

**Import panel**, 38px below: `1px dashed line2`, `radius:14px`,
`padding:26px`, horizontal flex, 22px gap. Left: serif 19px "Bring in a PDF"
and 12.5px `muted` copy —
"Drop a file and Virtu reads the title page, splits parts, detects repeats
and D.C. jumps, and proposes a page layout. You confirm; nothing is filed
silently."
Right: "Choose file" button, `padding:11px 20px`, `radius:10px`, `ink`/`paper`,
13px/500. Must also accept drag-and-drop onto the whole panel. The last
sentence is a product promise — import always ends in a confirmation step.

### 4. Tools — "On the stand"

Purpose: the things a stand holds besides music.

Eyebrow "Tools", `h1` "On the stand" (26px bottom margin), then a
**`1.15fr 1fr` two-column grid**, 20px gap, max-width 900px.

**Left — Metronome card.** `plate`, `1px line`, `radius:14px`, `padding:24px`.
Panel label "Metronome" (16px below), baseline row of mono 60px BPM + serif
italic 18px `muted` tempo word, four 6px beat lamps (light-mode variant: beat 1
`accent`, others `line2` resting / `ink` firing), the same 30–220 slider, then a
row 18px below: Start/Stop (flex 1, `padding:12px`, 13.5px/500, `ink`/`paper`
resting, `accent`/`#FFFDF8` running) and "Tap tempo" (`padding:12px 20px`,
`1px line2`, `ink` text). Both `white-space:nowrap`; the row must not wrap.

**Right column** — two stacked cards, 20px gap, same card spec.

*Tuning*: label "Tuning"; baseline row of serif 40px "A" (`line-height:1`) and
mono 13px `muted` "442 Hz"; then four equal preset buttons in a 6px-gap row —
"A 442" (active), "A 440", "A 432", "A 415" — `padding:9px 0`, `radius:8px`,
mono 12px; active `ink`/`paper`, inactive `muted` on `wash`. A415 is for
baroque players; keep it.

*Page turns*: label "Page turns"; three preference rows in a 12px-gap column.
Each row: a 38 × 22 toggle track (`radius:999px`, `accent` on / `line2` off,
`150ms ease-out`) with a 16px `#FFFDF8` knob at `top:3px` travelling
`left:3px → 19px` in `150ms cubic-bezier(.4,0,.2,1)`; then 14px gap; then
13.5px `ink` label with an 11.5px `muted` hint 2px below.

| Label | Hint | Default |
|---|---|---|
| Carry the last system over | "The system you just left stays visible for four seconds" | on |
| Half-page turns | "Advance one page at a time inside a spread" | off |
| Bluetooth pedal | "AirTurn PEDpro · connected" | on |

---

## Interactions & behavior

- **Navigation**: rail switches destination and always restores chrome
  (`chrome: true`). Entering a piece from any surface goes to the reading view
  at spread 2. "← Library" returns without losing reading position.
- **Turning**: `turn(±1)` clamps to `[1, ceil(pages/2)]`, no-ops at the bounds,
  runs the 220ms translate-and-fade, swaps the spread, and — forward only —
  raises the seam and schedules its dismissal at `seamHold + 200ms`.
- **Thumbnail jump**: sets the spread containing that page and clears the seam
  immediately (you navigated deliberately; nothing was carried).
- **Chrome**: centre-tap toggles top chrome, bottom chrome, and the hint
  together. The seam's `top` re-anchors between 72px and 14px accordingly. The
  annotation rail and metronome sheet are **not** affected by chrome hiding —
  hiding chrome must never cancel a running metronome or drop the pen.
- **Markup toggle** shows/hides the rail only; tool and ink selection persist
  across sessions.
- **Metronome** runs on a `setInterval` of `60000/bpm` in the prototype;
  production must use a sample-accurate audio clock (`AVAudioEngine` /
  WebAudio), not a timer, and must keep running when the app is backgrounded or
  the screen dims. Changing BPM restarts the interval and resets to beat 1.
- **Stage mode** swaps the token set globally; instant, no transition.
- **Empty and error states are not designed.** See Open questions.

## State

| State | Type | Notes |
|---|---|---|
| `dark` | bool | stage mode |
| `view` | `library \| read \| search \| tools` | destination |
| `piece` | Work | currently open |
| `spread` | int | 1-based, clamped to `ceil(pages/2)` |
| `chrome` | bool | top + bottom chrome + hint |
| `annotating` | bool | annotation rail shown |
| `tool` | `pencil \| ink \| hi \| text \| erase` | persists |
| `color` | hex | selected ink; persists |
| `metronome` | bool | sheet open |
| `running` | bool | metronome running |
| `bpm` | int 30–220 | persists per piece in production |
| `beat` | 0–3 | current beat lamp |
| `turning` | `-1 \| 1 \| null` | drives the turn transform |
| `seam` | bool | carried-over strip visible |
| `q` | string | search query |

Preferences (persisted, surfaced in Tools): `seamHold` seconds (0–10, default
4), `halfPageTurns`, `bluetoothPedal`, `showHints`, `tuningPreset`.

Production data needs: a work store (composer, title, catalogue, edition, part
list, page count, last opened, study progress), per-page annotation layers,
programmes/setlists, a searchable index of measures + rehearsal marks +
annotations, and per-page system-boundary geometry for the seam.

## Assets

No bitmap assets. Everything is CSS, procedurally generated SVG, or line icons
drawn inline at a 24 viewbox with 1.6px round-capped strokes — substitute your
codebase's icon set at the same weight rather than porting the paths.

Fonts are Google Fonts: **Newsreader**, **Archivo**, **JetBrains Mono**. All
three are open-licensed (OFL) and safe to bundle in an app.

The score notation is placeholder. Real pages come from PDF rendering
(PDFKit on Apple platforms, PDF.js on web).

## Files

- `Virtu.dc.html` — the full interactive design reference (all five surfaces,
  both palettes)
- `support.js` — runtime the reference needs to open; not part of the design

## Open questions for the team

1. **Portrait** is undesigned. Single page, or a scrolling continuous view?
2. **Sync and storage** — where do scores and annotation layers live, and what
   happens offline on stage (must be: everything works)?
3. **Setlists** beyond the single "next performance" panel — reorder, per-piece
   notes, timings?
4. **Half-page turns** are a preference but the layout for a mid-spread
   position isn't drawn.
5. **Multi-part works** (the Dvořák has a piano reduction attached) need a
   part-switcher that isn't yet designed.
