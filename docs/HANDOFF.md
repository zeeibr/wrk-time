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

**The equipment is the whole constraint.** Dumbbell pairs (2/3/5 lb), a single
10 lb dumbbell — one dumbbell held in both hands, bought August 2026 for core
work, its own `Equipment` case so nothing can treat it as a pair — an 18 lb
kettlebell, a resistance band, one 15 lb Bala
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
| Fasting | **Removed.** Started as a headline feature, was demoted to an input, and in August 2026 the user asked for it to go entirely. `FastWindow`, the eating-window editor, the Today cell, the Signals module and the planner context line are all gone. Old archives with a `fasts` array still restore; the key is simply ignored. |
| Functional-medicine lens | Circadian timing, sleep and recovery, stress load, minerals and hydration. Framed as education, never medical advice. |
| Profile data | Entered by the user in `BlockSetupView` on first run. It previously opened with an invented starting weight and goal; that seed is gone. |
| Design lane | **G, "Almanac."** |
| Intensity | One dial, `Pace` — steady / building / hard. It changes sessions per week and how fast load climbs. It is **not** allowed to claim it moves the scale faster; see §9. |
| Which lever moves the scale | Walking volume. Stated plainly on Signals. The app never prescribes intake. |
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
4. **Fasting is not in the app.** It was an input for a while; the user removed it entirely. Nothing tracks, displays or asks about eating.

---

## 4. State of the build

**Added 17 August 2026 — kit she can switch on and off, and two upper-body
routines.** Her words: *"i dont have the resistance bands yet"* — the band was
in the app months before it was in the house. `Tuning.ownedEquipment` now says
what she actually has, and Settings §05 lists every switchable drawer with its
move count. The enum stays closed; this is not a way to add equipment, only a
way to say "not yet" about equipment already in it. Bodyweight and the pad are
not on the list, because they are not hers to lose.

The seam that matters: **`MoveLibrary.available` is what may be offered or
generated; `MoveLibrary.all` is what things are read back against.** Rotations,
`names` (the planner's schema enum), the sampler, both pickers and the reviewer
take `available`; drawings, the sidedness repair and stored-routine lookups keep
`all`, so a week written when she had the band still draws and still runs.
`PlanValidator` rejects a move on kit she does not have — the last gate before
the store, and it guards the offline planner too. `PlanContext` and the reviewer
both say out loud what is missing, because the system prompts list the kit as a
fixed fact and would otherwise contradict the schema.

Switching a drawer off **rewrites the sessions already written**, the same path
a ruled-out move takes; switching one back on changes nothing already written.
Two seeded routines came with it: **Upper body** (push/pull alternating, the
pull side leading on the two heaviest things she owns) and **Triceps** (every
angle the elbow extends through, on the beam and the 8 lb ring rather than
stranded on the 2 lb pairs — the audit's finding). Neither uses the band.

**Two smaller things from the same stretch.** Today is drawn on the growth
form as a **saffron arc** across its seventh of the current week's ring, on the
ring's own wobble so it sits exactly on the week it marks and only ever on the
week being lived — the one place on the drawing that means *now* rather than
*done*. And a move you have recorded an opinion about keeps its muscle groups
on the row: the verdict takes the equipment's place in saffron and the muscles
follow in mute, because a ruled-out move still saying what it worked is exactly
what you need when picking its replacement.

**Two things this cost, both worth remembering.** The seed first used a
separate "have I done this" `@AppStorage` flag, set *before* the write; the
write did not land and the flag said the job was done for good. It is guarded
on the stored value's own presence now — a one-shot marker can outlive the
thing it marks. And **synthetic taps do not reach SwiftUI `Toggle`s** in this
harness (the pre-existing Sound toggle does not respond either); a short drag
across the switch does. Verified by hand: band off by default, on → the drawer
returns to Moves live, off → the repair note reads "Nothing already written was
using it."

**Added 15 August 2026 — the 10 lb dumbbell, the core set, wider suggestions,
and a setup pause.** She bought a single 10 lb dumbbell for core work.
`Equipment.singleDumbbell` is its own case — one dumbbell held in both hands,
never a pair — so `label(forLoad:)` says "One 10 lb dumbbell" where the pairs
say "Two". Seven core moves joined the library: Russian twist and standing
side bend on the new dumbbell, and forearm plank, side plank, lying leg raise,
bicycle crunch and plank shoulder tap on bodyweight — core *strength*, never a
claim about where fat comes off, because no move decides that. Side plank and
the side bend are sided; all seven are in `MovePlates.deferred`. A seeded
"Core foundation" `SavedRoutine` rides along, same precedent as the posture
reset: her ask was a core start that respects a core that is not strong yet
but still offers a bit of a challenge, so it runs easy-to-hard — dead bug and
bird dog first, the holds last — at 30-second intervals, eight minutes with
its warm-up, hers to edit or delete. Asked whether core could live on the kit
rather than only the mat, five more joined — one loaded core pattern per
implement, holds and slow carries rather than loaded flexion: beam overhead
hold, ring half-kneeling overhead hold (sided), kettlebell around the body
(both directions), dumbbell dead bug press on the pairs, and a front-rack
march on the 10 lb single. The band deliberately has none: band core work is
a Pallof press, and a Pallof press needs an anchor the kit does not have.
Arm work followed, asked for by name: "Raise the platters" — her name for
the barre serve-a-platter move, kept — and a straight-arm tricep press-back,
both on the 2 lb pair. Framed as arm strength; the ask behind it (the
underarm) is hers to hold, not the app's to promise against. And Season's
lived week rows now open on tap: a day-by-day list of finished sessions and
substantial extras, only days that held something, per the no-ledger rule.

**Also 15 August 2026 — the coach audit, 124 moves, and the sampler.** At
her ask, a subagent playing a veteran women's strength coach audited the
whole catalog. Its fixes landed: the chin tuck's "neck" tag was outside the
seven-word muscle vocabulary (now "back, core"), the beam hip thrust and
good morning cues were rewritten (the first prescribed furniture, the second
never said where the beam sits), the upright row cue now forbids the narrow
high pull, the Russian twist cue insists on the lifted chest, and the
pullover cue names one weight in both hands. Its additions landed too — 33
strength moves and 5 floor-based flows, chosen against the gaps it found
(pull volume, lateral and single-leg lower body, calves, grip, triceps
beyond 2 lb) — taking the library to **124 moves: 96 strength, 28 flow**.
Two proposals were declined: band lateral walks and clamshells want a mini
loop around the thighs, which her long band is not. **Watch item:** the
planner's schema name enum now carries ~96 strength names plus customs; the
move object is `$ref`'d once so the compiled grammar should hold, but the
next live plan is the real test — a 400 "schema too complex" would point
here first.

Same day, the repeat offer: "More today" now also offers the session she
finished today — today's own or the next one pulled early, which is what
`FinishedSessions.today` already answers — one more time. It runs the
**frozen** routine from the completed row (her loads, her warm-up, exactly as
done) through the `.extra` path, so it lands as a `RoutineRun` and never a
second mark. Offered in both branches: beside a still-on-the-plan session
and above the composed extra.

**The drawings caught up (15 August 2026).** Adding 40 moves in a day left 65
of 124 with no plate, so six agents drew in parallel, one per pose family, and
their geometry was integrated centrally and validated against `MovePlateTests`
in one pass. **88 of 124 moves are drawn now, up from 59.** The kettlebell got
its own `Prop.bell` — a stroked body with a handle arch, never the dumbbell's
filled disc, because eighteen pounds is not two — and `MovePlates` gained
`kettlebell` and `singleDumbbell` arrays. "Air squat" needed no drawing at
all: the bare `squat` strip was orphaned, every other squat being claimed by a
longer key, so deleting it from `deferred` handed it over by the ordinary
longest-match rule.

**36 remain deferred, and `MovePlates.deferred` is now grouped by why**, which
is the useful part. Only three are simply undrawn. Six are band moves, which
have no `Prop` — a band is a line between the hands under tension and it
genuinely changes the silhouette, so inventing one is a drawing decision
rather than geometry. Twelve need a **pose builder that does not exist**:
there is no prone, side-lying, seated or kneel-back builder, and `supine`
places one arm, one leg and a pinned sole — that gap is what blocks the side
plank, the superman, the Russian twist and the child's pose, and it is the
single highest-value thing to build next. The rest were refused on principle:
eight because the movement is smaller than the one-head panel rule (a chin
tuck moves an inch, a static hold has one frame), and seven because the fact
that names the move is invisible in both projections (a grip rotation, a
wheel turn, a step that goes back *and* across). Those are the same call that
dropped "Shaking" from the library, and they should not be quietly reversed.

The sampler (same day, her ask: "try all the moves — keep track of what weve
tried"): a flight of six untried strength moves at ten seconds on, ten off,
from a section on Moves. "Tried" is **derived, never stored** — completed
sessions' routines, `RoutineRun` move names, `SetLog` rows — so history
counts retroactively and no second ledger can disagree with the first.
Finishing a flight records a `RoutineRun` like any routine, which is exactly
what advances the count; it earns no mark and stays under the tick floor on
purpose. Verified end-to-end in the simulator: a finished flight moved the
count and the next flight offered the next six. The by-muscle
suggestions now ask for ten moves rather than four (four minus the
near-duplicates `validated` demotes is how "core" once returned a single
offer), carry her refusals into the prompt, and drop any suggestion
`MovePreference.anyCovers` matches on the way out. And every session with a
warm-up now takes a 30-second rest phase (`WarmUp.setupSeconds`) between the
last flow movement and round one — time to get the kit out, shown as "Next up"
with the first move, filing no reps because no set precedes it. The morning
practice, all flow, never gets one. Weekly counts stopped capping at the
target the same day: a week she finished six sessions of five reads 6/5 on
Today, Season and the ring, which the ring's slot arithmetic was already built
for.

**Added 29 July 2026 — more than one workout a day.** Today used to dead-end:
the finished branch of section 02 had no button, so a day the plan scheduled
something ended when she did it. It now offers what is left — a missed session
or the next one early, which are the plan and earn marks — and when the plan is
exhausted, a composed `ExtraSession` plus her own saved routines, which earn
none. A finished routine previously left one overwritten `lastRunAt` and nothing
else; it now writes a `RoutineRun`, and `PlanContext.workload` puts that volume
in front of the planner with an instruction about what to do with it. Two or
more extra workouts in a week is a `PlanTrigger` signal, because a week the
model is not asked about gets no context at all.

Whether a finished custom routine earns a mark was **her** decision, asked
directly: it does not. The growth form stays a record of the plan.

Updated 28 July 2026, after a four-dimension engineering audit — persistence,
planner correctness, time arithmetic, concurrency — and the fifteen fixes it
produced. Every finding below was verified against the source before being
acted on, and the critical one was confirmed by removing the fix again and
watching the new test fail.

**What the audit was really about.** Almost every critical finding was the same
shape: an effect that must happen, placed on a path nobody exercised end to
end, reporting success anyway. See the section of that name in `CLAUDE.md`;
it is the single most useful thing to hold in mind when adding to this app.

**The three that were costing real money or writing false records:**

1. The six a.m. background plan was computed, billed and thrown away — a
   hand-made `ModelContext` does not autosave and nothing in the planner
   saved. `PlannerService.write` saves for itself now.
2. Claude's rotation was silently cut from five moves to three, on every paid
   week, because the draft decoder named three fixed slots while the schema had
   moved to `Tuning.movesPerSession`. At a setting of two it threw outside the
   repair loop, which would have sent every remaining week of the block to the
   offline planner after paying for it.
3. A resumed run assumed today's planned session, so finishing an interrupted
   morning practice marked a session she had never started and wrote it to
   Health. `ActiveSession` carries its subject now.

**Also fixed:** a rewrite adding a second session to a day already trained; four
disagreeing spellings of "is this move ruled out", which made the shipped
push-up dislike offer the incline push-up as its own replacement; a backup
carrying six of the store's eight types, so a restore lost every opinion about
every move; a Health workout spanning wall-clock including pauses; a weight
backfill that could never run; flow movements inside the planner's move enum; a
new block opening with the previous block's marks; an expired resume replaying
the whole routine; a token counter that was both a race and a half-price
undercount; a practice reading as undone after a flight; the skip review racing
the cover it was asked from; and a backward clock stranding the session.

Previously updated 27 July 2026, after the app was compiled, run on the
simulator, run on a physical iPhone, and driven against the live Claude API for
the first time.

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
| Manual weigh-ins | Built | `WrkTime/Today/WeighInView.swift` |
| Sided moves — a full work interval per side | Built, tested | `WrkTime/Timer/IntervalRoutine.swift` |
| Custom-move queue, review, muscle suggestions | Built, live-verified Aug 8 2026 | `WrkTime/Planner/MoveReviewer.swift`, `WrkTime/App/MoveLibraryView.swift` |
| Interrupted-session recovery | Built, tested | `WrkTime/Timer/ActiveSession.swift` |
| Move preferences and skip reasons | Built, tested | `WrkTime/Model/MovePreference.swift`, `WrkTime/Today/SkipReviewView.swift` |
| Backup and restore | Built | `WrkTime/Model/Archive.swift` |
| Flow work — qi gong and lymphatic | Built | `MoveLibrary.flow` in `WrkTime/Model/Equipment.swift` |
| Morning practice — daily, 8 movements | Built, tested | `WrkTime/Model/MorningPractice.swift` |
| Flow warm-up on every session | Built, tested | `WrkTime/Model/WarmUp.swift` |
| Timer-only routines — no moves | Built, tested | `WrkTime/Timer/RoutineBuilderView.swift` |
| Move diagrams — drawn stick figures | Built, tested | `WrkTime/DesignSystem/MoveDiagram.swift`, `WrkTime/Today/MoveSheet.swift` |
| Chronological extra-workout ticks on the rings | Built, tested | `GrowthForm.tickPositions` in `WrkTime/Today/GrowthForm.swift` |
| Single 10 lb dumbbell + core move set | Built, tested | `Equipment.singleDumbbell`, `MoveLibrary` in `WrkTime/Model/Equipment.swift` |
| Setup pause between warm-up and round one | Built, tested | `RoutineSchedule` in `WrkTime/Timer/IntervalRoutine.swift`, `WarmUp.setupSeconds` |
| Loaded core work on every implement | Built, tested | `MoveLibrary` in `WrkTime/Model/Equipment.swift` |
| The sampler — 10s tastes, tried/untried derived | Built, tested | `WrkTime/Model/MoveSampler.swift`, `WrkTime/App/MoveLibraryView.swift` |
| Equipment she can switch on and off | Built, tested | `Tuning.ownedEquipment`, `Equipment.isOwned`, `MoveLibrary.available`, Settings §05 |
| Week rows open to a day-by-day breakdown | Built | `WrkTime/Today/SeasonView.swift` |
| Repeating the session finished today | Built | `TodayView.repeatOffer` |
| Today drawn as a saffron arc on the current ring | Built | `GrowthForm.ringSegment` in `WrkTime/Today/GrowthForm.swift` |
| Seeded routines — posture, core, upper body, triceps | Built | `WrkTimeApp.seed…Routine` |
| **Watch app** | **Not started** | — |
| **`LiveActivityIntent`** | **Not started** — lock screen is read-only | — |
| Cycle-aware programming | Deliberately not built — opt-in only, awaiting her decision | — |

283 tests in 48 suites. Builds and runs on the iPhone 17 Pro simulator and on a
physical iPhone 17 Pro.

The extra-workout ticks (Aug 15 2026): a tick no longer lands at an arbitrary
slot — `GrowthForm.tickPositions` places each `RoutineRun` just past the dot of
the session it actually followed, from timestamps. Same-day extras cluster
tight, a different-day extra steps wider, one before any session tucks ahead of
the first dot, and a heavy day clamps inside its gap so it cannot collide with
the next dot. The function is `nonisolated static` and pure — living on a
SwiftUI view it would otherwise inherit `@MainActor`, which the app never
noticed and the off-actor tests crashed on. Anything pure added to a view type
for testability should carry the same keyword.

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

### The morning practice

Eight flow movements, a minute each, every day, always opening with the
rebounding. Asked for in as many words: *"one of those every morning separate to
the workout sessions but mandatory … it's important we do these every day."*

Three properties follow from *every day* and the code protects each:

- **It is not tied to the plan.** It appears on a rest day, in any week, and on
  a day the planner never wrote. Nothing about it is conditional on a
  `PlannedSession`.
- **It earns no mark.** Rule three stands — one mark is one finished planned
  session. A daily practice drawing on the growth form would make the form mean
  "I moved" rather than "I did the plan", and would swamp the weekly thing it
  exists to record. It keeps its own row instead.
- **Only finished days are stored.** There is no row for a day she missed. A
  run of days is reported when there is one and a gap is simply not mentioned;
  the app does not keep a ledger of absences.

It runs on the same engine as everything else — a routine of pure flow, zero
rounds — which is why `RoutineSchedule` accepts a routine with no rounds at all.
Pain still outranks the ritual: if the rebounding itself is ruled out, the
practice opens with something else rather than insisting.

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
- **`MovePlates.strip(for:)` is a dictionary lookup**, because the library is
  closed. It was three passes of fuzzy matching, and every one of them existed
  to guess what an invented name meant. They guessed wrong: "Beam goblet squat"
  drew empty hands under a label reading 15 LB BALA BEAM, and "Ring goblet
  squat" drew a hinge because it shares the word *ring* with the ring deadlift.
  Closing the library deleted the guessing instead of adding a fourth rule.

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

**Shaking is gone from the library.** A shake has no shape — any two arm angles
would be an arbitrary picture — and a closed library has no room for a move
without a drawing. It was dropped rather than drawn badly.

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
| Weight and goal | **No** — sessions are written the same either way |
| Goal weight → `walkMinutes` | **Yes, and only here** |

**Walking is the one exception and it is deliberate.** Thirteen-minute sessions
cannot move energy balance; walking can. So `walkMinutes` is the single number
set with the goal in mind, bounded at 300 a week, climbing by at most ten
minutes a week offline. The app states plainly on Signals which lever moves the
scale — walking — and never prescribes intake.

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
- Health content is educational, never medical advice. That framing
  is both correct and what keeps a health app through App Store review.
- **A test must never be able to spend her money.** Ten test call sites used
  `PlannerService.planWeek`'s default `ClaudePlanner()`, which reads her key out
  of the Keychain and calls Anthropic for real — so every full suite run on a
  machine with a key made up to ten genuine requests, once per call site, every
  run. That is where the simulator's 485 requests and $37 came from; her phone,
  doing the same job for real, had spent 62 cents. The launch guard was never at
  fault: `planCurrentWeekIfNeeded` skips a week that already has sessions, and
  opening the app into a written week costs nothing. Tests now go through
  `ClaudePlanner.blocked`, whose `URLSession` fails every request before it
  leaves the process. Keep the key off development simulators as well — two
  independent reasons are the right number.
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

## 22 August 2026 — the reorganization

Her brief: the app had grown disorganized; the timer no longer said what to
pick up (it did, in the uncommitted tree — three weeks of August were never
committed); moves were grouped by drawer when the same movement exists on
four implements; sessions ran mat → standing → mat; she wants rep work as
well as intervals, a baseline test, a clear "too light, move up" rule, and
form notes because she has never been shown.

Done today, in order, each committed and tested:

1. August committed; the new ladder (15 lb single; 9/13/18/35 kettlebells;
   no band, never bought). Remote "Remove fasting" commit merged, local won.
2. `docs/COACH-BRIEF.md` — the one coach, from a three-person panel
   (strength, fat loss, physiology) and her answers. Read it first.
3. `MoveTaxonomy` — pattern and position for all 96 strength moves.
4. `MoveLibrary.rotation` builds the coach's shape; offline templates are a
   title and a lead implement; the validator and the pending-session read
   seam order by position. The week already on her phone runs in the new
   order without a rewrite.
5. Moves tab by position with pattern chips.
6. `MoveForm` — five lines of form per strength move; a card on the move
   sheet and a Form button on the timer.

Not done, in `tasks/todo.md`: session modes (reps / EMOM / AMRAP), the
baseline test and weekly check, double progression replacing the pace
rule, the setup buffer in the schedule, the two-implement validator rule
(waits for the prompt to say it), the coach brief as the shared system
prompt, the coach chat, aesthetics. Known small thing seen on Today: the
"Weight · 7-day mean" value wraps at 168.4 lb.

