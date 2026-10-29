# Mendlet — Redesign Spec (build-ready)

Author: UX lead pass, 2026-10-29. Replaces the visual and structural decisions in `docs/design-notes.md` and the v7 screens in `docs/screenshots/`. Builder: SwiftUI, iOS deployment target 17.0, Liquid Glass only through the existing `.glass()` helper.

Reference images live in `docs/design/refs/<screen>/<app>-<n>.jpg` (downloaded from Mobbin, 700 px wide). Every reference below is cited as `path` + Mobbin link. A few images appear under two screens when they serve both. The owner collection (13 screens, Apple Health, Apple Fitness, Journal, Cal AI, HelloFresh, Blue Apron, Centr, Recime, Apple Photos) is `https://mobbin.com/collections/175c3475-f7b6-41b6-af7c-3dc3a68df769`; its screens are used below where relevant.

---

## 0. Diagnosis of the v7 app (why it reads as a hackathon demo)

Looking at `v7-en-home / analysis / diagnosis-real-sweater / decision-replace / shopping / guide-real-sweater`:

1. The home screen is a raw camera feed with two floating glass buttons. There is no home: no projects, no progress, no place to come back to.
2. Every screen is the same three ingredients: system grouped gray, white cards at radius 24, a full-width system-blue capsule. No typographic voice, no rhythm.
3. The photo is wrapped in debug furniture: "Garment 71 %" and "Garment 89 %" pins, "Hole 75 %", filter chips ("All / Garment x2 / Hole"), a circle ring around the damage, a hand icon and a collapse icon on the photo.
4. The diagnosis shows a confidence ring ("75 fairly sure") and "Likely causes" with numbered bubbles. The analysis screen shows an "Agent log" card with a "Muse Spark" badge and a "LIVE" tag. These are model internals, not product.
5. The verdict leads with a gray app-icon tile, then body copy in secondary gray, then three icon cards (Low / 15-45 min / 8-25 EUR). Copy is machine voice: "presumably", "Assumed leather outsole", "Done when hole edges lie flat with no tension" inline.
6. The guide stacks a four-color progress bar, "Step 3 of 5", Share and Close pills, a 4:3 photo with a pin, an H1, a dense paragraph, a yellow warning card and a three-button footer (back chevron, blue Done, "Doesn't help").
7. Shopping is a list of pill pairs ("Have it" / "Buy") with blue "Required" tags and a disabled gray bar.

The redesign keeps every capability and removes everything that exposes the machinery. The marking on the user's own photo stays and becomes the hero.

---

## 1. Design principles

1. **The photo is the hero; chrome steps back.** On Analysis, Finding, Verdict, Guide and Project the user's own photo is the largest element (46 to 62 % of screen height, edge to edge or in a 24 pt card). Everything else is type on a quiet surface. Reference feel: Google Lens result sheet (`refs/analysis/googlelens-1.jpg` ([Mobbin](https://mobbin.com/screens/fce278a0-4a62-4851-b08e-b667289033c1))), Cal AI result (`refs/analysis/calai-1.jpg` ([Mobbin](https://mobbin.com/screens/2db7609c-6b5f-4a75-8813-4045e4300775))), Lovi (`refs/analysis/lovi-1.jpg` ([Mobbin](https://mobbin.com/screens/e6316517-0b99-428f-a07c-93cf5e8be244))).
2. **One accent, used for state only.** Neutral ink and paper do 95 % of the work. The primary button is ink (label color on a capsule), like Cal AI / Perplexity / Rocket Money (`refs/scan/calai-2.jpg` ([Mobbin](https://mobbin.com/screens/dcf735f6-52fd-4181-bf5e-442065642bb4)), `refs/home/empty-perplexity.jpg` ([Mobbin](https://mobbin.com/screens/c6ce53ff-7075-42d9-818e-ba26ad51ebfe)), `refs/project/rocketmoney-1.jpg` ([Mobbin](https://mobbin.com/screens/a5d153d6-fb60-4e2c-a1ab-814d20b19d85))). The single accent is **system blue** (`Color.accentColor` = `.systemBlue`; owner decision: no orange anywhere), used only for progress fill, the current-step node, a checked box and links. No other accent hues, no green success, no yellow cards, no red except destructive actions. Photo markings are always white.
3. **Type carries the hierarchy.** SF Pro (system) for UI and body. New York (`design: .serif`) only for editorial moments: Home title, finding headline, verdict headline, step title, completion line. This is the Julienne / Blue Apron / Noom / Recime pairing (`refs/guide/julienne-1.jpg` ([Mobbin](https://mobbin.com/screens/5ddc1d76-b042-4552-97fb-698b19eb8688)), `refs/guide/blueapron-1.jpg` ([Mobbin](https://mobbin.com/screens/efd46517-8af3-4395-a301-7dfa97375ec2)), `refs/completion/noom-1.jpg` ([Mobbin](https://mobbin.com/screens/04ff3e32-9b8a-4a80-b661-0235f0b65dcb)), `refs/checklist/recime-1.jpg` ([Mobbin](https://mobbin.com/screens/81ed4348-a658-4958-b059-e26ad58ee1e5))). No `.rounded` anywhere (remove `Font.rounded`). Hero numerals use SF Pro semibold with `.monospacedDigit()`. Always text styles (Dynamic Type), never fixed sizes except the two hero numerals.
4. **Restraint rules (how not to look AI-generated).** No gradient blobs, no mesh backgrounds, no sparkle glyphs, no emoji, no glow on UI chrome, no "AI / Muse / SAM / model / confidence / %" strings anywhere in the user path, no drop-shadowed cards (use 0.5 pt hairline separators and fills instead), no more than one filled button per screen, no icon in a colored rounded square. Every screen has one primary action and at most one secondary text action.
5. **8 pt grid, 20 pt margins.** Spacing tokens: 4, 8, 12, 16, 20, 24, 32, 48. Horizontal margin 20. Hero corner radius 28 (continuous). Card radius 20 (continuous), only used on Home project cards and the Verdict facts container. Control height 54 (primary), 44 (secondary, glass circles). Minimum tap target 44.
6. **Editorial copy.** Sentences, not labels. Short, human, confident. Headline 3 to 7 words, one sentence of reason, one sentence of consequence. No hedging ("presumably", "assumed", "likely", "might"), no first-person persona ("I'm taking a close look"), no exclamation marks, no "AI". See section 5.
7. **Motion has a job.** Three motion types only: (a) the **mark reveal** (the signature, section 4), (b) **hero continuity** (the photo morphs between Scan, Analysis, Finding, Verdict via `matchedGeometryEffect`), (c) **state change** (spring `response 0.42, dampingFraction 0.86`). Haptics: soft impact when an outline finishes drawing, selection on checkbox, success on "Done" and completion. Reduce Motion: replace every move/draw with a 0.25 s cross-fade.

### 1.1 Tokens (replace `Theme.swift` contents)

| Token | Value |
| --- | --- |
| `bg` | `Color(.systemGroupedBackground)` (Home, Checklist, Project) |
| `surface` | `Color(.systemBackground)` (sheets on Finding/Verdict/Guide) |
| `card` | `Color(.secondarySystemGroupedBackground)` |
| `ink` | `Color(.label)`, `inkSecondary` `Color(.secondaryLabel)`, `inkTertiary` `Color(.tertiaryLabel)` |
| `hairline` | `Color(.separator)` at 0.5 pt |
| `fill` | `Color(.tertiarySystemFill)` |
| `accent` | `Color.accentColor` = system blue (owner: no orange) |
| `mark` | `Color.white` (all photo overlays) |
| `scrim` | `Color.black.opacity(0.30)` |
| Primary button | capsule, fill `ink`, text `Color(.systemBackground)`, `.headline`, height 54 |
| Secondary action | text button, `.body.weight(.medium)`, `accent` |
| Radii | hero 28, card 20, thumbnail 12, chip none (chips are removed) |
| Springs | `ui` response 0.42 / damping 0.86; `press` response 0.25 / damping 0.7 (scale 0.97) |

Type scale (SwiftUI): Home title `.system(.largeTitle, design: .serif).weight(.semibold)`; headline serif `.system(.title, design: .serif).weight(.semibold)`; step title `.system(.title2, design: .serif).weight(.semibold)`; body `.body` (line spacing +4); secondary `.subheadline` secondaryLabel; overline `.caption.weight(.semibold)` with `.tracking(0.8)` and `.textCase(.uppercase)`, secondaryLabel; hero numeral `.system(size: 56, weight: .semibold).monospacedDigit()`; fact value `.title3.weight(.semibold).monospacedDigit()`; mark label `.footnote.weight(.semibold)`.

---

## 2. Information architecture and flow

```
                        ┌──────────────────────────────────────────────┐
                        │ HOME  "Repairs"                              │
                        │  In progress | Done   (underline tabs)       │
                        │  project cards -> PROJECT                    │
                        │  floating "Scan" capsule -> SCAN             │
                        │  ... menu -> Settings sheet                  │
                        └───────┬───────────────────────┬──────────────┘
                   tap card     │                       │ Scan
                                ▼                       ▼
                        ┌──────────────┐        ┌────────────────┐
                        │ PROJECT      │        │ SCAN (cover)   │  gallery / note / live / torch
                        │ what you need│        └──────┬─────────┘
                        │ steps        │               │ shutter
                        │ Continue ────┼──┐            ▼
                        └──────┬───────┘  │     ┌────────────────┐   follow-up questions (sheet)
                               │ items    │     │ ANALYSIS       │◄──────────────┐
                               ▼          │     │ mark reveal    │               │
                        ┌──────────────┐  │     └──────┬─────────┘               │
                        │ BEFORE YOU   │  │            │ safety gate: blocked ──► BLOCK -> Home
                        │ START        │  │            ▼ (FlowGate unchanged)
                        │ checklist    │  │     ┌────────────────┐
                        └──────┬───────┘  │     │ FINDING        │  "Not right?" -> tap to refine
                               │ Start    │     │ hero + diagnosis│
                               ▼          │     └──────┬─────────┘
                        ┌──────────────┐  │            ▼
                        │ GUIDE        │◄─┘     ┌────────────────┐ replace: second life, Done -> Home
                        │ step player  │        │ VERDICT        │ pro: Save, Done -> Home
                        └──────┬───────┘        │ hero + advice  │ repair: "Start repair" saves the
                               │ last step      └──────┬─────────┘  PROJECT then -> BEFORE YOU START
                               ▼                       │
                        ┌──────────────┐               ▼
                        │ COMPLETION   │        (project exists from Verdict on)
                        │ before/after │
                        └──────┬───────┘
                               ▼ Done
                              HOME (project moves to "Done")
```

Rules:
- Home is the root. The camera is no longer the root. Scan is a full-screen cover presented from Home; closing it returns to Home.
- A project is created when the user taps **Start repair** on the Verdict (existing `CaseStore.upsert`). Leaving at any later point (close button, swipe back, app kill) keeps the project; `SavedCase` already holds `shoppingStatus`, `currentStep`, `completedSteps`, `finished`.
- "In progress" on Home = `finished == false`. "Done" = `finished == true`.
- Replace/Pro verdicts do not create a project. They end with **Done** (Home) and the scan stays in History (the existing `store.cases` list; History becomes the "Done" tab only for finished repairs, see Home states).
- Routes: keep the existing `FlowModel.Route` cases (`analysis, diagnosis, decision, shopping, guide, block, completion`) so `-uiScreen` keeps working. Add `project` (carries a case id). UI names: `diagnosis` = "Finding", `decision` = "Verdict", `shopping` = "Before you start".
- No tab bar. Settings via the ellipsis menu on Home.

---

## 3. Screens

Conventions in the wireframes: `[ ]` button, `( )` glass circle, `▓` photo, `░` scrim, `━` progress. 393 pt wide canvas.

### 3.1 Home ("Repairs")

**Purpose.** Show the user's projects, what is still needed, and the single way to start a new scan.

**References and what to borrow**
- `refs/home/journal-1.jpg` ([Mobbin](https://mobbin.com/screens/bf356291-cee2-4cbf-9ea4-79be184ab05a)): large title, grouped cards on a pale ground, floating round action bottom-right. Borrow the title scale and the card rhythm.
- `refs/home/things-2.jpg` ([Mobbin](https://mobbin.com/screens/724087de-2e95-47ec-926c-efbdab249a23)): row anatomy "title + muted project line", no card chrome, hairlines. Borrow for the Done list.
- `refs/home/angi-1.jpg` ([Mobbin](https://mobbin.com/screens/fb2b64b1-011a-471e-bea5-092c1a9348cc)): underline segment "In progress | Done" and project card with chevron. Borrow the tab idiom.
- `refs/home/hims-1.jpg` ([Mobbin](https://mobbin.com/screens/338ce5a5-d309-4aca-bc4b-b1c12131a7d0)): card with named progress stages and a single status sentence. Borrow the segmented progress line.
- `refs/home/flighty-1.jpg` ([Mobbin](https://mobbin.com/screens/939d5aae-4c27-4a32-b91c-767ee82a1845)) and `refs/home/structured-1.jpg` ([Mobbin](https://mobbin.com/screens/574482d9-3640-4553-805e-944f11f27428)): bottom surface over a hero, big left-aligned figure column, floating glass control. Borrow the glass floating control.
- `refs/home/empty-perplexity.jpg` ([Mobbin](https://mobbin.com/screens/c6ce53ff-7075-42d9-818e-ba26ad51ebfe)), `refs/home/empty-angi.jpg` ([Mobbin](https://mobbin.com/screens/3ebf8f26-3f08-4e68-ba7e-2beca00d9e70)), `refs/home/empty-claude.jpg` ([Mobbin](https://mobbin.com/screens/95d84616-c65e-4722-9042-46764480514f)): empty state is one sentence and one button. Borrow exactly that.
- `refs/home/opal-1.jpg` ([Mobbin](https://mobbin.com/screens/a255c56f-2d49-4ce5-86d4-58e929052ab4)): image-led rounded tiles. Borrow the idea of the photo as the card face.
- `refs/home/copilot-1.jpg` ([Mobbin](https://mobbin.com/screens/b9f87d05-1926-4b80-97c8-964ed8335b7f)): small caps overlines with trailing action. Borrow the overline pattern.

**Layout (in progress, 2 projects)**
```
┌───────────────────────────────┐
│ 9:41                      (···)│  nav bar, trailing menu
│ Repairs                        │  largeTitle serif
│ In progress    Done            │  underline tabs, 44 pt
│ ━━━━━━━━━━                     │
│ ┌───────────────────────────┐ │
│ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ │  photo 16:10, own photo, radius 20 top
│ │▓▓▓▓▓ ○ outline ▓▓▓▓▓▓▓▓▓▓▓│ │  damage outline drawn static (no label)
│ │                           │ │
│ │ Grey knit sweater         │ │  .headline
│ │ Darn the hole             │ │  .subheadline secondary
│ │ ━━━━━━━━━▒▒▒▒▒▒           │ │  5 segments, 3 pt, 3 filled accent
│ │ Step 3 of 5               │ │  .footnote secondary
│ │ Still needed: darning     │ │  .subheadline, only if something is missing
│ │ needle, grey yarn         │ │
│ └───────────────────────────┘ │
│ ┌───────────────────────────┐ │
│ │ ▓thumb  Leather shoe  >   │ │  second card (same component)
│ └───────────────────────────┘ │
│                               │
│          ┌──────────┐         │
│          │ ◉  Scan  │         │  floating glass capsule, 56 pt, bottom 24
│          └──────────┘         │
└───────────────────────────────┘
```

**Components**
- `HomeView` (rewrite). `NavigationStack` root, `ScrollView` with `LazyVStack(spacing: 16)`, margin 20. Large title inline-collapsing via `.navigationTitle("Repairs")` with serif font applied through `UINavigationBarAppearance` large title attributes (`UIFont` New York descriptor).
- Toolbar trailing: `Menu` with an ellipsis (`ellipsis`, 44 pt glass circle via `.glass`): "Settings", "Language". No History button.
- Tabs: `ProjectTabs` (two `Text` buttons, `.body.weight(.semibold)`, selected = ink with 2 pt ink underline using `matchedGeometryEffect`; unselected = secondary). Height 44, bottom hairline.
- `ProjectCard` (new): `VStack(alignment: .leading, spacing: 12)`; photo `MarkedPhotoThumb` (the saved image with the damage mask outline drawn at 1.25 pt white, scrim 0.2, aspect 16:10, top corners radius 20 continuous); text block padding 16; `SegmentBar` (see 3.7 for the component; height 3, gap 4, filled = accent, empty = fill); line "Step 3 of 5" `.footnote` secondary; line "Still needed: …" (join of required items whose status is not "have", max 2 names then "+ 2 more") `.subheadline`; whole card is one `Button` with `PressScaleStyle`. Card background `card`, radius 20, no shadow.
- Finished project row (Done tab): `HStack` 56 pt thumbnail radius 12 (after image if available else photo), title `.body.weight(.semibold)`, subtitle "Repaired 28 Oct" `.subheadline` secondary, chevron. Hairline separators inset 88. No cards.
- Floating `ScanButton`: `HStack { Image(systemName: "camera.fill"); Text("Scan") }`, `.headline`, padding 20/16, `.glass(Capsule(), interactive: true)`, centered at bottom, 24 pt above safe area; list gets `.safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }`.

**Typography.** Title serif largeTitle; card title `.headline`; card line 1 `.subheadline` secondary; progress caption `.footnote`.
**Spacing.** Title to tabs 8; tabs to first card 16; card gap 16; card text padding 16; between text lines 4.
**Colors.** `bg` ground, `card` cards, accent for filled segments only.

**States**
- Empty (no cases): no tabs. Centered block: serif `.title` "Nothing to mend yet." / `.body` secondary "Photograph a tear, a loose sole or a broken cable." / primary ink capsule "Scan something" (replaces the floating button). Borrowed from `refs/home/empty-perplexity.jpg` ([Mobbin](https://mobbin.com/screens/c6ce53ff-7075-42d9-818e-ba26ad51ebfe)) and `refs/home/empty-angi.jpg` ([Mobbin](https://mobbin.com/screens/3ebf8f26-3f08-4e68-ba7e-2beca00d9e70)).
- Empty "Done" tab: `.body` secondary centered "Finished repairs show up here."
- Loading: none (store is local).
- Offline: no change on Home. A scan attempt offline shows the error state in 3.4.
- Error: none on Home.

**Motion.** Cards enter with `.opacity + .offset(y: 12)` stagger 0.05 s. New project inserted from Verdict: card scales from 0.96 and the segment bar fills from 0 (0.5 s easeOut). Floating button hides on scroll down (offset 80 pt, `ui` spring) and returns on scroll up.

**Final copy (EN)**
Title: "Repairs". Tabs: "In progress", "Done". Floating: "Scan". Menu: "Settings", "Language". Card line: "Step 3 of 5". Missing line: "Still needed: darning needle, grey yarn" / "Still needed: patch, thread and 2 more". All items ready: "Everything is ready". Not started guide (checklist incomplete, step 0): line 1 "Gathering materials", progress bar empty, caption "2 of 5 items ready". Done row subtitle: "Repaired 28 Oct". Empty: "Nothing to mend yet." / "Photograph a tear, a loose sole or a broken cable." / "Scan something". Done empty: "Finished repairs show up here." Card accessibility label: "<title>, step 3 of 5, still needed darning needle".

**Title of a project** = category noun + damage, derived from the case, never the raw model summary: `"<Garment or item>"` where garment = first noun phrase of `diagnosis.summary`; fallback "Repair". Subtitle = the repair type from the first step overlay (`darning` -> "Darn the hole", `ladder_stitch` -> "Close the seam", glue -> "Reglue the sole", solder -> "Reconnect the wire").

---

### 3.2 Scan

**Purpose.** Camera-first, premium. Make the right photo easy: close-up on the damage, in light.

**References and what to borrow**
- `refs/scan/bitepal-1.jpg` ([Mobbin](https://mobbin.com/screens/6aa57cd2-61ec-4a1d-bda4-32c476090dc2)) (owner reference): bottom control row = gallery thumbnail left, big white ring shutter center, small keyboard button right; a quiet pill above the shutter ("My meals"); two-state mode pill at the top ("Meal | Label"); dark rounded camera sheet. Borrow the control row and the top pill. **We do not use the circular crop or the mascot.**
- `refs/scan/bitepal-2.jpg` ([Mobbin](https://mobbin.com/screens/e904fdb7-bc19-486f-9f99-9bd7b0564e1b)): during capture of the meal, a hairline horizontal scan line sweeps the photo. Borrow for the Analysis mask reveal (section 4).
- `refs/scan/calai-1.jpg` ([Mobbin](https://mobbin.com/screens/1931911e-97bc-4668-8c50-4dc5516e9c02)): four corner brackets, `.5x / 1x` pill above the shutter, mode tiles. Borrow bracket weight and the zoom pill. See `refs/scan/googlelens-2.jpg` ([Mobbin](https://mobbin.com/screens/9e251fac-a08c-461b-bad0-b6d66f27b206)) for the glass mode pill version.
- `refs/scan/greg-1.jpg` ([Mobbin](https://mobbin.com/screens/2641b32c-9c17-4dbd-8472-b2faa345d8a2)): arc corners rather than L brackets, hint pill on the viewfinder ("Try turning on some lights"), vertical glass tool rail. Borrow the arc corners and the hint pill (to contain our hint copy).
- `refs/scan/yuka-1.jpg` ([Mobbin](https://mobbin.com/screens/0809f49a-2a01-465a-b7bb-4d9af26c0ae3)), `refs/scan/googlelens-1.jpg` ([Mobbin](https://mobbin.com/screens/fce278a0-4a62-4851-b08e-b667289033c1)): result sheet slides up over the live camera. Borrow for the capture-to-analysis continuity.
- `refs/scan/phantom-1.jpg` ([Mobbin](https://mobbin.com/screens/b6c3f068-abb6-4a4d-9ed4-f26ae495ca90)), `refs/scan/ubereats-1.jpg` ([Mobbin](https://mobbin.com/screens/e5793787-0398-4f03-8b7a-dc484b2d5a20)): restraint (thin white frame, nothing else). Borrow the thin stroke.
- `refs/scan/locket-1.jpg` ([Mobbin](https://mobbin.com/screens/645891b2-e7c9-4767-9805-974fa3db54ef)): single camera screen with ring shutter and glass pill. Borrow the ring shutter.
- `refs/scan/calai-2.jpg` ([Mobbin](https://mobbin.com/screens/dcf735f6-52fd-4181-bf5e-442065642bb4)): first-run interstitial with a single sentence and one white pill. Borrow for camera permission.

**Layout**
```
┌───────────────────────────────┐
│ (✕)                      (⚡) │  44 pt glass circles, top safe area + 8
│                               │
│   ╭─                   ─╮     │
│                               │  four arc corners, 36 pt long, 3 pt, white .9
│    Fill the frame with       │  hint pill (glass capsule), 14 pt below frame
│    the damage                 │
│   ╰─                   ─╯     │  frame 288 x 288, centered at 44 % of height
│                               │
│        [ Photo | Live ]       │  glass pill, 36 pt, above shutter, 16 pt gap
│ ┌──┐       ◯          (◌)    │
│ │▓▓│     shutter     note     │  gallery 52 pt radius 12 | shutter 76 | note 52
│ └──┘                          │
└───────────────────────────────┘
```
(`◌` = SF Symbol `text.bubble`.)

**Components**
- `ScanView` replaces `InlineCameraCard` as the camera host; `InlineCameraSession`, `LiveScanView`, `CameraPicker` stay. Presented via `.fullScreenCover` from Home. Camera preview edge to edge, `.ignoresSafeArea()`, with a 0.12 black scrim at the top and bottom 160 pt (linear gradient) for control legibility.
- `ViewfinderCorners`: `Shape` drawing four quarter arcs (corner radius 28), `lineWidth 3`, `lineCap .round`, `Color.white.opacity(0.9)`, shadow black 0.25 r2. Idle "breathing" scale 1 to 1.015, 2.4 s easeInOut forever; off under Reduce Motion.
- Hint pill: `Text` `.footnote.weight(.medium)`, `.glass(Capsule())`, padding 14/8.
- Top buttons: `CircleIconButton` 44 pt `.glass`, `xmark` and `bolt.fill`/`bolt.slash`.
- Mode pill: two-segment glass capsule "Photo | Live" (`.glass`, selected segment `Color.white.opacity(0.9)` with black text, the Cal AI pattern). Live opens the existing `LiveScanView`.
- Shutter: 76 pt white filled circle inside a 88 pt 3 pt white ring (BitePal). Press: scale 0.92 `press` spring + light impact.
- Gallery: the latest photo 52 pt radius 12 with 1 pt white .6 border; tap opens `PhotosPicker`.
- Note: `text.bubble` 52 pt glass circle opens a bottom sheet "What's wrong?" with the existing `VoiceTextField` (keeps voice dictation). When a note exists the circle shows a 10 pt white dot at its top-right.

**Typography.** Hint `.footnote.weight(.medium)`; mode pill `.subheadline.weight(.semibold)`.
**Colors.** All white on camera; no accent on camera.

**States**
- Camera permission not determined: black screen, centered white `.title3` "Mendlet needs the camera" / `.subheadline` white .7 "To photograph what you want to repair." / white pill "Continue" (borrowed from `refs/scan/calai-2.jpg` ([Mobbin](https://mobbin.com/screens/dcf735f6-52fd-4181-bf5e-442065642bb4))), then system prompt.
- Denied: same layout, "Camera access is off" / "Turn it on in Settings, or pick a photo instead." / pill "Open Settings", text button "Choose a photo".
- No camera (simulator): preview shows the demo photo; behavior unchanged (existing `demoPhoto`).
- Low light: hint pill changes to "More light helps" (use the Greg pattern; `AVCaptureDevice` ISO or exposure bias heuristic; if not available, skip).
- Offline: banner pill replaces the hint: "No connection. You can still take the photo." Capture works; analysis waits (see 3.4 error).

**Motion.** On shutter: white flash 0.12 s at 0.35 opacity, the frame freezes, the four corners translate outward to the photo's edges (0.35 s `ui`), controls fade out (0.2 s). The frozen photo becomes the Analysis hero via `matchedGeometryEffect(id: "hero")`.

**Final copy.** Hint: "Fill the frame with the damage". Segments: "Photo", "Live". Note sheet title: "What's wrong?" placeholder "Optional, e.g. the sole came off yesterday". Sheet button: "Save note". Gallery accessibility: "Choose a photo". Permission copy above.

---

### 3.3 Analysis (the mark reveal)

**Purpose.** While the diagnosis runs, show the damage being found on the user's own photo. This is the Meta-model showcase; it must feel like a crafted product feature.

**References and what to borrow**
- `refs/analysis/googlelens-1.jpg` ([Mobbin](https://mobbin.com/screens/fce278a0-4a62-4851-b08e-b667289033c1)), `refs/analysis/googlelens-2.jpg` ([Mobbin](https://mobbin.com/screens/40e20d17-0165-48c6-8b82-bf009a264fce)): the region of interest stays bright, the rest of the photo is dimmed, four corner brackets sit on the region edge, the result sheet rises from the bottom with a grabber. Borrow the dimmed-surround and the sheet.
- `refs/analysis/applephotos-1.jpg` ([Mobbin](https://mobbin.com/screens/19627cf0-5ca8-4570-b04a-f383be8596c9)), `refs/analysis/applephotos-2.jpg` ([Mobbin](https://mobbin.com/screens/19627cf0-5ca8-4570-b04a-f383be8596c9)) and `refs/analysis/capwords-1.jpg` ([Mobbin](https://mobbin.com/screens/2058a2fb-c097-4ff5-bfd6-f47fd93e8c4f)): Apple subject lift. The isolated subject gets a thin white contour and a soft separation. Borrow the contour weight and the "lifted" look. In CapWords the label sits beneath the subject in plain type, no chip.
- `refs/analysis/bitepal-2.jpg` ([Mobbin](https://mobbin.com/screens/e904fdb7-bc19-486f-9f99-9bd7b0564e1b)) and `refs/analysis/bitepal-1.jpg` ([Mobbin](https://mobbin.com/screens/11e8327b-d4ee-4cbc-b7a9-44cc33d255ea)): a thin light scan line sweeps the photo while a bottom sheet says what is happening. Borrow the sweep and the single-line status sheet.
- `refs/analysis/calai-1.jpg` ([Mobbin](https://mobbin.com/screens/2db7609c-6b5f-4a75-8813-4045e4300775)): photo top, sheet bottom. Borrow the proportion (photo 62 %).
- `refs/analysis/lovi-1.jpg` ([Mobbin](https://mobbin.com/screens/e6316517-0b99-428f-a07c-93cf5e8be244)): sheet over a dimmed photo with a one-line finding. Borrow the sheet style.
- `refs/analysis/starlink-1.jpg` ([Mobbin](https://mobbin.com/screens/a446c6a5-c04d-40b9-82db-a5e3b865074b)): single large white circular action on a dark ground. Borrow for the "Continue" arrival (not used as chrome).

**Layout**
```
┌───────────────────────────────┐
│ (✕)                           │  glass circle top-left
│▓▓▓░░░░░░░░░░░░░░░░░░░░░░▓▓▓▓▓│
│▓▓░░░░░╭──────╮░░░░░░░░░░░░▓▓▓│  scrim 0.30 everywhere except the mask
│▓▓░░░░░│ mask │░░░ Hole      ▓▓│  mask interior unscrimmed + white .12 fill
│▓▓░░░░░╰──────╯────·          │  outline 1.5 pt, label with leader
│▓▓▓░░░░░░░░░░░░░░░░░░░░░░░▓▓▓▓│  62 % height photo, edge to edge
├───────────────────────────────┤  sheet radius 28, surface
│            ───                │  grabber (decorative)
│  Finding the damage           │  .title3 semibold, crossfades per phase
│  ● ● ○ ○                      │  4 dots, 6 pt
└───────────────────────────────┘
```

**Components**
- `AnalysisView` (restyle). Hero = `MarkedPhoto` (section 4) full-bleed with `.ignoresSafeArea(edges: .top)`; the sheet is `AnalysisSheet`, fixed height 168 pt, `surface`, top radius 28.
- Status line: `Text` `.title3.weight(.semibold)`, content from the phase table below, crossfading (`.contentTransition(.opacity)` 0.25 s). Under it `PhaseDots`: 4 circles 6 pt, 8 pt gap, done = ink, current = ink with a pulsing 1 to 0.4 opacity (1.2 s), future = fill. No percentages, no step numbers, no "4 of 4".
- Tap on the status line toggles a detail drawer showing the existing `AgentTraceView` rows (hidden by default; this is where the Wonder agent trace lives so the screenshots script `-recoveryTrace` still renders it). Gesture is invisible to normal users; the drawer is titled "Behind the scenes" `.footnote.weight(.semibold)` secondary.
- Close: `CircleIconButton` 44 pt `.glass` top-left, cancels analysis (existing behavior).

**Phase to copy** (maps to `FlowModel.stageStates` order)
1. "Looking at your photo"
2. "Finding the damage" (mask phase 2 starts when segments arrive)
3. "Outlining it" (the outline draws, section 4)
4. "Writing your plan"

**States**
- Loading: as above.
- Needs more info (existing follow-up): the sheet grows to a question card, `.title3` serif question text, answer field or "Take another photo" ink pill, "Skip" text button. Existing `FollowUpSheet` content is restyled with the same tokens; remove its icon tiles.
- Error / empty result / "no damage found": hero stays, scrim off, sheet shows serif `.title2` "We couldn't find the damage." / `.subheadline` secondary "Try a closer photo in daylight, with the damage in the middle." / ink pill "Try again" / text button "Choose another photo". Borrowed structure: `refs/scan/bitepal-3.jpg` ([Mobbin](https://mobbin.com/screens/229c5792-8472-41f0-8255-e82917e6cbe5)) (one sentence headline, one sentence help, one pill). No mascot.
- Offline / timeout: "No connection." / "Your photo is saved. Try again when you're back online." / pill "Try again".
- Blocked: handled by `BlockView` (3.9).

**Motion.** See section 4. Auto-zoom to small damage stays (scale up to 2.4x over 0.9 s `easeInOut` while the outline draws).

---

### 3.4 Finding (diagnosis)

**Purpose.** Say what is wrong, in one headline, with the marking as the hero.

**References**
- `refs/analysis/lovi-1.jpg` ([Mobbin](https://mobbin.com/screens/e6316517-0b99-428f-a07c-93cf5e8be244)): sheet with category overline, thumbnail, bold one-line title, body in a soft grey block. Borrow typographic order.
- `refs/analysis/calai-1.jpg` ([Mobbin](https://mobbin.com/screens/2db7609c-6b5f-4a75-8813-4045e4300775)): photo top, sheet below with a title row and one action row.
- `refs/verdict/warbyparker-1.jpg` ([Mobbin](https://mobbin.com/screens/5813f280-ce17-4ca0-9b44-dfcdf6187643)): "Your face scan results" sheet, label/value rows with expansion. Borrow the "Likely cause" expandable row (one line collapsed).
- `refs/verdict/bevel-1.jpg` ([Mobbin](https://mobbin.com/screens/44391026-6a4e-4069-88ef-cc7870c17a37)): a single hero statement, a quiet sentence, one dark button.

**Layout**
```
┌───────────────────────────────┐
│ (✕)                      (Adjust)│  Adjust = glass capsule "Adjust"
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
│▓▓░░ mask + label ░░░░░░░░░░░▓│  photo 56 % height, mask persists
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
├───────────────────────────────┤
│ WHAT WE FOUND                 │  overline
│ A small hole in grey knit.    │  serif .title semibold
│ The surrounding stitches are  │  .body, 2 to 3 lines
│ intact, so it can be darned.  │
│ ─────────────────────────     │
│ Cause   Snagged on something  ▾│  one row, expandable (max 2 causes)
│                               │
│ [        See my options      ]│  ink pill, pinned
└───────────────────────────────┘
```

**Components**
- `DiagnosisView` (restyle). Hero `MarkedPhoto` (frame height 56 % of screen), sheet `surface` top radius 28 overlapping the photo by 28 pt; content scrolls inside the sheet, CTA pinned in a bottom bar with a 0.5 pt top hairline and material background.
- Overline "What we found". Headline = first sentence of `diagnosis.summary` (serif `.title`, 2 lines max, `minimumScaleFactor` not allowed; truncate with the CopyPolish rules). Body = remaining sentences, `.body` ink, secondary if > 2 lines.
- Cause row: `DisclosureGroup`-style custom row (label "Cause" `.subheadline` secondary, value first cause `.subheadline.weight(.medium)`, chevron). Expanded shows up to 2 more causes as plain lines. Remove numbers and circles.
- "Adjust" (glass capsule on the photo, top-right, `slider.horizontal.3`? No: SF Symbol `hand.tap`, label "Adjust"): enters tap-to-refine; a pill appears bottom-center of the photo "Tap the damage" and each tap shows a 24 pt white ring that expands and fades (0.35 s) before the existing `/refine` call. Replaces the old hand icon + collapse icon. The expand icon (full-screen photo) becomes a double-tap on the photo.
- Remove: confidence ring, "fairly sure", chips row, garment pins.

**States.** Loading: Analysis. Error: see Analysis. Low confidence (< 0.6): existing follow-up path, never a percentage.

**Motion.** Sheet rises 0.45 s `ui`; mask holds its last frame (no re-draw). Headline fades in 0.25 s after.

**Final copy.** Overline "What we found". CTA "See my options". Adjust: "Adjust". Adjust hint: "Tap the damage". Cause row label: "Cause". Show more: "More causes". Accessibility for mask: "Damage outlined on your photo".

---

### 3.5 Verdict

**Purpose.** A confident recommendation, with the marked photo still the hero, time and cost as quiet facts, and a clear next action. Also hosts the "second life" ideas for replace.

**References**
- `refs/verdict/bevel-1.jpg` ([Mobbin](https://mobbin.com/screens/44391026-6a4e-4069-88ef-cc7870c17a37)): one large statement, one sentence, a single dark action. Borrow the headline-first hierarchy.
- `refs/verdict/zopa-1.jpg` ([Mobbin](https://mobbin.com/screens/e129e144-795f-49b5-8b12-93fdc969278d)): "How this compares" tinted rows with label left and bold value right, estimate disclaimer under. Borrow the facts rows and the disclaimer line.
- `refs/verdict/warbyparker-1.jpg` ([Mobbin](https://mobbin.com/screens/5813f280-ce17-4ca0-9b44-dfcdf6187643)): sheet over camera result with Continue and Rescan. Borrow the action pair.
- `refs/verdict/bitepal-1.jpg` ([Mobbin](https://mobbin.com/screens/9cf623e7-3839-4fb5-8192-b910b0ffdbd4)): "My meal" sheet over dimmed camera, item row with trailing action, black pill "Log 30 kcal". Borrow the sheet anatomy and the pill that carries a value.
- `refs/verdict/tide-1.jpg` ([Mobbin](https://mobbin.com/screens/da4b347e-27fc-4dcf-ba96-326b48ea415e)): calm full-screen statement with one suggestion row below. Borrow the quiet suggestion row for second life.
- `refs/completion/photoroom-1.jpg` ([Mobbin](https://mobbin.com/screens/581c0f2a-743c-4464-bb1a-c5ac3c2c2625)) and `refs/completion/hers-1.jpg` ([Mobbin](https://mobbin.com/screens/dc7b6682-eff4-4591-be82-a6d5d9fd6f62)): before/after as a bare slider and as a split card with tiny labels. Borrow for the hero "Marked | Repaired" toggle.
- `refs/project/rocketmoney-1.jpg` ([Mobbin](https://mobbin.com/screens/a5d153d6-fb60-4e2c-a1ab-814d20b19d85)): white rows with title, one-line text and chevron on a pale ground. Borrow for the "Before you start" row.

**Layout (repair yourself)**
```
┌───────────────────────────────┐
│ (←)                           │
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
│▓▓░░ mask + label ░░░░░░░░░░░▓│  photo 40 % height
│▓▓▓▓▓▓▓▓[ Marked | Repaired ]▓│  glass segmented, bottom of photo
├───────────────────────────────┤
│ MY ADVICE                     │
│ Repair it yourself.           │  serif .title semibold (verdict headline)
│ Small hole, solid knit around │  .body, max 3 lines
│ it. Darning closes it for the │
│ price of a needle and yarn.   │
│                               │
│ Effort      Time       Cost   │  caps .caption secondary
│ Low         ~ 1 h      € 5–12 │  .title3 semibold, vertical hairlines
│ Estimates, not quotes.        │  .footnote tertiary
│                               │
│ ┌─────────────────────────┐   │
│ │ Before you start      > │   │  row card, "5 things to gather"
│ └─────────────────────────┘   │
│ [        Start repair        ]│  ink pill
└───────────────────────────────┘
```

**Variants**
- **Repair yourself.** As above. CTA "Start repair" (creates the project, goes to Before you start).
- **Take it to a pro.** Headline "Take it to a pro." Facts: Effort "Pro job" (replaces Low/Medium/High), Time "At the shop", Cost range. Sheet below facts: section "What to ask for" with one `.body` line from `reasoning`'s second sentence if present. CTA "Save for later" (creates a project in "In progress" with status "With a pro"; no guide). Secondary text button "Close".
- **Replace.** Headline "Time to let it go." Reason. Section overline "GIVE IT A SECOND LIFE" and up to 3 rows (SF Symbol 20 pt in a 36 pt `fill` circle, title `.body.weight(.semibold)`, text `.subheadline` secondary), hairline separated, no card background. Symbol by kind: `upcycle` `scissors`, `recycle` `arrow.3.trianglepath`, `donate` `gift`. Facts row is hidden for replace (the 8–25 EUR is a replacement cost; show a single line "A replacement costs about 8–25 EUR." `.subheadline` secondary). CTA "Done" (Home), secondary text "Scan something else".

**Components**
- `DecisionView` (rewrite). Hero `MarkedPhoto` 40 % height with `HeroModeToggle` ("Marked | Repaired", only if `afterState == .ready`; label "Repaired" shows the Muse Image result with the existing `BeforeAfterSlider` drag; a `.footnote` caption inside the photo bottom-left "Preview" while Repaired is selected). Toggle = glass capsule 36 pt.
- `FactsRow`: `HStack` of three columns separated by 0.5 pt vertical hairlines; each column `VStack(alignment: .leading, spacing: 4)` overline + value; container has no background.
- `ChecklistRow` (the "Before you start" card): `card` background radius 20, padding 16, title `.body.weight(.semibold)`, subtitle `.subheadline` secondary "5 things to gather, you have 2" (or "Everything is ready" when complete), chevron `.footnote` tertiary.
- Remove: gray app-icon tile, "My recommendation" label, three icon cards, "The options compared" table, bottom blue "Take a new photo" capsule on repair verdicts.

**States.** Loading: the verdict sheet shows 3 skeleton lines (`fill` rounded rectangles, shimmer off) only if navigated here before the response is complete (should not happen). Error: handled upstream. Offline: Verdict works from the stored response.

**Motion.** Hero shrinks from 56 % to 40 % via `matchedGeometryEffect` and the sheet content swaps with a 0.3 s cross-fade; mask stays visible and re-fits (zoom rect eased 0.6 s). Facts count up numerals (`.contentTransition(.numericText())`) 0.5 s on appear.

**Final copy.** See section 5.4 for every verdict string and rewritten recordings.

---

### 3.6 Before you start (checklist and shopping)

**Purpose.** The gate between a verdict and the first step; also the place the user returns to to see what is missing.

**References**
- `refs/checklist/nytcooking-1.jpg` ([Mobbin](https://mobbin.com/screens/4cea7541-c8ea-41a1-a34f-e71e9754d6c0)): checkbox rows, checked items grey out, quantity in bold, underline tabs. Borrow the greying and the quiet checkbox.
- `refs/checklist/centr-1.jpg` ([Mobbin](https://mobbin.com/screens/f8e5377c-271a-4e9b-b3e7-713a3cffbdcb)): grouped list with section headers, empty circle checkboxes, quantity right-aligned bold. Borrow group structure.
- `refs/checklist/recime-1.jpg` ([Mobbin](https://mobbin.com/screens/81ed4348-a658-4958-b059-e26ad58ee1e5)) and `refs/checklist/julienne-1.jpg` ([Mobbin](https://mobbin.com/screens/27a77111-4b82-4982-aec9-e723051f0ce0)): thumbnails left, hairline rows, serif header, a "Clear" pill. Borrow serif header and hairlines.
- `refs/checklist/cherrypick-1.jpg` ([Mobbin](https://mobbin.com/screens/5e4ba8b5-6fd0-4fb9-8a4d-04e1671b0edd)): struck-through unavailable items with a "Swap" text action. Borrow for "household alternative".
- `refs/project/airbnb-1.jpg` ([Mobbin](https://mobbin.com/screens/cf0264f7-185c-48c2-9875-78f62ff48bbc)) ("Finish up and publish"): rows with title, status dot and chevron. Borrow the status-dot language.

**Layout**
```
┌───────────────────────────────┐
│ (←)                       (⤴) │
│ Gather these first.           │  serif largeTitle-ish (.title)
│ 2 of 5 ready                  │  .subheadline secondary + thin progress line
│ ━━━━━▒▒▒▒▒▒▒▒                 │
│ MATERIALS                     │  overline
│ ◯  Denim patch, light blue    │  circle 28 pt; tap = "have it"
│    1 piece, about 10 x 15 cm  │  .subheadline secondary
│    Or use a clean denim scrap │  .footnote tertiary
│                        Find ↗ │  trailing text link, accent
│ ───────────────────────────── │
│ ●  Polyester thread, blue     │  checked: accent filled circle, text secondary
│ TOOLS                         │
│ ◯  Sharp hand needle  Optional│
│                               │
│ 3 required items to get       │  .footnote secondary (above CTA)
│ [        Start repair        ]│  ink pill, disabled until required done
│        I'll gather them later │  text button, returns to Home
└───────────────────────────────┘
```

**Components**
- `ShoppingListView` (rewrite as `ChecklistView`; keep route name `.shopping`). `List`-style custom `ScrollView`, groups "Materials" / "Tools" (from `kind`), rows via `ChecklistItemRow`.
- Row: 44 pt min height, leading `CheckCircle` 26 pt (empty = 1.5 pt `inkTertiary` ring, checked = accent fill with white `checkmark` semibold 13), title `.body`, quantity `.subheadline` secondary, household alternative `.footnote` tertiary "Or: …". Trailing: `Optional` `.footnote` tertiary for non-required, and for unchecked required rows a `Find` text link opening `https://www.google.com/search?tbm=shop&q=<search_term>` (replaces the "Buy" pill). Two states only (have / not yet); the previous third state "Buy" is mapped to "not yet" (`ItemStatus.buy` stays in the model, shown as unchecked).
- Header: `Text("Gather these first.")` serif `.title.weight(.semibold)`, progress caption, `ProgressLine` 3 pt.
- Bottom bar: caption + ink pill + text button. Pill disabled state = `fill` background, `inkTertiary` text (not 0.5 opacity gray glass).
- Share (toolbar trailing, `square.and.arrow.up`): existing plain-text share of the list stays.
- Estimated total cost line moves into the header as `.footnote` "About 5–12 EUR if you buy everything".

**States.** Empty (no items, e.g. pro verdict): not reachable. All ready: caption becomes "Everything is ready"; CTA "Start repair" enabled and the header line turns "All set." Error: none. Offline: Find links open Safari (fails gracefully).

**Motion.** Check: circle fills with a 0.18 s scale 0.8 to 1 spring and selection haptic; row text cross-fades to secondary; progress line animates 0.3 s. List never reorders.

**Final copy.** Title "Gather these first." Caption "2 of 5 ready" / "All set." Overlines "Materials", "Tools". Trailing "Optional", "Find". Alternative "Or: a clean denim scrap". Above CTA "3 required items to get" / "Everything is ready". CTA "Start repair" (when entering from Verdict) / "Continue repair" (when step > 0). Text button "I'll gather them later". Nav title (inline, on scroll) "Before you start". Cost line "About 5–12 EUR if you buy everything". Share: "Share list".

---

### 3.7 Guide (step player)

**Purpose.** One step per screen, with the stitch path / glue zone / solder points drawn on the user's own photo. Calm, focused, hands-busy friendly.

**References**
- `refs/guide/kitchenstories-1.jpg` ([Mobbin](https://mobbin.com/screens/c0dbae93-8b94-436d-b8fe-789c02841d43)): photo above, tool chip, large step text, segmented step bar at the bottom. Borrow the "uses: tool" line and the large type.
- `refs/guide/peloton-1.jpg` ([Mobbin](https://mobbin.com/screens/ddbad8c8-8a68-4c12-98d5-6475e8e7bb74)) and `refs/guide/ladder-1.jpg` ([Mobbin](https://mobbin.com/screens/2785953e-be22-43b7-97de-c94c3825a05b)): thin segmented progress bar at the very top, exercise title and set label under. Borrow the segmented bar.
- `refs/guide/blueapron-1.jpg` ([Mobbin](https://mobbin.com/screens/efd46517-8af3-4395-a301-7dfa97375ec2)): "STEP 1 OF 5" small caps over a serif title and a big photo. Borrow exact typographic order.
- `refs/guide/julienne-1.jpg` ([Mobbin](https://mobbin.com/screens/5ddc1d76-b042-4552-97fb-698b19eb8688)): serif step text, vertical progress, a "Cooking tip" in muted italics. Borrow the tip styling for "Watch out".
- `refs/guide/crouton-1.jpg` ([Mobbin](https://mobbin.com/screens/587d65fe-90b9-4730-b9b3-f614f684e5f0)): one sentence per screen, big round next arrow, page dots. Borrow the single-sentence discipline (copy section 5.5).
- `refs/guide/hellofresh-1.jpg` ([Mobbin](https://mobbin.com/screens/a8ce2bb8-cecc-423b-aaaf-53e3e00e333a)): photo top, short text, timers listed as rows with a clock. Borrow the timer row for glue/cure timers.
- `refs/guide/ikea-1.jpg` ([Mobbin](https://mobbin.com/screens/721f823b-6416-4e60-a426-379e0bdc9b32)): dashed overlay drawn on the live view with "1 of 5" overline and a black pill. Borrow the dashed line language for overlays.
- `refs/guide/airbnb-1.jpg` ([Mobbin](https://mobbin.com/screens/52b29c50-2480-4676-90fd-ea2eec45befb)): timeline spine with a rounded thumbnail per step. Borrow in Project steps list (3.8).

**Layout**
```
┌───────────────────────────────┐
│ ▓▓▓ ▓▓▓ ▓▓▓ ▒▒▒ ▒▒▒           │  segmented progress, 3 pt, y = safe top + 8
│ (✕)                      (⤴) │  glass circles over the photo
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
│▓▓▓▓▓ dashed stitch path ▓▓▓▓▓│  photo 46 % height, overlay (section 4.4)
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  radius 28 at bottom corners
│ STEP 3 OF 5                   │  overline
│ Anchor the yarn               │  serif .title2 semibold
│ Thread the needle with 40 cm  │  .body
│ of yarn. From the inside,     │
│ come up 5 mm outside the hole.│
│ Leave a 5 cm tail.            │
│ ✓ Done when the yarn holds    │  .subheadline secondary, check glyph tertiary
│   in firm knit.               │
│ │ Watch out                   │  2 pt accent bar at left, overline + text
│ │ A long thread tangles.      │
│ Uses: darning needle, yarn    │  .footnote secondary
│  (‹)   [      Done      ]  Not working? │  bottom bar
└───────────────────────────────┘
```

**Components**
- `GuideView` (restyle). Top `SegmentBar` (shared component with Home): N = number of steps, height 3, gap 4, filled = accent, current = accent at 0.5 opacity half-filled animating when the timer runs; sits over the photo's top safe area with a 0.18 black gradient for legibility. Remove the four-color bar, the "Step 3 of 5" label above the photo and the Close pill.
- Top buttons: close `xmark`, 44 pt `.glass` circle over the photo.
- Photo `MarkedPhoto` in guide mode (step overlay only, no labels), height 46 %, bottom corner radius 28; double-tap to expand (replaces the collapse icon).
- Text block padding 20: overline, serif title, body (`.body`, `lineSpacing(4)`), `DoneWhenLine` (client-side split of the final "Done when" sentence, section 5.5), `WatchOut` block (replaces the yellow card; 2 pt accent leading bar, overline "Watch out", `.subheadline`), `UsesLine`.
- Safety-critical step (`requires_confirmation`): above the CTA a full-width row `Toggle`-like check "I've done this safely" with `exclamationmark.triangle` 16 pt secondary; Done stays disabled until checked (FlowGate unchanged). No yellow fill.
- Bottom bar (material, 0.5 pt top hairline): left back `chevron.left` 44 pt glass circle (hidden on step 1), center ink pill "Done" (on the last step "Finish"), right text button "Not working?" opens `StepHelpSheet` (restyled with the same tokens; remove its icon tiles).
- Timers: a step with a wait (glue cure, drying) shows `TimerRow` (clock `timer` SF Symbol, "Wait 10 min", `.monospacedDigit()` countdown trailing; start button text "Start timer"), HelloFresh pattern.

**States.** Loading step help: sheet shows a spinner row "Checking this step". Error on help: "Couldn't load help. Try again." Offline: guide works offline; help shows error. No photo (cropped): hero uses the stored image.

**Motion.** Step change: photo overlay crossfades 0.25 s, text slides `.move(edge: .trailing)` 0.3 s `ui`; the SegmentBar segment fills 0.35 s. Overlay animates per section 4.4. Done press: success haptic, 0.97 scale.

**Final copy.** Overline "Step 3 of 5". Pill "Done" / "Finish". Secondary "Not working?". Safety check "I've done this safely". Done-when prefix "Done when". Watch out overline "Watch out". Uses "Uses: darning needle, grey yarn". Timer "Wait 10 min" / "Start timer". Help sheet title "Not working?" fields "What's happening?" button "Get help" ("Take a photo" secondary).

---

### 3.8 Project detail

**Purpose.** Reopen an unfinished repair: see what is still needed, how far you are, continue. Also the home for finished repairs.

**References**
- `refs/project/airbnb-1.jpg` ([Mobbin](https://mobbin.com/screens/cf0264f7-185c-48c2-9875-78f62ff48bbc)) ("Finish up"): large title, grey subtitle, rows with title, detail and a status dot (Complete / Required), chevron. Borrow row pattern for "What you still need".
- `refs/project/hims-1.jpg` ([Mobbin](https://mobbin.com/screens/338ce5a5-d309-4aca-bc4b-b1c12131a7d0)): card with named progress stages as a line. Borrow the segmented line.
- `refs/project/gentlerstreak-1.jpg` ([Mobbin](https://mobbin.com/screens/d52cd871-49fa-4ccb-b944-cb4a60ffed0d)) and `refs/project/gentlerstreak-2.jpg` ([Mobbin](https://mobbin.com/screens/0a99f3fb-c1b1-4b14-915c-1498cb8e329a)): one hero numeral with a small caption, quiet two-column stats beneath. Borrow the hero numeral "3/5".
- `refs/project/applefitness-1.jpg` ([Mobbin](https://mobbin.com/screens/5b8d5290-6c52-436f-bac3-9d0a531db829)): ring + figure pairing, overline card titles with chevron, floating glass bar. Borrow overline titles.
- `refs/project/copilot-1.jpg` ([Mobbin](https://mobbin.com/screens/b9f87d05-1926-4b80-97c8-964ed8335b7f)): row of small rings with figures under them, caps overlines. Borrow for compact item status (optional).
- `refs/project/rocketmoney-1.jpg` ([Mobbin](https://mobbin.com/screens/a5d153d6-fb60-4e2c-a1ab-814d20b19d85)): rows with title, one line and chevron; black pill at bottom. Borrow the pill placement.
- `refs/guide/airbnb-1.jpg` ([Mobbin](https://mobbin.com/screens/52b29c50-2480-4676-90fd-ea2eec45befb)): timeline with rounded thumbnails and a hairline spine. Borrow for the steps list.

**Layout**
```
┌───────────────────────────────┐
│ (←)                       (···)│  menu: Delete project
│┌─────────────────────────────┐│
││▓▓▓▓ photo + outline ▓▓▓▓▓▓▓▓││  hero card 16:10, radius 28, outline static
│└─────────────────────────────┘│
│ Grey knit sweater             │  serif .title
│ Darn the hole                 │  .subheadline secondary
│                               │
│ 3/5                           │  hero numeral 56 semibold
│ steps done                    │  .footnote secondary
│ ━━━━━━━━━▒▒▒▒▒▒               │
│ WHAT YOU STILL NEED           │
│ Darning needle        ● Required >│  Airbnb row, 56 pt
│ Grey yarn             ● Required >│
│ Already have 2 items          ▾  │  collapsed group
│ STEPS                         │
│ ● Lay the sweater flat        │  node filled = done
│ ● Trim loose fibres           │
│ ◉ Anchor the yarn             │  node ring accent = current
│ ○ Weave the mesh              │  node empty = upcoming
│ ○ Secure and check            │
│ [   Continue with step 3    ] │  ink pill pinned
└───────────────────────────────┘
```

**Components**
- `ProjectView` (new route `.project(caseId)`), `ScrollView` on `bg`.
- Hero card: `MarkedPhotoThumb` with outline (no label) radius 28, aspect 16:10; tap opens a full-screen viewer (existing `ReviewSheet` image).
- Title `.title` serif, subtitle `.subheadline` secondary. Hero numeral line: `Text("3/5")` hero numeral style; caption "steps done"; `SegmentBar` under it.
- "What you still need": rows `ProjectNeedRow` (title `.body`, trailing status text `.footnote` accent "Required" / tertiary "Optional", leading nothing; dot 8 pt accent for required; chevron). Tap row toggles to "Have it" with a confirmation haptic and the row moves into the collapsed "Already have" group (`DisclosureGroup`). If nothing is missing the section shows `.subheadline` secondary "You have everything you need." and no rows.
- "Steps": `StepTimeline`: 1 pt hairline spine at x = 20, nodes 12 pt (done: ink fill + white check 7 pt; current: 2 pt accent ring with 4 pt accent center; upcoming: 1.5 pt tertiary ring), step titles `.body` (done secondary, current semibold). Tap a step jumps into Guide at that step (allowed only for steps <= current, except "Review" for done steps).
- Pinned bar: ink pill. Label by state: "Continue with step 3", "Start step 1" (nothing done), "Gather what's missing" if required items missing (goes to Before you start), "View before and after" for finished.
- Finished project variant: hero becomes the `BeforeAfterSlider` (the Photoroom bare slider with BEFORE / AFTER caps, `refs/completion/photoroom-1.jpg` ([Mobbin](https://mobbin.com/screens/581c0f2a-743c-4464-bb1a-c5ac3c2c2625))), title unchanged, the numeral line becomes "Repaired" + date, and "Steps" are collapsed.
- Menu: "Delete project" (destructive, with confirmation dialog "Delete this project? Your photo and progress will be removed.").

**States.** Empty steps (pro verdict parked): hide Steps, show `.body` "A pro will take this one. Come back after the repair to log it." CTA "Mark as done". Error: none. Offline: fully functional.

**Motion.** Items collapsing animate `ui`; numeral changes use `.contentTransition(.numericText())`; the node of the just-finished step fills with a 0.25 s scale.

**Final copy.** Section overlines "What you still need", "Steps". Rows "Required", "Optional". Collapsed "Already have 2 items". Empty need "You have everything you need." Buttons above. Delete confirm above. Parked pro: "With a pro" as subtitle, "A pro will take this one. Come back after the repair to log it."

---

### 3.9 Completion

**Purpose.** Quiet payoff: the user's own before/after, one sentence, done.

**References**
- `refs/completion/applenews-1.jpg` ([Mobbin](https://mobbin.com/screens/9d6d2b9e-e1dc-4cd6-8b0e-8c15b51e7727)): restrained completion: one emblem, one title, one info row, one primary, two quiet secondary pills. Borrow the discipline.
- `refs/completion/photoroom-1.jpg` ([Mobbin](https://mobbin.com/screens/581c0f2a-743c-4464-bb1a-c5ac3c2c2625)): before/after as a bare slider with BEFORE / AFTER caps. Borrow the slider treatment.
- `refs/completion/hers-1.jpg` ([Mobbin](https://mobbin.com/screens/dc7b6682-eff4-4591-be82-a6d5d9fd6f62)), `refs/completion/noom-1.jpg` ([Mobbin](https://mobbin.com/screens/04ff3e32-9b8a-4a80-b661-0235f0b65dcb)): before/after in a rounded card with tiny caps labels; serif headline below. Borrow the card and caps labels.
- `refs/completion/jomo-1.jpg` ([Mobbin](https://mobbin.com/screens/b223a4d8-3555-4aa4-8e2d-edfb8f2a9915)): "Good job" over the user's own photo with a single check. Borrow the idea of the user's photo as the celebration, not confetti.

**Layout**
```
┌───────────────────────────────┐
│ (✕)                           │
│┌─────────────────────────────┐│
││ BEFORE  ▓▓▓▓│▓▓▓▓▓  AFTER   ││  slider card 4:5 radius 28 (Muse Image after
││         ▓▓▓▓◉▓▓▓▓▓          ││  preview if available, otherwise the final-photo
│└─────────────────────────────┘│  the user took, otherwise original photo only)
│ Mended.                       │  serif .largeTitle
│ One less thing in the bin.    │  .body secondary
│ About 0.4 kg of textile kept  │  .subheadline secondary (only if known)
│ in use.                       │
│ [            Done            ]│
│        Share before and after │  text button
└───────────────────────────────┘
```

**Components.** `CompletionView` (restyle). Slider reuses `BeforeAfterSlider` restyled: 1.5 pt white divider, 32 pt white circle thumb with `chevron.left.chevron.right` 12 pt black, caps labels `.caption2.weight(.semibold)` tracking 0.8 in white on a 0.25 black capsule. Without an after image: single photo, no slider. "Optional result photo" action: text button "Add a photo of the result" opens the camera; after capture the slider uses it (replaces the generated preview). Remove confetti if any, the big check, and stats cards.

**States.** No saved rescue: hide the kilogram line. Error: none.
**Motion.** Slider auto-sweeps once 0.9 s (0.5 to 0.1 to 0.5) on appear, then rests at 0.5. Success haptic on appear.
**Final copy.** Title "Mended." (shoes: "Back on its feet." is not used; one title for all). Subtitle "One less thing in the bin." Line "About 0.4 kg of textile kept in use." / "About 0.6 kg kept out of the bin." Primary "Done". Text "Share before and after". Optional "Add a photo of the result". Labels "Before", "After".

---

### 3.10 Block (safety gate)

**Purpose.** Stop calmly. FlowGate logic is untouched.

**References.** `refs/blocked/brick-1.jpg` ([Mobbin](https://mobbin.com/screens/0338aaef-88cd-4ef4-b4e9-6e5cf45c4126)) (glyph, one-line title, two-line explanation, one pill, no alarm color), `refs/blocked/opal-1.jpg` ([Mobbin](https://mobbin.com/screens/24ea6194-b80c-4e36-8d53-80802f03c64d)) (explanatory note in a soft field). 

**Layout.** Black text on `bg`. Centered column: SF Symbol `hand.raised` 40 pt thin weight, `inkTertiary`; serif `.title` "Not one to repair at home."; `.body` secondary reason (from the gate); soft note in a `fill` rounded field radius 16 (`.subheadline`) "If it's a battery, bring it to a recycling point. Don't charge it or open it."; ink pill "Back to Repairs". The photo thumbnail (radius 20, 120 pt tall, with no mask) sits above the symbol to keep context. Remove red tint, stop-sign icons and any "blocked" badge.
**Copy.** Reasons per category (map from the existing gate reason keys): battery "This one has a lithium battery. A damaged cell can ignite, and no guide can make that safe at home."; mains "This runs on mains power. Opening it is dangerous without training."; helmet "A helmet protects you only when it is intact. A repaired one can fail without showing it."; child seat "A child seat has to be exactly as tested. Don't repair it."

### 3.11 Settings (sheet)

Inset grouped `List`, large title "Settings" inline. Sections: "Language" (System / English / Deutsch), "Privacy" (one footnote: "Photos are sent to the analysis server only to assess the repair." only if true per proxy; confirm before shipping), "About" (version, "Mendlet"). Demo/precision/fast-replay toggles are hidden unless `-demo`/DEBUG launch arguments or a hidden 5-tap on the version row. No accent colors on rows except links.

---

## 4. Marking and mask styling (the hero feature)

The marking is the proof that Meta SAM 3.1 sees the damage. It must read as a product feature: precise, quiet, lit. Reference language: Apple Photos subject lift (`refs/analysis/applephotos-1.jpg` ([Mobbin](https://mobbin.com/screens/19627cf0-5ca8-4570-b04a-f383be8596c9)), `refs/analysis/applephotos-2.jpg` ([Mobbin](https://mobbin.com/screens/19627cf0-5ca8-4570-b04a-f383be8596c9)), `refs/analysis/capwords-1.jpg` ([Mobbin](https://mobbin.com/screens/2058a2fb-c097-4ff5-bfd6-f47fd93e8c4f))), Google Lens region focus (`refs/analysis/googlelens-1.jpg` ([Mobbin](https://mobbin.com/screens/fce278a0-4a62-4851-b08e-b667289033c1)), `refs/analysis/googlelens-2.jpg` ([Mobbin](https://mobbin.com/screens/40e20d17-0165-48c6-8b82-bf009a264fce))), BitePal's thin scan sweep (`refs/analysis/bitepal-2.jpg` ([Mobbin](https://mobbin.com/screens/e904fdb7-bc19-486f-9f99-9bd7b0564e1b))).

### 4.1 Static anatomy (one `MarkedPhoto` component)

`MarkedPhoto(image, masks, mode, labelStyle, zoom)` replaces the ad-hoc composition in `SegmentLayer`, `OverlayRenderer` and `LabelPins`. Layers bottom to top:

1. **Photo.** Aspect fill, continuous corner radius as the screen dictates. No border.
2. **Scrim with cut-out.** `Color.black.opacity(0.30)` as an even-odd path: full rect minus the damage mask path(s). The unscrimmed interior reads as "lifted". Edge of the cut-out softened with `.blur(radius: 0.6)` on the mask path used as the scrim's hole so the transition is not jagged (render the scrim in a `Canvas`, blend `.destinationOut` for the mask).
3. **Interior tint.** `Color.white.opacity(0.10)` fill inside the mask. Nothing else inside (no hatch, no gradient).
4. **Outline.** The mask contour as a smoothed closed path: simplify (Ramer-Douglas-Peucker, epsilon = 0.4 % of the image diagonal), then Chaikin smoothing 2 iterations. `stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))`. Behind it a second identical stroke, `Color.black.opacity(0.28)`, `lineWidth 3`, `blur(1)` for legibility on pale fabric (this replaces the glow; there is no outer glow anywhere). On photos where the mask touches the image edge, do not stroke the edge-touching segment.
5. **Multiple instances.** Each connected component gets its own outline. Group ids as today. Parts masks (garment, sole, board) are **not drawn** in Finding/Verdict/Guide/Home by default; they remain available for geometry (stitch path planner, glue band, solder routing) and for electronics pads (4.4). Remove the white-on-white part layers and the part pins.
6. **Label (typographic, no chip).** One label per damage group: `Hole`, `Tear`, `Open seam`, `Loose sole`, `3 holes`, `Broken wire`. `Text` `.footnote.weight(.semibold)`, white, shadow `black.opacity(0.35) r2`, no background, no border, no percentage, no model name. A leader: 0.75 pt white (opacity 0.8) line from the nearest contour point (a 4 pt filled white dot on the contour) outward 24 to 40 pt at the free angle, text anchored at the line end with 6 pt gap. Reuse `LabelPins.place` for collision avoidance; remove its width calc for score/badge. Labels are shown in Analysis, Finding and Verdict, not in Guide or on Home cards.
7. **Dimension (optional, Verdict only).** If `DamageDimension` yields a value: hairline 0.75 pt white with 6 pt end ticks measured across the damage's long axis, offset 12 pt outside the contour, text `.caption2.weight(.medium)` white "about 4 cm" in the line's middle with a 4 pt black .0 gap behind. Always prefixed "about". Skip if the estimate is unavailable.

Do not draw: confidence, numbers, circles/rings around the damage, glow, colored fills, pulsing halos, chips, badges, arrows pointing at the mask.

### 4.2 Reveal animation (Analysis, first appearance; `ScanReveal.swift`)

Total 2.4 s, driven by one `phase` value. Reduce Motion: skip to the end state with a 0.25 s cross-fade.

| t (s) | Event |
| --- | --- |
| 0.0 to 0.5 | Frozen capture photo is on screen. Scrim fades 0 to 0.30 (`easeOut` 0.5). |
| 0.2 to 1.3 | **Scan sweep.** A horizontal light band (height 140 pt, linear gradient clear, white 0.20, clear; blend `.plusLighter` where supported, else `.screen`) travels from above the photo to below it, `easeInOut`. A 1 pt white line at 0.6 opacity rides the band's center (BitePal scan line, `refs/analysis/bitepal-2.jpg` ([Mobbin](https://mobbin.com/screens/e904fdb7-bc19-486f-9f99-9bd7b0564e1b))). |
| 0.9 to 1.9 | **Outline draws.** As the band crosses each instance's bounding box, its outline begins `trim(from: 0, to: t)` 0 to 1 over 0.9 s `easeInOut`, starting at the contour's top-most point, clockwise. Instances stagger by 0.12 s. |
| 1.5 to 2.0 | Interior tint fades in 0 to 0.10; the scrim's cut-out opens (the scrim hole is animated by a path mask scaled 0.96 to 1.0 with `ui` spring). |
| 1.9 to 2.4 | Leader line draws (0.2 s), then label fades in (0.2 s). Soft impact haptic (`UIImpactFeedbackGenerator(style: .soft)`) when the last outline completes. |
| in parallel | Auto-zoom to small damage: scale 1.0 to <= 2.4 over 0.9 s `easeInOut`, starting at 0.9 s. |

Resting state is the 4.1 stack. If the analysis result arrives after the reveal, hold the resting state; if it arrives before the sweep ends, finish the sweep (never cut it short), then proceed. With classic vs agent mode the same reveal runs; agent mode only shows additional rows in the hidden trace drawer.

### 4.3 Revisit behavior

Finding and Verdict show the resting state immediately (no re-draw). When the Verdict hero resizes, the mask re-fits with a 0.6 s `easeInOut` zoom rect interpolation. Project and Home thumbnails draw the outline statically at 1.25 pt without scrim or label.

### 4.4 Guide overlays (stitch path, glue, solder)

Same material language: white only, 2 pt round-capped strokes, no glow, no chips.

- **Stitch path (textile).** Planned path from `StitchPathPlanner` (unchanged). Upcoming = dashed `StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6])`, white 0.9. Completed portion (for the active step) = solid 2 pt. Needle entry/exit points: 5 pt white filled circle with a 1 pt white ring at 3 pt offset appearing at 8 pt/s along the path. A tiny 8 pt chevron every 80 pt shows direction. The active step animates the dash phase `0 to -12` over 0.9 s linear forever (stops under Reduce Motion). Backdrop: scrim 0.22 outside the mask (lighter than Analysis).
- **Darning grid (holes).** Parallel lines 1.5 pt white 0.85 clipped to the mask, spacing = path planner spacing, warp lines draw over 0.6 s; weft lines draw over 0.6 s staggered by 0.04 s.
- **Glue zone (shoes).** The band polygon filled white 0.16, outline 1.5 pt dashed white; press direction as a 2 pt arrow with a 6 pt open head, label none. Timers are shown in the step text/TimerRow, never on the photo.
- **Solder / wires (electronics).** Pads: 10 pt circle, 1.5 pt white ring, 3 pt center dot when active. Wire route: 2 pt solid white with 8 pt arrowhead at the pad end. Polarity: plain text `+` / `−` `.footnote.weight(.bold)` white with a 14 pt black 0.35 circle behind it (the only background allowed on the photo, for legibility on circuit boards).
- **Highlight (other steps).** Outline only (1.5 pt, no tint) on the segment referenced by `segment_ids`.

### 4.5 Implementation notes

- New shared pieces: `MarkedPhoto.swift`, `MaskPath.swift` (simplify + smooth, cached per mask), `RevealSweep.swift` (rewrite of `ScanReveal.swift`), `SegmentBar.swift`, `ViewfinderCorners.swift`.
- Keep `Segment`, `StitchPathPlanner`, `DamageDimension`, `LiveGeometry`. Restyle `OverlayRenderer`, `StitchPathView`, `SolderOverlay`, `ShoeOverlay` to the 4.4 values. Remove `Theme.partColors`, `segmentColor`, `LabelPinsLayer` chip drawing.
- Performance: build `Path` once per mask and cache; draw in `Canvas` for the scrim/outline stack; use `drawingGroup()` only on the sweep layer.

---

## 5. Copy guide

### 5.1 Voice

Plain statements in the present tense, second person only where an action is asked ("Turn the sweater inside out."). No persona, no exclamation, no hedging words (presumably, assumed, likely, probably, seems, appears), no "AI", no model names, no filler ("Please", "Simply"). Numbers as numerals with units (5 mm, 40 cm, 10 min). Sentence case everywhere. Overlines are the only uppercase (via `textCase`). Length targets: headline 3 to 7 words; reason 1 to 2 sentences (max 30 words); step title 2 to 4 words, imperative; step text 1 to 3 sentences (max 45 words); mistake 1 sentence (max 18 words).

### 5.2 Never show

`AI`, `Muse`, `SAM`, `Meta`, `LIVE`, `confidence`, `fairly sure`, `%` on any mark or fact, `Garment`, "I'm taking a close look", "Planning the repair", "4 of 4", "Agent log", "Doesn't help", "My recommendation", "The options compared", sparkles `✦`.

### 5.3 Client-side `CopyPolish` (display-only, applies to demo recordings and live responses)

A pure function `CopyPolish.sentence(_:)` in `Flow/Localization.swift` neighbors, unit-tested:
1. Trim; capitalize the first letter; ensure a final period.
2. Remove hedge words/phrases: `presumably `, `Presumably `, `assumed `, `Assumed `, `likely `, `probably `, `apparently `, `looks intact` -> `is intact`, `looks like` -> `is`. (Regex list, case-insensitive; collapse double spaces; if a sentence starts with "Assumed ", drop the whole sentence.)
3. Split sentences on `. ` for headline/body separation.
4. `DoneWhenLine.split(text)`: if the last sentence starts with `Done when`, `End state:` or `You're done when`, return (body, "Done when …" normalized: `End state:` -> `Done when`; lowercase the next word).
5. Common mistake: replace ` - ` (spaced hyphen) with `. ` and capitalize the next word.
6. German strings are not touched.
No other model text is rewritten on device. Real fixes belong in the prompt (5.6) and the next recording pass.

### 5.4 Verdict copy: templates and rewritten recordings

Headlines (fixed, from `recommendation`): `repair_self` "Repair it yourself." / `repair_pro` "Take it to a pro." / `replace` "Time to let it go." Overline always "My advice". Reason = `decision.reasoning` after `CopyPolish`. Effort labels: low "Low", medium "Medium", high "High"; time `time_minutes` formatted "About 1 h" / "20 to 45 min" / "2 to 3 h"; cost "5 to 12 EUR" (use the thin "–" and locale currency symbol, "€ 5–12"). Footnote "Estimates, not quotes." (`estimate_note` if present replaces it).

Rewritten from `Resources/LiveRecordings/*.en.json` (what the user should read; the left column is what the recordings contain today):

| Recording | Today (recording) | Display (after `CopyPolish`, and target model output) |
| --- | --- | --- |
| `real_sweater` summary | "Small hole with material loss in presumably grey knit sweater. Surrounding knit looks intact, suitable for darning." | Headline: "A small hole in grey knit." Body: "The surrounding stitches are intact, so it can be darned." |
| `real_sweater` reasoning | "Small hole with material loss in presumably knit sweater can be closed by hand darning without pulling edges together. Stable surrounding knit allows a self repair with needle and matching yarn." | "A small hole in solid knit. Darning closes it for the price of a needle and some yarn." |
| `real_sole` summary | "Leather dress shoe sole with a through-hole in the forefoot and heavy surrounding wear. Assumed leather outsole from user note and photo." | Headline: "Worn through at the forefoot." Body: "The leather sole has a full hole and the area around it is thin." |
| `real_sole` reasoning | "The leather outsole is worn through with a full hole in the forefoot. A DIY fill or glue cannot restore strength, walking safety, or water protection. A cobbler needs to replace the front sole and add a protective layer." | Verdict "Take it to a pro." Reason: "The sole is worn right through. Glue won't hold a step. A cobbler can replace the front half and add a protective layer." |
| `jeans` summary | "Assumed denim jeans leg with a long frayed tear with material loss directly beside the outer seam. White cross-threads remain, edges are frayed and cannot be closed tension-free." | Headline: "A long tear beside the seam." Body: "Threads are missing, so the edges can't be pulled together. The denim around it is sound." |
| `jeans` reasoning | "Long frayed tear in denim next to the seam with fabric threads missing. Edges cannot be pulled together without tension, but surrounding denim looks stable enough for a sew-on backing patch plus darning by hand." | "The edges won't close without pulling. A patch behind the tear and a darned top layer will hold." |
| `sneaker` summary | "Front sole of white sneaker is detached from the upper with a visible gap. Sole and upper edges appear intact, presumably suitable for gluing." | Headline: "The front sole has come loose." Body: "Both edges are intact, so it can be glued." |
| `sneaker` reasoning | "Front sole is locally detached but sole and upper look intact with no missing material, so cleaning and rebonding with flexible shoe adhesive is a realistic self-repair." | "Nothing is missing, only unstuck. Clean both surfaces, rebond with flexible shoe glue and it will hold." |
| `worn_shirt` summary | "Grey T-shirt, presumably worn cotton jersey, with dozens of small holes and several large holes across front, neckline and sides. Fabric looks overall very thin and fragile with no stable edges for repair." | Headline: "Worn thin all over." Body: "Dozens of small holes and several large ones, with no sound fabric left to stitch into." |
| `worn_shirt` reasoning | "The jersey is worn thin over the whole front with dozens of small holes and several large holes with frayed, unstable edges. There is no sound fabric left to anchor darning or patches, so hand repair would take many hours and tear out again." | Verdict "Time to let it go." Reason: "There is no sound fabric left to anchor a repair. Hand work would take hours and tear out again." |
| `worn_shirt` second life | "Cut into cleaning cloths — Cut the still usable parts into cleaning rags or workshop cloths. The thin jersey absorbs dust and polish well." / "Recycle via textile collection — Put the worn-out shirt in a textile collection container or bring it to the local recycling centre for textile recycling." | "Cut into cleaning cloths" — "Thin jersey is ideal for dusting and polishing." / "Textile collection" — "Drop it in a collection container or at your recycling centre." |

Second life titles: <= 4 words. Texts: 1 sentence <= 12 words.

### 5.5 Step copy

Template per step: **Title** (imperative, 2 to 4 words) / **Text** (what to do, with numbers) / **Done when** (one outcome sentence) / **Watch out** (one fix-oriented sentence). Safety lines inside text only for steps with `safety_critical`.

Rewritten from the recordings:

`real_sweater` (5 steps)
1. **Lay it flat, inside out.** "Turn the sweater inside out and lay the hole flat on a table. Smooth the knit so the hole sits relaxed, without stretching." Done when "the edges lie flat with no tension." Watch out "Stretching the knit pulls the hole bigger. Let it relax."
2. **Trim the loose ends.** "With small scissors, snip only the loose fibres around the hole, 1 to 2 mm. Keep your fingers clear of the blades." Done when "no long threads stick out." Watch out "Cutting stitches enlarges the hole. Trim fuzz only." (safety: scissors, confirmation)
3. **Anchor the yarn.** "Thread the darning needle with about 40 cm of grey yarn, unknotted. From the inside, come up 5 mm outside the hole edge. Leave a 5 cm tail." Done when "the yarn is anchored in firm knit." Watch out "A long thread tangles and tightens. Keep it short and loose."
4. **Weave the mesh.** "Sew parallel threads across the hole, 2 to 3 mm apart, running 5 mm into solid knit on each side. Then weave crosswise, over and under." Done when "an even, loose grid covers the hole." Watch out "Pulling tight puckers the knit. Keep every thread loose and even."
5. **Secure and check.** "Make 2 or 3 tiny backstitches in solid knit, then trim to 1 cm. Turn it right side out and stretch the area gently sideways." Done when "the edges stay closed with no puckering." Watch out "Cutting flush lets the darn pull out. Leave small tails."

`sneaker` (4 steps): 1 **Clean both surfaces** / 2 **Glue both sides** (safety: ventilation, confirmation) / 3 **Press it closed** / 4 **Clamp and cure** (timer "Wait 24 h"). Done-when examples: "both surfaces are dry, matte and dust-free." / "both sides feel tacky, not wet." / "the gap is closed and the edge sits flush." / "the toe stays closed when you pull gently."

`jeans` (6 steps): **Turn it inside out** / **Trim the fluff** / **Pin the patch** / **Baste around the patch** / **Darn over the tear** / **Lock the thread**.

Text length rule: if the model returns > 60 words, show the first 2 sentences and a "More" disclosure for the rest.

### 5.6 Prompt changes (separate from UI; `prompts/prompt_b_diagnose.v6.txt` -> `v7`)

Do not change the schema or API contract; change instructions only.

1. **Remove the "Annahme" instruction** (line 12: "nenne sie im summary als Annahme ('vermutlich …')"). Replace with: "Nenne das Material im summary direkt und ohne Einschränkung (z. B. 'graues Strickteil'), wenn es erkennbar ist. Verwende keine Wörter wie 'vermutlich', 'wahrscheinlich', 'scheint', 'angenommen'. Unsicherheit gehört in needs_more_info, nie in den Ton."
2. **summary:** "Höchstens zwei Sätze. Der erste Satz ist eine Nominalphrase von höchstens 9 Wörtern, die Material und Schaden benennt ('Kleines Loch in grauem Strick.'). Der zweite Satz sagt, ob die Umgebung intakt ist."
3. **decision.reasoning:** "Zwei Sätze, höchstens 30 Wörter. Satz 1: warum diese Empfehlung. Satz 2: was sie kostet oder was dafür nötig ist."
4. **Step title:** "Imperativ, 2 bis 4 Wörter."
5. **Step text:** "Höchstens 3 Sätze, höchstens 45 Wörter, mit Maßen. Der letzte Satz beginnt mit 'Fertig, wenn' und beschreibt den Endzustand in einem Satz. Kein 'End state:'."
6. **common_mistake:** "Ein Satz, höchstens 18 Wörter, Format: Fehler. Lösung. Kein Bindestrich als Trenner."
7. **second_life:** "title höchstens 4 Wörter; text ein Satz mit höchstens 12 Wörtern."
8. **likely_causes:** "Höchstens zwei, jeweils höchstens 6 Wörter, Nominalphrase."
9. Both English and German outputs follow the same limits (`{language}` placeholder is already used).
10. After editing, re-record the five demo scenarios with the key and replace the `*.en.json` files; until then `CopyPolish` bridges the gap. The README states responses are unedited recordings, so keep `CopyPolish` display-only (documented in the README as presentation formatting).

---

## 6. What to delete or replace in the current app

| Item | Where | Action |
| --- | --- | --- |
| Camera as root with floating History/Settings | `HomeView.swift`, `InlineCameraCard.swift` | Replace with new Home; camera moves to `ScanView` (reuse `InlineCameraSession`) |
| `Font.rounded` and every `.rounded(...)` call | `Theme.swift`, all views | Delete |
| Blue `AccentColor` | `Assets.xcassets/AccentColor` | Keep system blue (owner: no orange) |
| Garment/part pins, `%` scores, badges | `LabelPins.swift`, `SegmentLayer.swift`, `OverlayRenderer.swift` | Remove chip drawing; keep placement algorithm; replace by 4.1 labels |
| Filter chips "All / Garment x2 / Hole", hand icon, collapse icon | `DiagnosisView.swift` | Delete; "Adjust" capsule and double-tap to expand |
| Circle ring around damage | `SegmentLayer`/`ScanReveal` | Delete |
| Confidence ring, "fairly sure", numbered cause bubbles | `DiagnosisView.swift` | Delete |
| Agent log card, "Muse Spark" badge, LIVE tag, "4 of 4" bar | `AnalysisView.swift`, `AgentTraceView.swift` | Move behind tap-to-reveal "Behind the scenes" drawer; default hidden |
| 4-color progress bar | `AnalysisView.swift`, `GuideView.swift` | Replace by `SegmentBar` / `PhaseDots` |
| Gray app-icon tile, "My recommendation", three icon metric cards, options-compared table | `DecisionView.swift` | Delete; use headline + `FactsRow` |
| Full-width blue `.borderedProminent` capsules | `Components.swift` (`PrimaryButton`) | Replace with ink pill (54 pt), one per screen |
| Yellow "caution" card in steps | `GuideView.swift` | Replace by `WatchOut` bar and safety check row |
| "Have it" / "Buy" pill pairs, blue "Required" tags, disabled gray capsule | `ShoppingListView.swift` | Replace with `ChecklistItemRow` |
| Close/Share pill buttons in guide header | `GuideView.swift` | 44 pt glass circles on the photo |
| "Doesn't help" | `GuideView.swift` | "Not working?" text button |
| `Theme.partColors`, `segmentColor(_:in:)` | `Theme.swift` | Delete |
| Demo/precision/fast switches in Settings | `SettingsSheet.swift` | Hide unless DEBUG/launch arg/5-tap |
| Back chevron + title nav bars styled as pills | all pushed views | Use native `NavigationStack` back button; hide nav bar only on Scan/Analysis/Guide |

---

## 7. Constraints for the builder

1. **Demo mode stays functional and invisible.** No "Demo" label, banner or toggle in the UI. Keep `DemoBootstrap`, `DemoImageFactory`, `LiveRecordings`, `MockAPIClient`.
2. **Launch arguments keep working** (`scripts/screenshots.sh`): `-uiScreen liveScan|analysis|diagnosis|decision|shopping|guide|completion|settings`, `-uiScenario <DemoScenario raw>`, `-uiStep <n>`, `-recoveryTrace YES|NO`. Add `-uiScreen home` and `-uiScreen project` (with a seeded in-progress case) for new screenshots; extend `HomeView.debugJump()`. Update `scripts/screenshots.sh` with `home`, `project`, `scan` shots and re-take `docs/screenshots/v8-en-*.png`.
3. **FlowGate / safety gating untouched** (`Models/Gates.swift`, `FlowModel` gate checks, `requires_confirmation` blocking Done). The new UI only restyles the confirmation control.
4. **API contract untouched** (`Models/Contract.swift`, `APIClient`, proxy). Everything above is derived client-side or via prompt text only.
5. **Tests must pass**: `RepairAssistantTests` and `proxy` pytest. Add unit tests for `CopyPolish`, `MaskPath` simplification (point count reduced, closed path), `ProjectTitle` derivation, and `DoneWhenLine.split`.
6. **Deployment target stays iOS 17.** Liquid Glass only through `View.glass(_:tint:interactive:)` in `Theme.swift` and `systemButtonStyle`; do not call `glassEffect` directly or use `.glassProminent` outside the helper. The primary ink pill is custom (`PrimaryButtonStyle` rewritten); the glass helper is used for floating controls only (Scan button, circle buttons, hero toggle, hint pill).
7. **Localization.** `Localizable.xcstrings` entries for all new English strings; German strings must be produced for the same keys (the app is English-only on a German device by the latest commit, but the xcstrings keep both). `tr(...)` stays the lookup.
8. **Accessibility.** Every control has a label; the mark has `accessibilityLabel("Damage outlined on your photo")`; Dynamic Type up to AX3 (hero numeral and mark labels excepted); contrast: white text on photo always has the 0.35 shadow; tap targets >= 44 pt; Reduce Motion handled everywhere (section 1 #7).
9. **Dark mode.** All surfaces use system colors; accent has a dark variant; Home and Checklist are readable in both.
10. **File plan.** New: `Views/HomeView.swift` (rewrite), `Views/ProjectView.swift`, `Views/ScanView.swift`, `DesignSystem/MarkedPhoto.swift`, `DesignSystem/SegmentBar.swift`, `DesignSystem/ViewfinderCorners.swift`, `Rendering/MaskPath.swift`, `Flow/CopyPolish.swift`. Rewrite: `DiagnosisView`, `DecisionView`, `ShoppingListView`, `GuideView`, `CompletionView`, `BlockView`, `AnalysisView`, `ScanReveal`. Restyle: `StepHelpSheet`, `FollowUpSheet`, `SettingsSheet`, `ReviewSheet`, `BeforeAfterSlider`, overlay renderers.
11. **Order of work** (each step independently shippable): (1) tokens + AccentColor + ink button; (2) `MarkedPhoto` + reveal; (3) Analysis/Finding/Verdict; (4) Home + Project + persistence hooks; (5) Checklist; (6) Guide + overlays; (7) Scan; (8) Completion/Block/Settings; (9) CopyPolish; (10) screenshots + README images.

---

## 8. Reference index

Every downloaded reference with its Mobbin link. Files are in `docs/design/refs/`.

| File | Mobbin | Notes |
| --- | --- | --- |
| `refs/analysis/applephotos-1.jpg` | [screen](https://mobbin.com/screens/19627cf0-5ca8-4570-b04a-f383be8596c9) | Apple Photos subject lift share sheet |
| `refs/analysis/applephotos-2.jpg` | [screen](https://mobbin.com/screens/19627cf0-5ca8-4570-b04a-f383be8596c9) | Apple Photos subject lift: subject isolated with soft glass share sheet (Subject row + action grid) |
| `refs/analysis/bitepal-1.jpg` | [screen](https://mobbin.com/screens/11e8327b-d4ee-4cbc-b7a9-44cc33d255ea) | BitePal analyzing: photo dimmed, bottom sheet Analyzing |
| `refs/analysis/bitepal-2.jpg` | [screen](https://mobbin.com/screens/e904fdb7-bc19-486f-9f99-9bd7b0564e1b) | BitePal scan line over circular crop |
| `refs/analysis/calai-1.jpg` | [screen](https://mobbin.com/screens/2db7609c-6b5f-4a75-8813-4045e4300775) | Cal AI result: photo on top, white sheet with big number, Fix Issue + Done |
| `refs/analysis/capwords-1.jpg` | [screen](https://mobbin.com/screens/2058a2fb-c097-4ff5-bfd6-f47fd93e8c4f) | CapWords: lifted subject cutout with soft halo, label under, confirm/redo/dismiss row |
| `refs/analysis/googlelens-1.jpg` | [screen](https://mobbin.com/screens/fce278a0-4a62-4851-b08e-b667289033c1) | Google Lens: selected region stays bright with corner brackets, rest of photo dimmed; result sheet pulls up with grabber |
| `refs/analysis/googlelens-2.jpg` | [screen](https://mobbin.com/screens/40e20d17-0165-48c6-8b82-bf009a264fce) | Google Lens: tall selection, bracket corners at region edges, chips row Translate/Search |
| `refs/analysis/lovi-1.jpg` | [screen](https://mobbin.com/screens/e6316517-0b99-428f-a07c-93cf5e8be244) | Lovi: result sheet over dimmed photo, filter chips, thumbnail + category + title rows |
| `refs/analysis/starlink-1.jpg` | [screen](https://mobbin.com/screens/a446c6a5-c04d-40b9-82db-a5e3b865074b) | Starlink: white circle View results on dark camera |
| `refs/blocked/brick-1.jpg` | [screen](https://mobbin.com/screens/0338aaef-88cd-4ef4-b4e9-6e5cf45c4126) | Brick: bracket glyph, one-line title, two-line grey explanation, one pill button; calm, no red alarm |
| `refs/blocked/opal-1.jpg` | [screen](https://mobbin.com/screens/24ea6194-b80c-4e36-8d53-80802f03c64d) | Opal: Blocked sheet, grey info note in rounded field |
| `refs/checklist/centr-1.jpg` | [screen](https://mobbin.com/screens/f8e5377c-271a-4e9b-b3e7-713a3cffbdcb) | Centr shopping list: circles, groups, qty bold right |
| `refs/checklist/cherrypick-1.jpg` | [screen](https://mobbin.com/screens/5e4ba8b5-6fd0-4fb9-8a4d-04e1671b0edd) | Cherrypick: struck-through unavailable items, tick boxes, Swap action (swap = have/buy) |
| `refs/checklist/julienne-1.jpg` | [screen](https://mobbin.com/screens/27a77111-4b82-4982-aec9-e723051f0ce0) | Julienne shopping list: serif header, recipe groups, thumbnail rows, Clear pill |
| `refs/checklist/nytcooking-1.jpg` | [screen](https://mobbin.com/screens/4cea7541-c8ea-41a1-a34f-e71e9754d6c0) | NYT Cooking ingredients: sheet with underline tabs, quiet checkbox rows, checked items grey out, bold quantity |
| `refs/checklist/recime-1.jpg` | [screen](https://mobbin.com/screens/81ed4348-a658-4958-b059-e26ad58ee1e5) | Recime grocery list: thumbnails, hairline rows, serif title, checkboxes |
| `refs/completion/applenews-1.jpg` | [screen](https://mobbin.com/screens/9d6d2b9e-e1dc-4cd6-8b0e-8c15b51e7727) | Apple News: restrained completion - one emblem, title, info card, Done + secondary pills |
| `refs/completion/hers-1.jpg` | [screen](https://mobbin.com/screens/dc7b6682-eff4-4591-be82-a6d5d9fd6f62) | Hers: before/after split inside rounded card with tiny pill labels Month 0 / Month 6 |
| `refs/completion/jomo-1.jpg` | [screen](https://mobbin.com/screens/b223a4d8-3555-4aa4-8e2d-edfb8f2a9915) | Jomo: Good job with the user's own photo tinted by check mark |
| `refs/completion/noom-1.jpg` | [screen](https://mobbin.com/screens/04ff3e32-9b8a-4a80-b661-0235f0b65dcb) | Noom: side-by-side TODAY/ in 30 years with caps labels; serif headline |
| `refs/completion/photoroom-1.jpg` | [screen](https://mobbin.com/screens/581c0f2a-743c-4464-bb1a-c5ac3c2c2625) | Photoroom: before/after as bare slider track with BEFORE/AFTER caps, white thumb, dark canvas |
| `refs/guide/airbnb-1.jpg` | [screen](https://mobbin.com/screens/52b29c50-2480-4676-90fd-ea2eec45befb) | Airbnb What you'll do: rounded photo thumbs with hairline timeline, title + one-line description |
| `refs/guide/blueapron-1.jpg` | [screen](https://mobbin.com/screens/efd46517-8af3-4395-a301-7dfa97375ec2) | Blue Apron: serif step title, STEP 1 OF 5 caps label, large photo |
| `refs/guide/crouton-1.jpg` | [screen](https://mobbin.com/screens/587d65fe-90b9-4730-b9b3-f614f684e5f0) | Crouton: single sentence, quantities highlighted in accent, round next arrow, page dots |
| `refs/guide/hellofresh-1.jpg` | [screen](https://mobbin.com/screens/a8ce2bb8-cecc-423b-aaaf-53e3e00e333a) | HelloFresh step: Step 2 of 6 dots, photo top, timers |
| `refs/guide/ikea-1.jpg` | [screen](https://mobbin.com/screens/721f823b-6416-4e60-a426-379e0bdc9b32) | IKEA: Get ready - 1 of 5 blue overline, bold title, short bullets, black pill Next step; dashed overlay drawn on live view |
| `refs/guide/julienne-1.jpg` | [screen](https://mobbin.com/screens/5ddc1d76-b042-4552-97fb-698b19eb8688) | Julienne cook mode: serif large step, vertical segmented progress at left, Cooking tip, ingredient cards |
| `refs/guide/kitchenstories-1.jpg` | [screen](https://mobbin.com/screens/c0dbae93-8b94-436d-b8fe-789c02841d43) | Kitchen Stories: photo top, tool chip (baking dish), large step text, segmented step bar bottom |
| `refs/guide/ladder-1.jpg` | [screen](https://mobbin.com/screens/2785953e-be22-43b7-97de-c94c3825a05b) | Ladder: thin segmented progress, bottom drawer with item count |
| `refs/guide/peloton-1.jpg` | [screen](https://mobbin.com/screens/ddbad8c8-8a68-4c12-98d5-6475e8e7bb74) | Peloton Strength+: segmented progress bar top, set label, title, full-bleed media card, Next preview row |
| `refs/home/angi-1.jpg` | [screen](https://mobbin.com/screens/fb2b64b1-011a-471e-bea5-092c1a9348cc) | Angi Projects: In progress / Done underline tabs, project card with chevron |
| `refs/home/applefitness-1.jpg` | [screen](https://mobbin.com/screens/94930138-4137-432c-826f-3eeb1bdf45db) | Apple Fitness: ring hero + Move 0/250 CAL typographic pairing, floating glass tab bar |
| `refs/home/collection-applehealth.jpg` | [screen](https://mobbin.com/screens/855294e9-fefb-492f-8073-40ef6e26d351) | Owner collection Apple Health |
| `refs/home/copilot-1.jpg` | [screen](https://mobbin.com/screens/b9f87d05-1926-4b80-97c8-964ed8335b7f) | Copilot: budget rings row, small grey caps section headings with trailing action, rounded white cards |
| `refs/home/empty-angi.jpg` | [screen](https://mobbin.com/screens/3ebf8f26-3f08-4e68-ba7e-2beca00d9e70) | Angi empty state: bold headline, secondary line, single full-width button |
| `refs/home/empty-claude.jpg` | [screen](https://mobbin.com/screens/95d84616-c65e-4722-9042-46764480514f) | Claude empty Projects: tiny icon, grey copy, dark pill New project |
| `refs/home/empty-perplexity.jpg` | [screen](https://mobbin.com/screens/c6ce53ff-7075-42d9-818e-ba26ad51ebfe) | Perplexity empty Projects: one sentence + one pill button |
| `refs/home/flighty-1.jpg` | [screen](https://mobbin.com/screens/939d5aae-4c27-4a32-b91c-767ee82a1845) | Flighty: bottom sheet over full-bleed map, big left-aligned time column, rows with hairline |
| `refs/home/hims-1.jpg` | [screen](https://mobbin.com/screens/338ce5a5-d309-4aca-bc4b-b1c12131a7d0) | Hims home: stepper progress line card with named stages |
| `refs/home/journal-1.jpg` | [screen](https://mobbin.com/screens/bf356291-cee2-4cbf-9ea4-79be184ab05a) | Apple Journal: large title, entry cards, floating plus |
| `refs/home/opal-1.jpg` | [screen](https://mobbin.com/screens/a255c56f-2d49-4ce5-86d4-58e929052ab4) | Opal: large rounded glass cards with image-tinted backgrounds, 2-up grid, floating glass tab bar |
| `refs/home/structured-1.jpg` | [screen](https://mobbin.com/screens/574482d9-3640-4553-805e-944f11f27428) | Structured: sheet over soft header, timeline spine with rounded glyph nodes, circle trailing checkbox, floating glass tab bar |
| `refs/home/things-1.jpg` | [screen](https://mobbin.com/screens/bd7d8522-11cf-44d7-aa6b-ae45d8bb4c68) | Things 3: list with plain rows, no card chrome, tiny icons, hairlines, a single blue FAB |
| `refs/home/things-2.jpg` | [screen](https://mobbin.com/screens/724087de-2e95-47ec-926c-efbdab249a23) | Things 3 Today: section headers with project subtitles under titles |
| `refs/project/airbnb-1.jpg` | [screen](https://mobbin.com/screens/cf0264f7-185c-48c2-9875-78f62ff48bbc) | Airbnb Finish up: large title, grey subtitle, rows with title + status dot (Complete/Required) + chevron. Use for project 'what you need' |
| `refs/project/applefitness-1.jpg` | [screen](https://mobbin.com/screens/5b8d5290-6c52-436f-bac3-9d0a531db829) | Apple Fitness Summary: dark rounded cards, small overline titles with chevron, ring + figure |
| `refs/project/copilot-1.jpg` | [screen](https://mobbin.com/screens/b9f87d05-1926-4b80-97c8-964ed8335b7f) | Copilot: ring-per-item progress row; caps overline labels |
| `refs/project/gentlerstreak-1.jpg` | [screen](https://mobbin.com/screens/d52cd871-49fa-4ccb-b944-cb4a60ffed0d) | Gentler Streak: hero numeral 147 kcal with small caption, map header, floating glass tab bar |
| `refs/project/gentlerstreak-2.jpg` | [screen](https://mobbin.com/screens/0a99f3fb-c1b1-4b14-915c-1498cb8e329a) | Gentler Streak Steps: soft warm gradient halo hero numeral, two-column stats |
| `refs/project/hims-1.jpg` | [screen](https://mobbin.com/screens/338ce5a5-d309-4aca-bc4b-b1c12131a7d0) | Hims: segmented stage progress (Requested/Reviewed/Shipped/Delivered) |
| `refs/project/rocketmoney-1.jpg` | [screen](https://mobbin.com/screens/a5d153d6-fb60-4e2c-a1ab-814d20b19d85) | Rocket Money: white rows with title, one-line explanation, chevron; black pill bottom action |
| `refs/scan/bitepal-1.jpg` | [screen](https://mobbin.com/screens/6aa57cd2-61ec-4a1d-bda4-32c476090dc2) | BitePal camera: circular viewfinder, Meal/Label segmented pill top, My meals pill, thumbnail + shutter + keyboard |
| `refs/scan/bitepal-2.jpg` | [screen](https://mobbin.com/screens/e904fdb7-bc19-486f-9f99-9bd7b0564e1b) | BitePal scanning: thin scan line sweeping circular crop, bottom sheet Checking database |
| `refs/scan/bitepal-3.jpg` | [screen](https://mobbin.com/screens/229c5792-8472-41f0-8255-e82917e6cbe5) | BitePal error: couldn't spot food, Scan again |
| `refs/scan/calai-1.jpg` | [screen](https://mobbin.com/screens/1931911e-97bc-4668-8c50-4dc5516e9c02) | Cal AI scan: corner brackets, 0.5x/1x lens pill, mode tiles, shutter |
| `refs/scan/calai-2.jpg` | [screen](https://mobbin.com/screens/dcf735f6-52fd-4181-bf5e-442065642bb4) | Cal AI privacy interstitial |
| `refs/scan/googlelens-1.jpg` | [screen](https://mobbin.com/screens/fce278a0-4a62-4851-b08e-b667289033c1) | Google Lens: camera becomes result sheet with grabber |
| `refs/scan/googlelens-2.jpg` | [screen](https://mobbin.com/screens/9e251fac-a08c-461b-bad0-b6d66f27b206) | Google Lens: thin arc corners, glass pill mode switcher at bottom, round white shutter with grey ring |
| `refs/scan/greg-1.jpg` | [screen](https://mobbin.com/screens/2641b32c-9c17-4dbd-8472-b2faa345d8a2) | Greg camera: four arc corner marks instead of rectangle, hint pill, vertical glass tool rail, white shutter |
| `refs/scan/locket-1.jpg` | [screen](https://mobbin.com/screens/645891b2-e7c9-4767-9805-974fa3db54ef) | Locket: single camera, glass floating pill nav, ring shutter |
| `refs/scan/phantom-1.jpg` | [screen](https://mobbin.com/screens/b6c3f068-abb6-4a4d-9ed4-f26ae495ca90) | Phantom: minimal rounded bracket corners |
| `refs/scan/ubereats-1.jpg` | [screen](https://mobbin.com/screens/e5793787-0398-4f03-8b7a-dc484b2d5a20) | Uber Eats card scan: thin rounded rectangle frame, white caption sheet below |
| `refs/scan/yuka-1.jpg` | [screen](https://mobbin.com/screens/0809f49a-2a01-465a-b7bb-4d9af26c0ae3) | Yuka scanner: bottom sheet slides over live camera |
| `refs/verdict/bevel-1.jpg` | [screen](https://mobbin.com/screens/44391026-6a4e-4069-88ef-cc7870c17a37) | Bevel: single hero number, one sentence, quiet ring, Next button |
| `refs/verdict/bitepal-1.jpg` | [screen](https://mobbin.com/screens/9cf623e7-3839-4fb5-8192-b910b0ffdbd4) | BitePal result sheet: My meal, item row, Log button |
| `refs/verdict/tide-1.jpg` | [screen](https://mobbin.com/screens/da4b347e-27fc-4dcf-ba96-326b48ea415e) | TIDE: full-screen calm statement typography, one suggestion row |
| `refs/verdict/warbyparker-1.jpg` | [screen](https://mobbin.com/screens/5813f280-ce17-4ca0-9b44-dfcdf6187643) | Warby Parker scan results: sheet with expandable label/value rows, Continue + Rescan |
| `refs/verdict/zopa-1.jpg` | [screen](https://mobbin.com/screens/e129e144-795f-49b5-8b12-93fdc969278d) | Zopa: 'How this loan compares' tinted rows label + bold value; estimate disclaimer under |

