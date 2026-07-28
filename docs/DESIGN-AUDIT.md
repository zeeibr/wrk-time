# Design audit and plan

Four independent audits — visual craft, interaction and platform, accessibility,
and brand — against the running app, the code, and
`docs/design/lane-g-almanac-approved.html`. Findings that two or more auditors
reached independently are marked **[×2]** and should be treated as high
confidence.

Written 26 July 2026, immediately after the app compiled and ran for the first
time.

---

## The verdict, in one paragraph

The thinking here is award-tier and the engine is genuinely excellent. What is
missing is execution against its own thesis. Three things stand out. First, the
app has **functional gaps that no amount of styling would survive**: the screen
sleeps mid-workout, and no finished session is ever recorded, so the growth form
can never grow. Second, **the signature move is barely visible** — the knockout
that justifies the entire design lane is on screen for roughly 5–8% of a work
interval. Third, **accessibility is essentially unimplemented**: four modifiers
in 2,877 lines, a duplicated accessibility tree, and a colour carrying the
smallest text in the app at less than half the legal contrast.

None of this requires abandoning a single settled decision. Several of the fixes
make the constraints *more* true than the current build does.

---

## P0 — Functional bugs

These are defects, not opinions. They break documented behaviour.

> **Status: done, 26 July 2026.** All twelve are fixed, the app builds, and the
> suite is green at 29 tests (26 before, plus three covering the new engine
> behaviour: completed-vs-abandoned, the countdown cues, and that rest never
> ticks). Two deliberate deviations from the recommendations above:
>
> - **The `audio` background mode was *not* added.** It only keeps a process
>   alive while an audio session is genuinely playing, and no audio exists yet,
>   so declaring it now would buy nothing and risk review. It belongs with the
>   audio cue work. `remote-notification` *was* added — CloudKit was emitting a
>   runtime complaint without it.
> - **The phase caption now reads "left of 60 seconds", not "left of sixty
>   seconds".** Interpolating the real duration is the fix; spelling it out at
>   20 Hz needs a formatter that fights Swift 6 concurrency, and every sibling
>   mono label ("ROUND 1 / 8", "13:10 LEFT") already uses digits. Worth a second
>   opinion — it is a small voice change.

| # | What | Where | Why it matters |
|---|---|---|---|
| 1 | **The screen sleeps mid-workout.** Nothing sets `isIdleTimerDisabled` anywhere. | `WorkoutTimerView.swift` `.onAppear` | The display locks during round one. Field register gone, ticker suspended, haptics stopped. Total failure of the stated use case — phone on the floor. |
| 2 | **No session is ever recorded.** `HealthSync.record(session:start:end:)` and `SavedRoutine.lastRunAt` have **zero callers**. | `HealthSync.swift:37`, `Store.swift:68` | `completedAt` is never set, so `completedCount` is permanently 0. HANDOFF §3 rule 3 ("one mark is one finished session") is unimplemented. The growth form can never grow and Today says "Day one" forever. |
| 3 | **End and Skip render invisible.** `transport(foreground:)` declares a parameter it never reads; `FieldButton` hard-codes field colours. | `WorkoutTimerView.swift:172`, `Components.swift:165,172` | In the base layer these draw **oat on oat at 1.00:1**. The field drains past the transport row at ~15% remaining, so both controls vanish in the final ~9 seconds of every work interval — exactly when you reach for them. |
| 4 | **Live Activity freezes.** No `UIBackgroundModes`, so the process suspends and `update` is never called again. | `project.pbxproj` | The lock screen sits on a stale phase, still labelled "Work", for the rest of the session. |
| 5 | **The Live Activity drain bar never moves.** `remainingFraction` is evaluated once at render; ActivityKit only re-renders on push, and you push once per phase. | `WorkoutActivity.swift:36`, `WorkoutLiveActivity.swift:115` | A frozen bar beside a running clock. Fix is `ProgressView(timerInterval:)` — *more* of the one-push-per-phase idea, not less. |
| 6 | **Pause is invisible to the lock screen.** `ContentState` has no paused flag and `update` is only driven by `currentPhase`. | `LiveActivityController.swift:33` | Pause the workout and the lock screen keeps counting to zero. |
| 7 | **Success chime for quitting.** `end()` fires `onFinish` → `sessionComplete()` regardless of reason. | `IntervalEngine.swift:139` | The app congratulates you for abandoning a workout. Inverse of the voice rule. |
| 8 | **`countdownTick()` is dead code.** No call site. **[×2]** | `Haptics.swift:29` | The file's own header calls this the reason the app works face-down on the floor. There is no last-3-seconds cue of any kind. |
| 9 | **The marginal index draws on top of itself.** `rotationEffect` doesn't change layout bounds. **[×2]** | `Components.swift:33` | Visible in the current build — "01" is struck through by "SESSION" on every section. |
| 10 | **`"left of sixty seconds"` is hardcoded.** **[×2]** | `WorkoutTimerView.swift:197` | The builder allows work from 10s. A 30-second interval displays and announces "sixty". |
| 11 | **"Drag to reorder" is a lie.** No `.onMove`, not in a `List`. | `RoutineBuilderView.swift:136` | The copy promises an interaction that does not exist. |
| 12 | **No `Assets.xcassets` at all**, but two build settings reference `AppIcon` and `AccentColor`. | `project.pbxproj` | There is no app icon, and anything untinted falls back to **system blue** — a colour that appears nowhere in this design. |

---

## P1 — The signature

The register change is the entire claim to originality, and it is currently the
weakest-performing part of the app.

**The knockout is almost never on screen.** Both the visual and interaction
auditors computed this independently and agreed: the numeral sits in the top
~18% of the screen while the boundary traverses all of it, so the boundary
crosses the digits only between roughly 83% and 93% remaining — about **4.6 to
6 seconds of a 60-second round**. For the other ~54 seconds the screen is a dark
rectangle with a number in the corner, and the boundary is a bare horizontal
line crossing nothing, which reads as a progress bar. During rest it never
happens at all. **[×2]**

The approved mockup avoids this by knocking out *the entire screen* — pips, top
row, move name, next line, and all three buttons — so the boundary is always
cutting through something.

Two candidate fixes, not mutually exclusive:

- **Redistribute the field content** across the boundary's travel path (the
  mockup's approach): move the numeral down, add the round pips high, keep the
  foot block anchored. Target content occupying ≥75% of the travel.
- **Let the numeral ride the waterline** — bind its vertical offset to
  `1 - phaseRemainingFraction`. The knockout then holds for 100% of the
  interval, *and* the numeral's position becomes a second, pre-attentive
  readout you can read across a room without resolving digits. It also
  disambiguates work from rest for free: in work the numeral descends, in rest
  it is parked and perfectly still.

**Work and rest look nearly identical.** Same ground, same type colours; the
discriminators are an 11pt mono caption and a waterline position you can't judge
without a reference. Worst in the first seconds of work — exactly when you need
to know the round started.

**Rest is 60% empty screen.** `currentPhase?.move` is nil during rest so the
whole move block vanishes, and the one thing rest is for — knowing what's next
so you can set up — is a 10pt line at the very bottom. Promote `nextPhase.move`
into the vacant slot.

**There is no way in and no way out.** The register change is currently
performed by UIKit's stock modal slide-up, and the field is already at full
height when the cover arrives, so there is nothing to see. At the other end,
completion is an unhandled state whose saffron button **restarts the entire
13-minute routine** (`toggle()` → `.finished` → `start()`). The mark being drawn
onto the growth form is the payoff for the whole app, and it is wired to
nothing.

**The two-layer construction is fragile.** It depends on two independently
laid-out copies of a text tree agreeing exactly, forever, under every Dynamic
Type size and locale. Consider collapsing to a single layer with a two-hard-stop
gradient foreground (`.knockout(waterline:)` as a design-system primitive) —
exact by construction, one text tree, no mask pass, and it cannot ghost.

---

## P2 — Accessibility

Four accessibility modifiers in the entire codebase. Zero references to
`accessibilityReduceMotion`, `colorSchemeContrast`, `dynamicTypeSize`,
`ScaledMetric`, `differentiateWithoutColor`, or `minimumScaleFactor`.

**The good news first: the knockout is contrast-clean.** 14.14:1 above the
boundary, 14.13:1 below — AAA on both grounds, differing by 0.01. The signature
needs no softening whatsoever.

### Contrast, computed from the actual hex values

Document register, ground = oat `#E9E5D9`:

| Foreground | Ratio | AA 4.5 | Verdict |
|---|---|---|---|
| ink `#0F1A15` | **14.14** | PASS | AAA |
| moss `#35513F` | **6.95** | PASS | |
| mute `#4A6252` | **5.28** | PASS | |
| **sage `#8FA894`** | **2.03** | **FAIL** | Below even the 3:1 non-text floor |
| saffron `#D9A227` | **1.82** | **FAIL** | |

Field register, ground = field `#101A14`: oat 14.13, saffron 7.75, sage 6.95 —
all pass. **The palette is not broken; exactly one colour is, on exactly one
ground.**

### The blockers

1. **The accessibility tree is duplicated. [×2]** `.mask()` clips pixels but does
   not prune the tree, so VoiceOver reads every timer screen twice — two
   countdowns, two Pause buttons, two End buttons — and Switch Control scans six
   transport controls instead of three. Fix: `.accessibilityHidden(true)` on the
   field-layer `ZStack`. **One line.**
2. **Sage carries body text at 2.03:1 in nine places. [×2]** Equipment specs
   ("15 LB BALA BEAM") — the only place the user learns what to pick up. The
   handoff's own rule says sage "does not clear 4.5:1"; it actually misses by
   **2.2×**. Fix: route all nine through `Register.secondary`, which already
   resolves to `mute` (5.28:1) on oat and keeps sage (6.95:1) on field. No new
   token, no change to the field register.
3. **Nothing scales with Dynamic Type except the slab. [×3]** `Face.ui` and
   `Face.mono` use `.system(size:)` with no `relativeTo:`. At AX5 the headings
   grow ~3× while body, buttons and labels stay frozen — the hierarchy inverts.
4. **No Reduce Motion path.** A full-height hard edge sweeps the screen
   continuously for 60 seconds — a classic vestibular trigger. The fix is
   already written: hold the field still during work, exactly as rest does.
5. **Work vs Rest in the Dynamic Island is hue-only at 1.12:1.** Two 8pt dots of
   near-identical luminance. Encode it in shape, not just colour.

### Also

Six unlabelled 24pt stepper buttons (fails Apple's 44pt bar by 45%, VoiceOver
reads "minus, plus" six times); the saved-routine row is an `.onTapGesture` on a
`VStack` so three assistive technologies can't reach it; no `.isHeader` traits
anywhere so the Headings rotor is empty on every screen; the growth form's label
is attached to a non-element; and End session is one unconfirmed tap that
destroys an unrecoverable session.

---

## P3 — Brand

### The name should change to **Almanac**

"WrkTime" names a stopwatch; the product is a seasonal planner with a stopwatch
in it. Vowel-dropping signals *grind*, sitting on top of a product whose entire
argument is *don't grind*. And "work time" is employee-surveillance search
territory.

**The approved design has already named the product.** The mockup prints
`ALMANAC` as the masthead on three screens, the field side rail reads
"Almanac · session 06 · day 12 of 84", and the Live Activity title is
"Almanac · work".

**The rename is nearly free:** `WrkTime` appears in **zero user-facing strings**
— only type names, folders, and bundle IDs. You do not need to rename the
target, the folder, or a single Swift type. One Info.plist key.

The App Store name must be globally unique and "Almanac" is taken (one of them
in Health & Fitness). Standard split: store name
`Almanac: Interval Training` (26/30), `CFBundleDisplayName` = `Almanac`.

### The icon does not exist — recommended concept: **The Cut Ring**

Oat paper ground; one eccentric ring from `GrowthForm.ringPath`, ink, 46px
stroke; the bottom 38% a solid ink field block; the ring re-stroked in oat
inside that block so it is **one continuous form cut by the boundary** — exactly
as the timer numeral is. One saffron radial notch with a terminal dot at ~1
o'clock. Ink seed at the centre.

It states both halves of the product at once: the growth form and the register
change. **The icon is week one of your season.** The dark variant inverts the
registers — the photographic negative of the light one, which restates the
product's central idea. Three flat values plus one accent, so it tints cleanly
where gradient icons turn to sludge.

Against a Health & Fitness grid that is overwhelmingly dark and saturated, a
pale oat tile is a hole punched in the page.

### Brand fixes in code

- **The masthead is missing from every screen. [×2]** The `ALMANAC` running head
  and firm rule from the mockup were dropped in the build. The brand is
  currently on zero screens. ~6 lines.
- **No numeral anywhere is set in the slab. [×2]** `almanacCount` is
  `Face.ui(size, .light)` — SF Pro. The mockup sets *every* figure in
  Superclarendon and reserves the grotesk for controls; the implementation
  inverted that. The count is the largest mark in the product and it currently
  looks like any timer in the store. Repointing it is one line for the largest
  brand return on this list.
- **`AccentColor` must be ink, not saffron.** If saffron becomes the global
  accent, every default control turns saffron and "saffron means live" dies
  within a week.
- **Add `saffronInk #9A7112`** for saffron that has to be *read* — saffron on oat
  is 1.82:1. The mockup already contains this value; promote it to the palette.
  Rule: saffron is a fill or a stroke; `saffronInk` is saffron you read.
- **No red, ever.** When the app reports something off, that is type's job, not
  colour's. The voice never alarms.

### The growth form is the most ownable asset, and every season looks identical

`ringPath` seeds its distortion from the week index alone, so week 3 of your
Block I, week 3 of Block II, and week 3 of anyone else's block are the same
curve. The doc comment claims "**your** season"; the determinism is right but
the identity isn't there.

Fix in ~6 lines: derive a `seed: UInt64` per block from start date + goal +
starting weight, and mix it into the phase. That single change turns the form
from a stable decoration into a portrait — and into something worth sharing.

Then: notch length proportional to session duration; a **dotted** ring for a
past week with zero marks (says "this week was quiet", not "you failed" — the
voice expressed as geometry); and the end-of-block **plate**, a tall rendered
almanac page with the finished form, three figures, and one slab line in the
app's voice. That is the artifact someone actually posts, and the reason they
start Block II.

---

## Progress, 26 July 2026

All four phases have been worked. Build is green and the suite is at 29 tests.

**Done.** Every P0 defect. The accessibility blockers: the duplicated
accessibility tree, sage retired from all nine document-register sites
(2.03:1 → 5.28:1), Dynamic Type scaling on `Face.ui`/`Face.mono`, a Reduce
Motion path, the saved-routine Button, adjustable steppers with 44pt targets,
header traits, and combined labels on rows, buttons and the growth form. The
signature: the count now rides the boundary, so the knockout holds most of the
interval rather than about five seconds of sixty; rest shows what is coming
instead of leaving its middle empty; and there is a real completion screen that
states what happened and stops — which also removed the button that restarted a
thirteen-minute routine. Brand: renamed to Almanac, the masthead is back on
every document screen, the count is set in Superclarendon, `saffronInk` exists
and today's mark uses it (differentiated by form, not colour alone), the growth
form is seeded per block so one season's drawing is not another's, and the app
icon — the Cut Ring — now exists in light and dark.

Also, not from the audit: the launch screen was generated white against an oat
app, which read as a flash of the wrong app while the CloudKit-backed store
opened. It is now the app's own ground.

**Also done, in a second pass.** The entry choreography: the ground now rises
through a document that does not move, inverting the numeral as it passes, then
holds for a three-second lead-in counted in the same ticks that later mark the
end of a round — the motif is the point. Today's growth form is the mockup's
thumbnail beside dotted-leader figures rather than an oversized hero. Week
derivation is calendar-based and marks bin by the week they were actually
finished in, so a quiet week is finally representable (H7). The counters row was
pinched between two hairlines — padding now sits inside the rules — and "13:15"
is no longer labelled MINUTES. The Timer tab has its masthead.

Walks recorded by Whoop, the Watch or the phone are now read (`walks(since:)`),
filtered to exclude anything this app wrote. They are context for the planner and
**never** marks: a mark is a finished planned session, and a walk Whoop logged is
not one.

**Audio now exists**, which closes the largest usability gap in the audit.
`SessionAudio` synthesises its cues rather than shipping sample files — decaying
sines with a little second harmonic, so they read as wooden rather than as an
alarm — and `SessionCues` binds felt and heard cues together as one vocabulary
instead of letting two callers fight over the engine's single-assignment
closures. The session is `.playback` with `.mixWithOthers`, so music keeps
playing straight through a workout.

`.duckOthers` is deliberately **not** set: it ducks for as long as the session is
active rather than only while a cue sounds, so a whole workout would play under
dipped music. If cues turn out to be lost under a loud mix, that is the dial to
turn — at the cost of the music dipping for the entire session.

The app also does not claim `MPNowPlayingInfoCenter` or `MPRemoteCommandCenter`,
so the Lock Screen, Control Centre and AirPods controls keep driving Spotify.
That is the closest thing to "music controls in the app" that iOS permits:
there is no public API to control another app's playback, and Spotify's own SDK
would need OAuth, which HANDOFF §2 rules out.

Because `.playback` sounds through the silent switch, there is a mute control in
the timer header as well as in settings — one findable during a session, one
findable when looking for it.

**Settings, backup and the API key.** There is now a settings sheet, reached
from the Today masthead. It holds the cue toggle, backup and restore, and the
Claude API key. `KeychainStore` keeps the key with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — encrypted at rest, excluded
from backups, never synced, never logged, and never read back into the UI once
saved. `Archive` exports the whole store as readable JSON and deliberately does
not carry the key. Restore **merges on identifier** rather than replacing, so
restoring the same file twice adds nothing and restoring an old file cannot
delete newer work.

**Loose sets.** Reps done off the plan can be kept — `LoggedSet`, entered from
Today, with the load picker offering only the weights that exist
(`availableLoadsPounds`). They are deliberately **not** marks. Rule 3 stands: if
twenty squats in the kitchen drew on the growth form, the form would stop
meaning "I did the plan" and become a general activity log. The section states
this in the open — "10 reps · no mark" — so the two counts can differ without
looking like a bug. They are volume the planner should see, and they are carried
in the backup.

**Haptics are a vocabulary now.** Pause is one soft press; resume is the lead-in
motif foreshortened to two quick taps; skip is firm-then-light, a shove and a
settle, so it feels like travel rather than like a button. The two actions with
the most different consequences no longer feel identical. Every generator is
warmed, including the notification one.

**Increase Contrast is handled.** `rule`, `ruleFirm` and `ruleOnField` each have
a raised variant — 3.49:1, 4.88:1 and 4.41:1 — and `Rule` and `FieldButton` read
`colorSchemeContrast`. The field button's ring matters most: it is a control
boundary rather than decoration, so it has to clear 3:1 when asked. Verified
with `simctl ui booted increase_contrast enabled`. Hairlines darken rather than
thicken, so the document keeps its weight.

**Settings says when you last saved a backup** — "Saved today", "Saved 9 days
ago", "Never saved". Stated, not nagged.

**Still not done.**

- **The cue tones are unheard.** They were written to spec and never listened
  to. Pitches, levels and decay all want a real ear before they are trusted.
  This is the single most likely thing in the app to be subtly wrong.
- **Haptics use `UIFeedbackGenerator`, not CoreHaptics.** The patterns are
  distinct and correct, but the continuous ramp for skip, and true intensity
  control, need CoreHaptics. Deliberately deferred: it cannot be verified
  without a device, and an engine that throws at session start would cost more
  than the refinement is worth.
- **No `LiveActivityIntent`**, so the lock screen is still read-only.

  This was previously filed alongside "dismissal destroys a session", on the
  theory that both wanted the engine hoisted into an app-level coordinator.
  Testing the second claim showed it was the wrong diagnosis twice over. The
  timer is a `fullScreenCover` with no interactive dismiss, so it cannot be
  swiped away at all — and the real loss was **process termination**, which an
  app-level coordinator would not have survived either, because it dies with
  the process.

  Demonstrated: a session at round 1 of 8 with 10:17 left, terminated and
  relaunched, came back as an untouched Today screen. The fix was persistence,
  not architecture — see `ActiveSession`. `LiveActivityIntent` remains genuinely
  outstanding and still wants a coordinator, but it is now the only thing that
  does, and it is not worth doing unverified on a device.
- **The planner has never been run against the live API.** It is built and
  tested — `ClaudePlanner` (raw HTTP against `/v1/messages`, `claude-opus-5`,
  structured outputs), `PlanValidator`, and a deterministic `OfflinePlanner` —
  but every path has so far been exercised through the offline fallback,
  because no key was set. The response handling is covered by tests against
  recorded response shapes rather than real ones. The first real call is the
  thing left to verify, and the failure it would most likely expose is the
  schema being rejected, not the plan being wrong.
- **The watch app** remains as HANDOFF §4 left it. Season and Signals are now
  built: Season gives the growth form the fold it was denied on Today, with a
  week-by-week table whose squares are the same vocabulary as the notches on
  the form; Signals pairs every reading with what the plan does about it, and
  says "the plan holds" when nothing came through rather than filling the gap.

  Onboarding now exists in the one place it was actually load-bearing:
  `BlockSetupView` asks for the starting weight, the goal, an optional target
  date and the pace. It replaced a seed that opened the app with
  `goalWeightPounds: 148, startingWeightPounds: 168.4` — numbers nobody had
  entered, presented as hers.

### Pace, and the thing it deliberately does not claim

`Pace` (steady / building / hard) changes session count and how fast rest
shortens and rounds climb. It does **not** claim to change how fast the scale
moves, and the copy says so at the point of choosing: with thirteen-minute
sessions and 2–15 lb kit, the energy balance is not decided in the sessions.
Selling that dial as a fat-loss lever would have been the easy build and a
false one.

**Walking is the one exception, and it is deliberate.** `walkMinutes` is the
only part of a generated week set with the goal weight in mind, because it is
the only training lever that meaningfully affects energy balance — thirteen
minutes of intervals do not. It is bounded (`PlanValidator.walkCeiling`, 300 a
week), climbs by at most ten minutes a week offline, and is stated on Signals
next to the sentence that says plainly which lever moves the scale. Intake is
never prescribed: the app names walking and the eating window she set, and
stops there.

The same rule governs `Projection`. A target date is a request: if it needs
more than one percent of body weight a week, the date moves and the reason is
stated once, rather than the app drawing a steeper line it cannot support.

## Phased plan

**Phase 0 — bugs (do first, none are design decisions)**
P0 items 1–12. Roughly: `isIdleTimerDisabled`, wire the completion path so
sessions are recorded, thread `foreground` through the transport, background
audio mode, `ProgressView(timerInterval:)` in the widget, paused state in
`ContentState`, `end(reason:)`, wire `countdownTick`, fix the rotated index,
interpolate the caption, remove the false "drag to reorder", create
`Assets.xcassets`.

**Phase 1 — accessibility blockers**
`.accessibilityHidden(true)` on the field layer (one line, fixes the largest
single defect in the app). Retire sage as a document foreground — nine sites
through `Register.secondary`. Scale `Face.ui` / `Face.mono`. Reduce Motion path.
Real labels and 44pt targets on the builder controls.

**Phase 2 — the signature**
Re-choreograph the field so the boundary always cuts something. Give rest a job.
Design the way in (field rises through a still document, then a 3-second lead-in)
and the way out (field recedes, summary, the new mark traced onto the form).
Build the haptic language as a system rather than five one-offs, and add the
audio channel — it is the only cue that survives the phone being face-down with
the screen off.

**Phase 3 — brand**
Rename to Almanac. Build the Cut Ring icon in three variants. Restore the
masthead. Repoint the count to Superclarendon. Add `saffronInk`. Seed the growth
form per block.

**Phase 4 — after the planner and onboarding land**
Commit `docs/VOICE.md` and wire it into the planner's system prompt — HANDOFF §8
already requires the planner to explain changes "in the app's voice", so the
guide is a functional input, not just documentation. Then the end-of-block plate,
the plates archive, and home-screen widgets carrying the form.

---

## What must be protected

Every auditor independently flagged the same things as genuinely good. Do not
let a refactor take them.

- **The `Register` abstraction.** A single environment value deciding which world
  a surface is in, with views reading `register.primary` rather than hard-coding.
  It is why Increase Contrast, dark mode, and the sage remediation are each a
  change to *one enum* rather than forty views. Real architectural foresight.
- **The engine's derived-time architecture.**
  `elapsed = now − start − paused + skipOffset` against a precomputed schedule,
  clock injected, `autoTick: false` for tests. Every recommendation above is
  downstream of this property. Don't let a display refactor leak a stored
  counter back in.
- **One Live Activity update per phase.** The date-bounds contract is correct.
  The frozen drain bar is not a counter-argument — the fix is *more* of the same
  idea.
- **`.linear` for the drain.** It represents elapsed time; easing it would be a
  lie about the clock. The problem was only ever applying that same 50ms curve
  to the phase-boundary jump.
- **Rest holding the field still.** A motion decision made for emotional reasons
  that happens to be exactly the hook Reduce Motion needs.
- **The count rounds up**, so "0:01" holds for its whole final second and the
  display never claims less time than you have.
- **Monospaced digits**, and **hairlines at `1/displayScale`**.
- **The 60-second ceiling enforced in the model, not the UI.**
- **The voice.** "rest — walk it off". "A rest day is part of the plan, not a gap
  in it." The 7-day mean instead of this morning's number. `projectedDate`
  returning nil rather than lying with arithmetic. This is the hardest property
  in the app to retrofit and it is already right. Every string added for empty
  states, onboarding and the planner must match it exactly.
