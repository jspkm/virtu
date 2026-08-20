# Virtu: A Performer's Product Vision

*Written from ten years of forScore on stage, plus Newzik, Piascore, Notability, and GoodNotes in the practice room. I have had an iPad die mid-Brahms, a Bluetooth pedal drop pairing in a pit, and a toolbar open itself during a quartet concert because my sleeve grazed the screen. Everything below follows from those scars.*

---

## 1. forScore: what to steal, what to fix, what to drop

forScore won because it is *reliable at the stand*. Ten years, thousands of services, and it has crashed on me maybe three times. That is the bar. Everything else is negotiable.

**Keep (steal shamelessly):**

- **The half-page turn.** This is forScore's single most underrated feature and non-negotiable for Virtu. In portrait, the top half of the *next* page slides over the top half of the current page, so I read the bottom of page 4 while the top of page 5 is already visible. It solves the fundamental problem of a one-screen device: paper gives you a two-page eyeful, a tablet doesn't. Any reader without this loses every violinist with a fast passage at a page break.
- **Pedal support done right.** forScore treats AirTurn/PageFlip as first-class: works everywhere, configurable actions, and — critically — *keeps working when Bluetooth hiccups* because tap zones are always live as a fallback. Redundant page-turn paths are a safety system, not a feature.
- **Cropping and margin adjustment.** IMSLP scans have an inch of dead margin. Cropping per-page to maximize staff size is the difference between readable and squinting at a stand two meters from a dim pit light. Do this at import, per part, persistently.
- **Links/buttons for repeats and jumps.** D.S. al Coda in a pit book means jumping backward 6 pages instantly. forScore's tap-a-dot-to-jump links are clunky to author but essential to have. Virtu should make authoring them fast (tap source, tap destination, done).
- **Setlists as ordered playlists over the library.** The model is right: a setlist references pieces, doesn't copy them. Keep the model, fix the UI (see §4).
- **Half-dark stage behavior.** forScore dims and warms the display and kills chrome. Keep, but go further (§3).

**Fix:**

- **The toolbar.** forScore's top bar is an airplane cockpit: 12+ icons, submenus, and the whole thing appears on a *single center tap* — the same gesture space as page navigation. I have opened the metronome during a performance. The chrome must be modal, not ambient (§3).
- **Annotation.** Serviceable, not good. Entering annotation mode is a mode-switch with a visible latency hitch; the eraser is imprecise; there's no proper lasso reposition; the stamp workflow is slow enough that half the players I know just write everything freehand badly. §2 and §5 cover the fix.
- **Metadata.** forScore's composer/genre/tags fields exist but the library still *feels* like a file browser with a score dropped in. Nobody I play with maintains forScore metadata; they maintain filenames like `Brahms2_vc_bärenreiter_FIXED2.pdf`. That's a design failure, not user laziness (§4).

**Drop (for now, some forever):**

- **Metronome, tuner, pitch pipe, piano keyboard.** Heretical, but: every pro has a dedicated tuner app or a physical one, and forScore's versions are the definition of toolbar clutter. Not needed to win a switcher; consider a *practice-mode-only* metronome much later.
- **Reflow, face-gesture page turns, audio/video sync, MIDI.** Nobody I've shared a stand with in a decade uses these on stage. Face gestures misfire; reflow mangles engraving.
- **The 90% of the stamp library nobody touches.** §5.
- **Hot corners.** Invisible, undiscoverable, and occasionally triggered by accident. Explicit beats hidden.

---

## 2. What Notability and GoodNotes know about ink that forScore doesn't

I keep a practice journal in Notability and teach from GoodNotes, and every time I switch back to forScore's annotation mode it feels like writing with gloves on. The gap, concretely:

- **Latency and pencil feel.** Notability/GoodNotes ink lands where the tip is, with pressure-sensitive line weight. Writing a fingering feels like writing. forScore's ink feels laggy and dead. Virtu is on PencilKit — you get Apple's low-latency prediction pipeline for free. *Do not build a custom ink renderer.* This is the whole reason to be Pencil-only: no palm-rejection compromises, no finger-drawing code paths, ink that feels like Apple's own.
- **Stroke eraser as default.** When I erase a fingering, I want the *whole "3" gone in one swipe*, not a pixel-scrubbed smear. GoodNotes' stroke-erase is correct for scores; offer pixel-erase as the alternate for trimming a long slur or crescendo hairpin. Virtu's append-only stroke journal makes stroke-erase natural — an erase is just a tombstone entry. Bonus: "erase only my highlighter" scoping, which GoodNotes has and which is perfect for clearing practice highlights while keeping bowings.
- **Lasso that moves ink.** Marks land in the wrong spot constantly — a cue written a system too low, fingerings that collide with a dynamic. Lasso-select, drag to reposition, done. forScore effectively can't do this; it's the #1 reason my colleagues' parts look like chicken scratch. Resize matters less; move matters enormously.
- **Undo ergonomics.** Two-finger tap to undo (system PencilKit gesture), plus Pencil double-tap configurable to toggle current-tool/eraser. Undo must be deep (the journal gives you this for free) and *instant*. Notability's scribble-to-erase gesture is also worth adopting — scratch out a mark and it vanishes.
- **Zoom-to-annotate.** The killer. A fingering is 3mm tall on the page. GoodNotes' zoom window (write big in a magnified strip, ink lands small on the page) is exactly how you write legible fingerings, and forScore has nothing comparable. For Virtu: press-and-hold or pinch into a magnified region, annotate at 300%, marks commit at true scale. This single feature makes Virtu-annotated parts *look better than paper*.
- **Layers — but musician-flavored.** Neither Notability nor GoodNotes has true layers, and I miss them in both. Scores have a natural layer structure: **my markings** vs. **the librarian's/section's markings** vs. **this-program-only markings** (cuts, cue changes for a specific gig). Three named layers with visibility toggles and per-layer export. This is a genuine differentiator — orchestral librarians will evangelize the app that lets them distribute a bowed part whose bowings players can't accidentally erase.

Translation to score marking: fingerings and bowings are *small, precise, dense*; dynamics circles and eyeglasses are *fast, gestural*; cuts are *structural* (they change navigation, not just appearance — §5). The ink system must serve all three speeds.

---

## 3. The two modes: Stage and Study

This is the product's spine, and the founder's instinct is right. forScore's original sin is that it has one mode with everything reachable from everywhere. Virtu should have two modes with a hard wall between them.

**Stage mode** is where the app lives 90% of its life. What exists in Stage:

- The page. Nothing else. No status bar, no chrome, no tool rail, no battery indicator overlay from the app (iOS's own is fine).
- Tap zones: left = back, right = forward. **Center tap does nothing in Stage mode.** This is the crucial break from forScore. Center-tap-for-chrome is how tools appear mid-performance. Kill it.
- Pedal input, always live, in parallel with tap zones.
- Half-page turn mode (portrait) as a per-piece setting.
- Authored jump links (repeats, D.S., cuts) — tappable, visually near-invisible (a faint dot, not a blue button).
- Annotations render, obviously — flattened, non-interactive. The Pencil in Stage mode does *nothing*. Touching ink cannot select it. There is no eraser to invoke. This is what "markup tools must never appear" really means: not hidden, *nonexistent* in this mode.
- Stage-dark: true-black background (OLED pit-friendly), score inverted or warm-dimmed per user choice, and — from bitter experience — **screen auto-lock disabled and brightness pinned**. Nothing is worse than the screen sleeping during a 40-bar rest.

"Distraction-free at a stand in a dark pit" means: no animation I didn't cause, no popover ever, no red badge, no update prompt, no accidental mode change from a sleeve or a bow tip grazing the glass. The failure mode isn't ugliness — it's a conductor watching me stab at my iPad during a fermata.

**Study mode** gets everything else: the tool rail, layers, lasso, zoom-annotate, stamps, cropping, link authoring, metadata editing, half-page-turn configuration. Study can be visually rich; it's a desk activity.

**Switching:** explicit, one action, symmetric, and impossible to trigger accidentally. My proposal: a persistent but tiny mode chip in one corner in Study mode; entering Stage is one tap on it (or a two-finger double-tap anywhere). *Leaving* Stage requires slightly more intention — press-and-hold the corner chip for half a second, or the same two-finger double-tap. A brief full-screen flash ("STAGE") on entry so you always know which world you're in. What you must never do: make the switch a buried settings toggle (too slow between rehearsal run-throughs, where I flip modes twenty times a night) or a single ambiguous tap (accidents).

**Page turns per mode:** Stage = tap zones + pedal + half-page; Study = those plus scrubber/thumbnail strip for jumping around while woodshedding. Auto-scroll: don't build it yet. It's a practice-room toy for étude grinding; no chamber musician uses it in performance because live tempo isn't metronomic. Ship it in Study mode someday, never in Stage.

And the founder's portrait complaint is simply correct: portrait = single page, always. Two-up belongs to landscape only. A squeezed spread in portrait is unreadable at arm's length and would sink the app in any side-by-side with forScore.

---

## 4. The musician's mental model: repertoire, not files

Ask a working musician what they're playing and they say: "Brahms 2, the Ravel quartet, and that pops program in December." They think in **works**, scheduled into **programs**, played with **ensembles**, across a **season**. Nobody thinks in PDFs.

The hierarchy Virtu already has — work → parts — is right. Complete it:

- **Work**: composer, title, catalog number, movements (with page anchors so "go to mvt. III" is one tap), key, approximate duration, edition/publisher. Composer and work title are the identity; edition matters because bowings live in editions ("the Bärenreiter" vs. "the old Peters" is a real distinction that causes real rehearsal chaos).
- **Part**: the PDF + its annotation layers. One work, many parts (Violin I, Viola, score). I'm usually a cello-part person, but as section leader I mark from the score and transfer — so switching parts within a work must be trivial.
- **Program** (rename "setlist" — classical players say program): an ordered list of works for a concert, with a date and ensemble attached. Programs are the primary navigation surface on a gig day: open the program, hit Stage mode, and page turns flow *across pieces* — last page of the Haydn turns into first page of the Webern with no trip back to any library screen. forScore does this; it's essential.
- **Season/Archive**: programs age out. Last season's twelve programs shouldn't clutter this week's view, but "what bowings did we use for Beethoven 5 in 2024?" must be answerable. A simple date-sorted archive suffices — no new ontology needed.

What "library" should feel like: opening a well-kept physical music cabinet, not a Downloads folder. Default view is *works grouped by composer*, with "current programs" pinned on top. Import flow matters most: when a PDF lands, ask three questions (composer, work, which part is this?) with aggressive autocomplete off the filename, and the file-ness disappears forever. forScore's failure is that metadata is optional homework; Virtu should make it a ten-second import ritual that pays off every day after.

---

## 5. Annotation semantics: what musicians actually write

Sit behind any professional string section and catalog the marks. In rough frequency order:

1. **Fingerings** (digits 1–4, 0, thumb) — string players, constantly
2. **Bowings** (down-bow ⊓, up-bow ∨) — the most-negotiated marks in orchestral life
3. **Circles** around dynamics, accidentals, key changes — "I missed this once, never again"
4. **Eyeglasses** ("watch the conductor/concertmaster HERE")
5. **Breath marks / commas** (winds, and phrasing for everyone)
6. **Cuts and vide** — brackets, slashes, "V—— —I", whole passages crossed out
7. **Measure numbers / rehearsal letters** written into scans that lack them
8. **Cues from other parts** — a few notes of the oboe line penciled above your rest so you know when to come in
9. Caesuras, courtesy accidentals, "listen," arrows for tempo (push/pull)

**First-class treatment** (structural, not just ink): **Cuts.** A cut is navigation data — in Stage mode the page turn should *skip the cut* or the vide-jump should be a tappable link, auto-authored when you mark the cut in Study mode. This is where Virtu can leap past forScore, where cuts are just drawings plus manually-built links. Also first-class: **rehearsal-mark anchors** ("jump to letter K" during rehearsal is worth gold — conductor says "K," everyone's there in one tap while the paper players are still flipping).

**Stamps, ruthlessly curated:** forScore ships ~100 stamps; the ones that get 95% of real use are about twelve: down-bow, up-bow, eyeglasses, breath comma, fermata, accent, the dynamics (pp p mp mf f ff), a circle, and numerals 0–4 for fingerings. Ship *one row* of these, one tap to select, tap-to-place, drag to nudge, sized sensibly by default. Fingerings deserve a dedicated micro-mode: pick "fingering," then each tap places a number from a tiny 0–4 picker at the pencil tip — faster than writing and always legible. Everything else — the long tail of ornaments and clefs — is freehand ink, which with good zoom-annotate (§2) looks better than a stamp library anyway.

Everything remains strokes/objects in the journaling model; "first-class" means the app *understands* certain objects (cuts affect paging, stamps are movable units) rather than inventing a parallel data model.

---

## 6. Roadmap: the shortest path to a switcher

The switcher I know best is me. Here's what would move me, in order:

1. **The mode wall (Stage/Study) + portrait single-page.** Both founder complaints, and they're the identity of the product. Nothing else matters if the app can betray me on stage. Small surface area, huge trust dividend. Ship first.
2. **Half-page turns.** The de facto standard for serious portrait reading. Without it, every fast movement with a bad page break disqualifies Virtu at the audition. With it plus the mode wall, Virtu is already *safer on stage than forScore*.
3. **Bluetooth pedal support.** AirTurn/PageFlip present as BLE keyboards (arrow/page keys) — days of work, and an absolute prerequisite. No pro performs 60 concerts a year on tap zones alone. Tap zones stay live as the fallback layer.
4. **Ink that beats forScore: stroke eraser, lasso-move, zoom-to-annotate, curated stamp row + fingering mode.** This is the "switch and your part gets *better*" pitch, and it's Virtu's Pencil-only thesis cashed in. It's the largest work item here, which is why it's ranked after the stage-trust items — but it's the feature that makes people show their stand partner.
5. **Programs with cross-piece paging + gig-day flow.** Open program → Stage → play the whole concert without touching navigation. This converts Virtu from "a PDF viewer" to "the thing on my stand every night."
6. **Import ritual + composer/work library.** The ten-second metadata capture and works-by-composer browsing from §4. Cheap, and it's what makes 200 PDFs feel like a repertoire instead of a folder.
7. **Cropping/margins + link authoring (repeats, D.S., cuts-as-navigation).** Rounds out real-world scans and pit books. Cuts-as-navigation is the first "only Virtu does this" headline.

**Ruthlessly not yet:** cloud sync (AirDrop the annotated PDF export covers 90% of sharing; sync bugs eat annotations, and eaten annotations end the product — the append-only journal is your integrity story, don't complicate it), OMR/AI anything (zero stage value), audio/recording, metronome/tuner (commodity, clutter), reflow, face gestures, ensemble live-sync à la Newzik (huge surface, tiny early audience), Android/phone (a phone score reader is a toy). Set-and-forget discipline: every feature must justify itself *at the stand, in the dark, in bar 340*. That's the whole product.

---

*One closing test I'd apply to every build: hand the iPad to a violinist five minutes before a run-through of the Schubert Cello Quintet — repeats, fast turns, dim hall — with no explanation. If anything on that screen surprises them before the double bar, it's a bug, whatever the spec says.*
