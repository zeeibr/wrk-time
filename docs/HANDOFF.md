# Handoff

Everything a new person — or a new session — needs to pick this up. Written
after the second milestone; state and planner sections updated 27 July 2026,
once the app was running on a real phone and the planner had reached the live
API.

---

## 1. What this is

An iOS interval workout timer and fitness planner, built for one person and
one specific set of equipment. Claude generates an adaptive multi-week program;
the user runs it against a drift-free interval timer; weight and recovery come
in from Apple Health and steer the next week's plan.

**The equipment is the whole constraint.** Two 2 lb dumbbells, one 15 lb Bala
Beam, three Bala rings at **5, 8 and 10 lb — three separate items, used one at a
time**, not a matched set — a walking pad, and bodyweight. Nothing else exists
as far as this app is concerned, and `Equipment` in `WrkTime/Model/Equipment.swift` is a
closed enum specifically so no generated plan can quietly assume otherwise.

The user is new to fitness and works in intervals capped at **60 seconds**.
That ceiling is clamped in the model (`IntervalRoutine.workCeiling`), not in
the UI, so nothing downstream can exceed it.

---

## 2. Decisions already made

These were settled with the user directly. Do not re-litigate them without
asking.

| Question | Decision |
| --- | --- |
| How the app reaches Claude | User's own API key, stored in the iOS Keychain, called from the device. No backend. |
| Audience at launch | Just the user, via TestFlight — but built to App Store standard. |
| Weight input | HealthKit read (Loftilla writes to Health) plus manual entry. |
| Recovery input | HealthKit, not the Whoop API. Whoop already writes sleep, HRV and heart rate to Health, so this is the same data with no OAuth and no token refresh. |
| Platforms | iPhone, Live Activity + Dynamic Island, and an Apple Watch standalone runner. |
| AI scope | Adaptive multi-week program, re-planned weekly from weight trend and recovery. Not one-off workout generation. |
| Persistence | SwiftData, synced through the user's private CloudKit database. |
| Fasting | **Demoted.** Started as a headline feature with a functional-medicine lens; the user later cut it back. Stats stay visible, but it gets no tab and no hero screen — one cell on Today, one module on Signals, and an input to the projection. |
| Functional-medicine lens | Circadian timing, sleep and recovery, stress load, minerals and hydration. Framed as education, never medical advice. |
| Profile data | Entered by the user in `BlockSetupView` on first run. It previously opened with an invented starting weight and goal; that seed is gone. |
| Design lane | **G, "Almanac."** |
| Intensity | One dial, `Pace` — steady / building / hard. It changes sessions per week and how fast load climbs. It is **not** allowed to claim it moves the scale faster; see §9. |
| Which lever moves the scale | Walking volume and the eating window she set. Stated plainly on Signals. The app never prescribes intake. |
| Disliked moves | Recorded, not hard-coded. She said "deweight things like pushups i dont like those", so push-ups ship as a seeded *preference* she can undo, not as a hole in the library. |
| After a skipped move | Asked why, once, at the end — hurt / disliked / too hard / no room / no time. The answer changes next week's plan. Never asked mid-set. |
| Flow work | Qi gong and lymphatic movement are in the kit as `.flow`, kept out of work intervals. Two named YouTube sequences are still to be matched. |

### How the design was chosen

Three rounds, all preserved in `docs/design/`:

1. **Round two** (`round-two-six-lanes.html`) — six directions: Interval,
   Meridian, Baseline, Signal, Season, Coach.
2. The user kept **C Baseline** (clean), **D Signal** (its timer and lock
   screen), and **E Season** (its presentation of everything else).
3. **Round three** (`round-three-syntheses.html`) — three syntheses of those
   three. The user approved **G, Almanac**.

`lane-g-almanac-approved.html` is the approved mockup on its own: five screens
at true iPhone size. Open it in a browser; it is self-contained.

---

## 3. The design idea, and why it must not be softened

Almanac has **two registers**, and the switch between them is the entire point.

- **Document.** Oat ground, ink type, moss hairlines, a slab serif. Today,
  Season, Signals — screens you *read*.
- **Field.** The moment a set starts, the ground inverts. A dark field rises
  from the bottom to the height of the time left in the interval, and the count
  is knocked out of the boundary: ink on oat above the line, oat on field
  below, one continuous numeral cut by the edge.

`Register` in `Shared/Palette.swift` is the single value deciding which world a
surface is in. Views read it; they do not hard-code colours.

Four rules the code enforces, inherited from the mockups:

1. **Saffron means live.** A running round, and today's mark on the growth
   form. Never a button that isn't running yet.
2. **Sage never carries body text.** It does not clear 4.5:1 on oat.
3. **One mark is one finished session.** A session started and abandoned earns
   nothing — `PlannedSession.completedAt` is the only thing that counts.
4. **Fasting is an input, not a feature.** See the table above.

---

## 4. State of the build

Updated 27 July 2026, after the app was compiled, run on the simulator, run on
a physical iPhone, and driven against the live Claude API for the first time.

| Area | State | Where |
| --- | --- | --- |
| Design system — palette, type, components | Built | `Shared/`, `WrkTime/DesignSystem/` |
| Interval engine | Built, tested | `WrkTime/Timer/IntervalEngine.swift` |
| Routine schedule maths | Built, tested | `WrkTime/Timer/IntervalRoutine.swift` |
| Workout timer screen — the register change | Built | `WrkTime/Timer/WorkoutTimerView.swift` |
| Routine builder — compose and save your own | Built | `WrkTime/Timer/RoutineBuilderView.swift` |
| Growth form — generative season rings | Built | `WrkTime/Today/GrowthForm.swift` |
| Today screen | Built | `WrkTime/Today/TodayView.swift` |
| SwiftData models, CloudKit sync | Built | `WrkTime/Model/Store.swift` |
| HealthKit reads and workout write-back | Built | `WrkTime/Health/` |
| Weight trend and goal projection | Built, tested | `WrkTime/Health/HealthSync.swift`, `WrkTime/Model/Projection.swift` |
| Live Activity and Dynamic Island | Built | `WrkTimeWidgets/`, `WrkTime/Timer/LiveActivityController.swift` |
| Block setup — weight, goal, target date, pace | Built | `WrkTime/Today/BlockSetupView.swift` |
| Claude planner + deterministic fallback | Built, tested, **live** | `WrkTime/Planner/` |
| Weekly re-planning for weeks 2–12 | Built, tested | `WrkTime/Planner/PlannerService.swift` |
| Season screen | Built | `WrkTime/Today/SeasonView.swift` |
| Signals screen | Built | `WrkTime/Today/SignalsView.swift` |
| Projection chart (from the approved mockup) | Built | `WrkTime/Today/ProjectionChart.swift` |
| Eating window editor, manual weigh-ins | Built | `WrkTime/Today/EatingWindowView.swift`, `WeighInView.swift` |
| Interrupted-session recovery | Built, tested | `WrkTime/Timer/ActiveSession.swift` |
| Move preferences and skip reasons | Built, tested | `WrkTime/Model/MovePreference.swift`, `WrkTime/Today/SkipReviewView.swift` |
| Backup and restore | Built | `WrkTime/Model/Archive.swift` |
| Flow work — qi gong and lymphatic | Built | `MoveLibrary.flow` in `WrkTime/Model/Equipment.swift` |
| Flow warm-up on every session | Built, tested | `WrkTime/Model/WarmUp.swift` |
| Timer-only routines — no moves | Built, tested | `WrkTime/Timer/RoutineBuilderView.swift` |
| Move diagrams — drawn stick figures | Built, tested | `WrkTime/DesignSystem/MoveDiagram.swift`, `WrkTime/Today/MoveSheet.swift` |
| **Watch app** | **Not started** | — |
| **`LiveActivityIntent`** | **Not started** — lock screen is read-only | — |
| Cycle-aware programming | Deliberately not built — opt-in only, awaiting her decision | — |

90 tests in 14 suites. Builds and runs on the iPhone 17 Pro simulator and on a
physical iPhone 17 Pro.

### What is still unverified

**The audio cues and the haptic vocabulary have never been heard or felt.**
They were written to spec and the app only reached a physical device on
27 July. This is the most likely thing to be subtly wrong.

**CoreHaptics** is not used: the patterns are distinct via `UIFeedbackGenerator`,
but the continuous ramp for skip and true intensity control need CoreHaptics and
were not worth writing blind.

The hand-written `WrkTime.xcodeproj/project.pbxproj` opened and built without
incident, and uses file-system synchronized groups — new files under `WrkTime/`
are picked up without editing it. It remains the artifact most worth being
careful around.

---

## 5. What the first live API call taught us

The planner worked on the first request in the sense that it returned HTTP 200,
and did not work in every sense that mattered. Four things had to change, and
they are recorded here because each would cost hours to rediscover.

**`fallbacks: "default"` silently breaks structured outputs.** Server-side
refusal fallback is the documented default for Opus 5 and was set. With it on,
every response was schema-valid and hollow — zeroed integers, empty strings,
`moves: []`, once with a genuinely well-written explanation attached to a week
containing one empty session. Removing `fallbacks` and its beta header, changing
nothing else, produced a full correct week on the next call. See the comment in
`ClaudePlanner`. If it is ever restored, re-test the structured output first.

**`effort: "medium"` was a false economy.** It returned unusable weeks, so the
request was spent *and* the plan still came from the offline planner. `high` is
the documented floor for intelligence-sensitive work on Opus 5.

**JSON Schema `minItems` is not supported by structured outputs.** Asking in
prose for four sessions of three moves produced two sessions, then one with an
empty rotation — and the repair turn, handed its own rejected answer, produced
the same thing again. The fix is structural: *required named properties*
(`one`/`two`/`three`/`four`, `first`/`second`/`third`) make the invalid state
unrepresentable, where an array bound cannot.

**Inlining a repeated sub-schema blows the grammar limit.** Twelve copies of the
move object in one schema returned `"The compiled grammar is too large"`. The
shapes live in `$defs` and are referenced.

The remaining failure mode is a *stubbed* session — the model fills the slots it
has something to say about and pads the rest onto a duplicate day with moves
named "placeholder". `PlanValidator` catches both signals.

---

## 6. Provisioning, as actually configured

Settled 26–27 July and no longer guesswork:

- **Team** — Zeemara Ibrahim. Signs with an Apple Development profile.
- **Bundle identifiers** — `com.zee.wrktime`, `.widgets`, `.tests`.
- **CloudKit** — `iCloud.com.wrktime.app`, named in both
  `WrkTime/WrkTime.entitlements` and `Store.cloudKitContainerIdentifier`;
  change both together. Sync is behind the `CLOUDKIT_SYNC` compilation
  condition, which is **on**.
- **App group** — `group.com.wrktime.app`, in both entitlements files.
- **Still outstanding on the developer account:** Background Modes → Remote
  notifications, and Push Notifications. Also worth setting a spend limit on
  the Claude API key.

The key itself lives only in the Keychain as
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — it is not in the repo, not in
the app's own backup file, and does not sync. A device and a simulator each
need it entered separately, by hand; that is the design, not an oversight.

---

## 7. Architecture notes worth knowing

### The interval engine

It never accumulates decrements. It records when the routine started and how
long it has been paused, then derives everything from

```
elapsed = now − start − pausedTotal + skipOffset
```

against a precomputed `RoutineSchedule`. A dropped frame, a slow tick, or the
app being backgrounded for ten minutes cannot make the count wrong — the next
`refresh()` simply reports the truth.

Time is injected (`now: () -> Date`), and `autoTick: false` disables the live
ticker, so tests drive the clock by hand and never sleep. **If you change this
file, keep both properties.** They are the reason the tests can assert exact
values.

### The Live Activity

The widget is handed the phase's start and end *dates*, not a countdown value,
and renders its own live timer from them. That means one update per phase
change rather than one per second — both what the system permits in the
background and the only way the lock screen stays correct while the app is
suspended. Do not "fix" this into a per-second push.

### Health

Everything the app reads is written by something else — Loftilla writes body
mass, Whoop writes sleep and heart rate. The app only reads, and writes back
completed workouts. `HealthService` is a protocol with a `StubHealthService`,
so the planner and projection can be tested without a device.

---

### Interrupted sessions

A session that was running when the process died is recoverable. This was
demonstrated broken first: a session at round 1 of 8 with 10:17 left, killed
and relaunched, came back as an untouched Today screen.

Note the diagnosis that was *wrong*: the audit filed this alongside
`LiveActivityIntent` on the theory that both wanted the engine hoisted into an
app-level coordinator. The timer is a `fullScreenCover` with no interactive
dismiss, so it cannot be swiped away at all — and a coordinator would have died
with the process anyway. The fix is persistence (`ActiveSession`), not
architecture. Resuming is cheap precisely because the engine derives everything
from wall-clock time: there is no accumulated per-tick state to rebuild.

A session the clock outran while the app was closed is **discarded, not
counted**. The app must not decide on her behalf that she finished.

### The warm-up

Every session opens with three to five flow movements. They are **additive** —
never a round removed, never a work interval shortened — and they are built by
`WarmUp` in `PlannerService.write`, not by either planner. Two reasons: every
week gets one whether Claude wrote it or the offline planner did, and it costs
no schema budget on a decision with one correct answer.

`Phase.Kind` gained a third case rather than a flag on `work`, because nearly
everything that happens at a boundary asks this question: the field holds still
through flow, no countdown is cued into it, the cue is the softest in the
vocabulary, and it is not a round. A boolean would have had to be checked in
all of those places and would have been missed in one.

The practice rotates by calendar day, stepping the window by one more than its
own width — stepping by the width exactly would give `library / width` distinct
practices, and twelve movements taken four at a time would mean every Thursday
opened like every Monday.

### Move plates

A move is drawn as a **strip**: two or three panels side by side, a hairline
between them, one floor line running under all of them. The strip is the
motion. There is no arrow, no dashed arc and no ghost figure — the first
attempt had all three and every one was off-brand, because dashed means
*projected* elsewhere in this app, arrowheads mean *proceed*, and a 40%-alpha
ghost sits under the 3:1 floor `Palette` sets for non-text.

Five things worth not undoing:

- **The stroke is 1.1pt at every size.** The first version scaled the line with
  the frame and rendered from 0.73pt in a row to 3.83pt in the sheet — the only
  mark in the app that changed weight when it changed size.
- **One figure scale**, with exactly one exception: `Pose.supine` draws at
  `Anatomy.recumbent`, because a body on the floor has no height to trade
  against a tall panel. The rule exists so a figure does not appear to zoom
  between one *standing* move and the next.
- **`Facing` decides the panel aspect** — portrait side-on, square front-on and
  for the wide low shapes. A front figure with both arms out is as wide as it is
  tall and cannot share a portrait frame at one scale.
- **The knee is solved, not placed.** Two-bar IK, and an unreachable foot is
  pulled in before solving rather than the bone being stretched to meet it.
- **`MovePlates.strip(for:)` matches on equipment as well as name.** The planner
  writes "Beam goblet squat", the only key it contains is the bare `squat`, and
  matching on the name drew empty hands under a label reading 15 LB BALA BEAM.

Four tests stand in for the eye: no joint outside its panel, segment lengths
preserved, a landmark moving at least one head diameter between consecutive
panels, and no plate drawing kit its move does not use. The third is the
illustrator's own rule and it caught seven strips that read as one drawing
printed twice.

**Two scale exceptions, both deliberate.** `Pose.supine` and `Pose.quadruped`
draw at `Anatomy.recumbent`. A body on the floor or on all fours has no height
to trade against a tall panel, and at the standing scale both occupied the
bottom fifth of the frame. The one-scale rule exists so a figure does not appear
to zoom between one *standing* move and the next.

**The lying torso is tilted a few degrees** — chest above pelvis — and sits
clear of the floor rule. Level and on the line it read as a wire with a bead
threaded on it rather than as a person.

**Kit is drawn only where it changes the silhouette.** The label under every
plate already names the exact item, more precisely than a drawing can: it can
say *which* ring. So the beam, rings and dumbbells appear because they change
where the hands are or because they are the only thing separating two identical
patterns — a beam deadlift from a ring deadlift. Nothing else is added.

**The spinal wave runs folded first.** Its cue is "tailbone to head and back
down" — tailbone moves first, head last, which is the roll *up*, so it opens
folded. This was flipped once on a misreading and flipped back; the order is
correct as written and should not be changed again without re-reading the cue.

**Shaking has no plate.** A shake has no shape, so any two arm angles would be
arbitrary, and an arbitrary drawing is worse than none. It is named in
`MovePlateTests.undrawable` rather than left as a silent gap.

They show shape and order, not clinical form. The cue carries the detail and the
move sheet says so out loud rather than letting the drawing imply more precision
than it has.

### Move kinds, and a decoding trap

`Move.kindRaw` is `Optional` on purpose. Routines are stored as JSON inside
`PlannedSession`, `SavedRoutine` and `ActiveSession`, and Swift's synthesized
decoder *throws* on a missing non-optional key rather than falling back to a
property default — so adding `kind` as non-optional would have made every
routine already on disk undecodable, taking the growth form with it. There is a
test for this (`decodesLegacyRoutine`). The same trap applies to any future
field added to `Move` or `IntervalRoutine`.

---

## 8. Judgement calls made without asking

Flagged here because a future maintainer might otherwise "correct" them.

- **The headline weight is a seven-day mean, not this morning's reading.**
  Day-to-day weight is mostly water; showing the raw number as progress is the
  most demoralising thing a weight tracker can do.
- **A goal date is projected only when the trend is actually heading there.**
  `projectedDate(toGoal:)` returns nil from a flat or rising trend rather than
  producing a date. A projection off a trend that is not happening is a lie
  told with arithmetic.
- **Recovery guidance is three coarse states, not a score.** A continuous
  "recovery number" would imply precision this data does not have. Two signals
  must be down before the plan changes; missing data holds the plan rather than
  inventing a reason to alter it.
- **Only *asleep* samples count as sleep.** Time in bed awake is not sleep.
- **CloudKit failure falls back to a local store** instead of crashing. Losing
  sync should not cost you the ability to run a workout.

---

## 9. The planner, as built

`OfflinePlanner` is **not a degraded mode** — it is the floor the app stands on,
and every failure path in `ClaudePlanner` lands there. A week is never blocked
on a network or a key.

`PlanValidator` sits between both planners and the store. A generated week that
names a load the kit cannot be set to is rejected **whole**, never trimmed: a
session missing half its rotation is a worse artefact than no session, and a
planner whose output is silently edited never learns it was wrong.

What the planner is told, and what it may do with each:

| Input | May it change the sessions? |
| --- | --- |
| Attendance over the last fortnight | Yes — the strongest signal it has |
| Loose sets logged off-plan | Yes |
| Recovery (sleep, HRV, resting heart rate) | Yes |
| Moves she said hurt | Yes — absolute, overrides everything |
| Moves she dislikes | Yes — rarely, never twice in a week |
| Eating window | **No** — passed as context only |
| Weight and goal | **No** — sessions are written the same either way |
| Goal weight → `walkMinutes` | **Yes, and only here** |

**Walking is the one exception and it is deliberate.** Thirteen-minute sessions
cannot move energy balance; walking can. So `walkMinutes` is the single number
set with the goal in mind, bounded at 300 a week, climbing by at most ten
minutes a week offline. The app states plainly on Signals which lever moves the
scale — walking and the eating window she set — and never prescribes intake.

**Flow work is not strength work.** `MoveKind` separates them, and
`MoveLibrary.moves(for:)` filters to `.strength`, so a spinal wave can never be
dropped into a forty-second work interval and counted down at. A flow is a
practice: continuous, unhurried, and ruined by a countdown.

**The pace dial is honest about its own limits.** `Pace` changes sessions per
week and progression speed. `Pace.expectation` says out loud that hard "will not
move the scale faster — that is decided by the walking and the eating window,
not by these thirteen minutes." Do not soften that into a growth-hacked promise.

**Move preferences** are keyed by name with containment matching, because a
dislike is about a family of movement and the planner invents names freely:
"push-up" also covers the incline and knee variants. Pain is sticky — once a
move is avoided, a later, milder reason does not promote it back in. She can
also long-press any move on Today to record an opinion without skipping a set.

---

## 10. Voice

The copy is part of the design and is easy to wreck. It is plain, warm, and
specific; it names real numbers and real equipment; it never exclaims and never
implies fault. Some existing lines to match:

> Twenty-four minutes, three moves you already know. Slow beats heavy today.

> If the last two rounds come slower, that still counts as finished.

> Sleep and heart rate are both off your usual. Today drops a round — that is
> the plan working, not you failing.

No "Crush it!", no "Great job!", no exclamation marks.

---

## 11. Working agreements

- Branch: `claude/ai-fitness-planner-ios-nh2obt`. Push there, not to the
  default branch.
- No pull request unless the user asks for one.
- Health and fasting content is educational, never medical advice. That framing
  is both correct and what keeps a health app through App Store review.
- Tests: `xcodebuild test -project WrkTime.xcodeproj -scheme WrkTime
  -destination 'platform=iOS Simulator,name=iPhone 16'`, or ⌘U.
- The API key is never committed, never in `UserDefaults`, never in a build
  setting or `.xcconfig`, never in the app's own export file, never logged.
  Keychain only. She types it herself; do not type it for her.

### What to pick up next

1. **Hear the audio and feel the haptics on the phone.** The flow cue
   (`Haptics.flowBegan`, the soft impact) is the newest and least verified of
   them. This is now the oldest unverified thing in the app. Everything else has
   been verified; these two have not, and they are cheap to check now that the
   app installs on a device.
2. **Match the two named flows** — Move With Erin's 8-minute lymphatic and Nick
   Moneo's "fix your stiffness" — once she sends them. They belong in
   `MoveLibrary` as named sequences. Do not guess at them unseen; the generic
   qi gong movements already in the library were written *as* generic on
   purpose.
3. **`LiveActivityIntent`**, so pause and skip work from the lock screen. This
   needs the engine reachable from an App Intent, which `ActiveSession` has
   made materially easier.
4. **The watch app.** Decided, never started. It reads the same store.
5. **Cycle-aware programming**, only if she opts in.
