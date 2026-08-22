# WrkTime

iOS interval workout timer and fitness planner. SwiftUI, SwiftData + CloudKit,
HealthKit, Live Activity, Xcode 16+, iOS 18+.

**Read `docs/HANDOFF.md` before substantial work.** It has the decisions already
settled with the user, the state of every area, and the plan for what is next.
This file is only the things worth having in context always.

## Status

Builds, runs and passes its tests on the iPhone 17 Pro simulator, and is
installed and run regularly on her physical iPhone 17 Pro. The audio cues and
the haptic vocabulary are still the oldest unverified thing in the app — they
were written to spec and have never been deliberately heard or felt.
`WrkTime.xcodeproj/project.pbxproj` is hand-written and remains the riskiest
artifact; it uses file-system synchronized groups, so new files under
`WrkTime/` are picked up without editing it.

Built: design system, interval engine (tested), timer screen, routine builder,
growth form, Today, Season, Signals, block setup, SwiftData + CloudKit,
HealthKit, Live Activity, backup/restore, the Claude planner with a
deterministic offline fallback, interrupted-session recovery, the flow warm-up,
timer-only routines, drawn move diagrams, sided moves (a timer per side), and
the custom-move review queue with muscle-targeted suggestions. `MoveReviewer`
**has** reached the live API (Aug 8 2026, in the simulator): a batch review
correctly approved a lift with equipment/load/muscles, classified a qi gong
movement as flow, and the by-muscle suggestions returned addable entries. The
planner's own first live call remains separately verified per HANDOFF.

Not built: the watch app, `LiveActivityIntent` (the lock screen is read-only),
and cycle-aware programming (opt-in only, awaiting the user's decision).

**The planner reached the live API on 27 July 2026** and has run against it
many times since; what that first call taught is in HANDOFF §5 and every lesson
there is still load-bearing. Her own spend on it is about 62 cents across a
block. Tests must never add to that — see the Workflow note below.

## Model usage

**The model is for adaptation, not arithmetic.** Progression — rest shortening,
rounds climbing, work lengthening toward the ceiling — is arithmetic
`OfflinePlanner` does correctly and for nothing. Claude adds judgement about
what *changed*: a session missed, an opinion recorded, a trend that turned.

`PlanTrigger` decides. A clean week steps on from the last one; a week with
something to adapt to is written. A check-in lands every fourth week so a long
clean run cannot drift. Pressing Rewrite always asks — that is her asking.

Before reaching for the model, ask whether the answer is arithmetic. Resizing a
rotation, substituting a ruled-out move, building the warm-up and the morning
practice are all local and free, and each was moved there deliberately.

`OfflinePlanner` is not a degraded mode — it is the floor the app stands on,
and every failure path in `ClaudePlanner` lands there. A week is never blocked
on a network. `PlanValidator` sits between both and the store: a generated week
that names a load the kit cannot be set to is rejected **whole**, never trimmed.

## Two numbers she controls

`Tuning` holds them: moves in a session's rotation (5 by default, 2–6) and
movements in the morning practice (8 by default, capped by the flow library).
Both are bounded rather than free — the response schema names a slot per move,
and the practice cannot ask for more movements than exist. Everything else
about a week is the planner's call.

## Hard constraints

- **Owning a thing and the enum holding it are two questions.**
  `Tuning.ownedEquipment` says what is actually in the house; the enum stays
  closed and is never a way to add kit. `Equipment.isOwned` is the one
  predicate, and the split it draws is load-bearing: `MoveLibrary.available`
  is what may be **offered or generated** (rotations, the schema's name enum,
  the sampler, the pickers, the reviewer), while `MoveLibrary.all` stays what
  things are **read back** against — drawings, the sidedness repair, a name in
  a stored routine. A week written when she had the band still draws and still
  runs; it simply is not written again. Switching a drawer off repairs the
  weeks already written, the same path a ruled-out move takes. Bodyweight and
  the pad cannot be switched off. Stored as one comma-joined string so a view
  can hold it in `@AppStorage` and redraw — `UserDefaults` does not publish,
  and the Moves tab has to lose the drawer without waiting for a relaunch.
- **Equipment is a closed enum** (`WrkTime/Model/Equipment.swift`): dumbbell
  pairs at 2/3/5 lb, a **single 10 lb dumbbell** (one dumbbell held in both
  hands — its own case, `singleDumbbell`, so nothing can treat it as a pair;
  bought August 2026 for core work), a 15 lb Bala Beam, three Bala rings
  (5/8/10), an 18 lb
  kettlebell, a resistance band, a walking pad. Nothing may offer or generate
  anything else. It grows only when she actually buys something (the 3/5 lb
  pairs and the kettlebell arrived August 2026 — three starter kettlebell
  moves, drawings deferred, no swing on purpose; the band arrived days later
  for posture work, with six posture moves — strength on purpose, so none of
  them leak into the morning practice's qi gong pool — and a seeded "Posture
  reset" `SavedRoutine` that is hers to edit or delete; the 10 lb dumbbell
  brought the core set — Russian twist, standing side bend, and five
  bodyweight moves, framed as core strength and never as fat placement,
  drawings deferred — plus a seeded "Core foundation" `SavedRoutine`, ordered
  easy-to-hard for a core that is not strong yet, hers to edit or delete, and
  one loaded core pattern per implement — holds and slow carries, never
  loaded flexion; the band has none because a Pallof press needs an anchor
  the kit does not have).
- **A load steps up only when her counts say so, and only by her hand.**
  `LoadProgression` is local arithmetic, and its ceiling is a **pace** — 18
  reps per minute of work, i.e. 12 in a 40 s interval — never a raw count,
  because she lifts to time and a fixed number would flatter long intervals.
  Two consecutive counted sessions at the current load, every set at pace;
  `SetLog.setSeconds` carries the intervals, and a row without them cannot
  qualify (no guessed pace). Surfaced as one sentence and one button on the
  move sheet — through `MoveOverrides`, so it behaves like any load change.
  The planner is told the conclusions in `PlanContext.readyForMore` and may
  speak to them, never assign them.
- **A completed session is frozen.** `mark` writes the routine the timer
  actually ran into the row, and the `routine` getter skips the repair-on-read
  seam once `completedAt` is set — a record must not shift when she later
  changes a load, or the Whoop copy would misreport what she lifted. Pending
  sessions keep tracking the library and her overrides.
- **Loads inside the library are hers to change.** `MoveOverride` stores one
  load per built-in move (only ever a load the equipment can be set to), edited
  from the library's selection bar. Applied at the stored-routine read seam
  (with the sidedness repair), in `ExtraSession`, and in the pickers — the cue
  text is corrected along with the number. Four ring moves added Aug 2026
  (bicep curl, hammer curl, Arnold press — all sided — and the behind-back
  raise) ship **without drawings** by her call; `MovePlates.deferred` stops the
  containment matcher from handing them the dumbbell strips.
- **The move library is closed too.** `MoveLibrary.names` is an enum in the
  planner's response schema and `PlanValidator` rejects anything outside it, so
  every move in every plan has a drawing by construction. Do not reopen it to
  let the planner invent a name — that is where the fuzzy matching, the
  wrong-shape plates and the fallback glyphs all came from.
- **The library grows only through review.** Her own additions are `CustomMove`
  rows: names queue locally, one send hands the batch to `MoveReviewer` (which
  also suggests moves by target muscle), and only an approved row joins the
  working library — the schema enum, the validator and the rotations all take
  the approved set as `extras`/`plus`/`including` parameters, never by mutating
  `MoveLibrary`. `MoveReviewer.validated` re-checks equipment and load locally
  so a bad approval is demoted, not stored. A custom move has no drawing,
  deliberately. `OfflinePlanner` sees none of this — it gets no context, by
  design — and `PlanRepair.resize` fills from built-ins only, so a rotation it
  regrows can swap a custom out for a built-in; accepted, not an oversight.
- **The sampler is a browse, not a workout.** Ten-second flights of six
  untried strength moves (`MoveSampler`, surfaced on Moves). "Tried" is
  derived from the records that already exist — completed sessions' routines,
  `RoutineRun` move names, `SetLog` rows — never stored as its own ledger. A
  finished flight is a `RoutineRun`: it advances the count by existing, earns
  no mark, and at about two minutes deliberately stays under the tick floor.
- **A sided move takes one full work interval per side.** `Move.sided`
  (`.sides` or `.directions`, Optional like every stored addition) makes
  `RoutineSchedule` expand the turn into two work phases labelled by
  `Phase.side` — added, never carved out of the first, and in a written-out
  sequence it claims two of her steps rather than adding any. `roundCount`
  counts the expansion, and every surface counts against `roundCount`.
- **Work intervals cap at 60 seconds**, clamped in `IntervalRoutine`, not in
  the UI.
- **The morning practice happens every day.** `Tuning.practiceMovements` flow
  movements — eight by default — at 60 s each,
  always opening with the rebounding (`Practice` in
  `WrkTime/Model/MorningPractice.swift`). It is not tied to the plan — it
  appears on rest days — and it earns no mark, because a mark is a finished
  session. It keeps its own record.
- **Every session also opens with 3–5 flow movements**, built by `WarmUp`. It is
  additive: never a round removed, never a work interval shortened. It draws
  from the movements the morning practice did not use that day, so nothing is
  repeated within a day. Between the last flow movement and round one sits a
  30-second setup pause (`WarmUp.setupSeconds`) — a rest phase, so it shows
  "Next up" with the first move and asks for no reps — because the warm-up
  runs empty-handed and round one does not. The morning practice, all flow,
  never gets one.
- **A day can hold more than one workout, and only some of them are marks.**
  Once the day's plan is done, Today offers what is left: a session missed
  earlier in the week or the next one early — those are the plan, and they earn
  marks. When the plan is exhausted it offers an `ExtraSession` composed from
  the kit, and her own saved routines. Those earn **no mark** and are recorded
  as `RoutineRun` instead. That split was her decision when asked, and it keeps
  the growth form meaning "I did the plan" rather than becoming an activity log.
- **`RoutineRun` is volume, and volume reaches the planner.** `PlanContext.workload`
  counts the last seven days — sessions done against planned, her own workouts,
  practices, loose sets — and the prompt says what to do with it. Two or more
  extra workouts is also a `PlanTrigger` signal, and that part is load-bearing:
  a week the model is not asked about is written by `OfflinePlanner`, which
  receives no context at all, so without the trigger the heaviest weeks would be
  the ones stepped on blindly.
- **A rest day is not a locked door.** It states the plan's intent and then
  offers whatever is still available: a session missed earlier this week first,
  otherwise the next one early. Offered, never urged.
- **A routine can be a fixed shape or a written-out sequence.** `IntervalStep`
  says what it is, so nothing assumes work and rest alternate — three work
  intervals in a row is a thing she can ask for. `roundCount` is the number of
  work intervals either way; never read `rounds` for display.
- **A routine may have no moves.** That is a plain interval timer, not an
  unfinished routine.
- **The walking pad has no moves.** They were removed outright, not merely kept
  out of rotations: Whoop already writes her walks to Health, so naming them as
  selectable moves duplicated a number the app reads anyway — and a
  forty-second interval on the pad takes longer to set up than to do. The
  `Equipment` case stays so anything already stored decodes, and the weekly
  target still lives in `walkMinutes` and is drawn on Signals.
- **Fasting is gone.** It was demoted to an input and then removed outright at
  the user's request (August 2026). Nothing tracks, displays or asks about
  eating; old archives with a `fasts` array restore fine, the key is ignored.
- **Whoop is read-only.** Their developer API only reads out — recovery, sleep,
  strain — so nothing can be written to Muscular Load programmatically.
  `WhoopSummary` writes the finished session to the clipboard instead, for her
  to paste into Whoop's own assistant. It counts *turns*, not schedule
  intervals: three turns on a split squat is "3 × 40s each side".
- **Whoop wants reps, so reps are counted during the rest.** A stepper on the
  rest phase files the set just finished (`RoutineSchedule.setEnding(before:)`),
  stored as `repCounts` on `PlannedSession` and `RoutineRun` — Optional, and
  sparse: an uncounted set stays zero rather than being guessed at, and its
  move falls back to time in the summary. Never a keyboard: a number pad in the
  field register, on a forty-second rest, is a way of recording nothing. The
  last set is counted on the finish screen, since it has no rest after it —
  `applyReps` revisits the row `report()` already wrote rather than delaying
  the recording, which would be the bug shape above all over again.
- **`SetLog` is the rep history, and it is a second record on purpose.**
  `repCounts` is flat against the schedule — right for writing, useless for
  reading back, because a `RoutineRun` keeps move names and no schedule. One
  row per move per session, with its load, rewritten by `sourceID` so a late
  count corrects rather than duplicates. Read on the move sheet, which the
  library's row chevron now opens.
- Health content is educational, never medical advice.

## Design: the Almanac lane

Two registers, and the switch between them is the whole idea.

- **Document** — oat ground, ink type, moss hairlines, slab serif. Screens you read.
- **Field** — a set starts, the ground inverts, and a dark field rises to the
  height of the time remaining with the count knocked out of its edge.

`Register` in `Shared/Palette.swift` is the single value deciding which. Views
read it; they never hard-code colours.

The tabs are **Today · Moves · Season · Signals** — the day, the material, the
record, the inputs. Moves (Aug 2026, from the IA review) is the old Timer tab
with the whole library inline under her routines: `MoveLibraryView(embedded:)`
owns the scroll and the selection bar, the routines ride in as `topSection`,
and the Settings sheet still opens the same view modally. The library holds
rep history and step-up nudges; it must never again live behind Settings.

- Saffron means live: a running round, today's mark. Nothing else.
- Sage never carries body text — it fails contrast on oat.
- One mark is one finished session; `completedAt` is the only thing that counts.
  Weekly counts never cap at the target: six finished on a five-session week
  is 6/5 on Today, Season and the ring — the ring's slot arithmetic grows with
  the week (`slots = max(sessionsPerWeek, marks)`), and the Season row grows
  extra pips. On the growth form (mark review, Aug 2026 — her picks): a session is a
  **moss dot set on the ring**, the latest a saffron-ink dot with a fine halo;
  her own workouts of `RoutineRun.substantialSeconds` (7 min) or more are
  **thin ticks hanging inward** — subordinate by shape and weight, counted by
  nothing. Dots because four crossing notches at even slots drew a crosshair
  around the centre seed. Future rings share one wobble phase (`drawPhase`) so
  they nest instead of tangling; a week takes its own phase once lived. Substantial is judged by the
  routine's **written** length (`plannedSeconds`, warm-up included), never the
  elapsed clock — skipping through rests still finished the session — and
  `ExtraSession` raises its rounds until every offer clears the floor.

Approved mockup: `docs/design/lane-g-almanac-approved.html`.

## The bug shape this app keeps producing

**A side effect placed on a path nobody exercises end to end, reporting success
anyway.** It has happened six times, and every instance was invisible because
the *failure* path worked:

- Recording a finished session hung on `.onChange` attached to the view that
  finishing removes, so only successful sessions were lost.
- The overnight planner built its own `ModelContext` — which does not autosave —
  and nothing in the planner called `save()`, so the week was billed for and
  discarded while "Written overnight" reported a timestamp.
- The draft decoder read three move slots while the schema asked for five, so
  two moves were dropped from every paid week and nothing counted them.
- A resumed run carried no identity, so finishing an interrupted practice marked
  a planned session she had never started.
- Recording a finished routine went into `TodayView.finish`, and a routine
  started from the **Timer tab** has its own `onEnd` and never reaches it — so
  those runs left no trace. The plan for that change said to wire both call
  sites; only one was wired, and only the wired one was verified.

The sixth is the instructive one: having the rule written down did not prevent
it. What prevents it is not having two call sites. When an effect must happen
for *every* instance of something, put it where that something is detected —
`IntervalEngine.onEnded`, `WorkoutTimerView.report`, `PlannerService.write`
saving for itself — and never in a caller who could have been a different
caller.

So: **when an effect must happen, do not let a view's lifetime decide whether it
does.** `IntervalEngine.onEnded` and `PlannerService.write` saving for itself are
both that rule. And when you add a path, exercise the *success* case on a device
or the simulator — the tests could not have caught any of these.

## Things not to "fix"

These look like oversights and are not:

- `MovePreference.anyCovers` is the **only** way to ask whether a move is ruled
  out. It matches by containment, so "push-up" covers the incline and knee
  variants — which is why the one seeded preference is written that way. Four
  places once spelled this question differently and they disagreed.
- `MoveLibrary.rotation` is the **only** builder for "pick N moves from the
  library". It matches refusals by containment and what is already in hand
  exactly, which is two different questions — and the last time they were
  spelled out separately in several places, the spellings disagreed and the app
  offered her the incline push-up she was on record as disliking.
- `ExtraSession` returns an `IntervalRoutine` and never a `PlannedSession`.
  Writing one would earn a mark it is not entitled to and would collide with
  `PlanValidator.duplicateDay` and with `write`'s set of days already trained.
- `MoveLibrary.names` is strength only. The planner's move enum feeds the
  rotation, and a rotation entry becomes a work phase; a flow movement there
  would be counted down at like a set.
- `ClaudePlanner.plan` returns its `Usage` rather than leaving it in a static.
  The static was a cross-actor race, and a repair turn overwrote the first
  request instead of adding to it.
- `PlanDraft` reads its move slots by name from `ClaudePlanner.moveSlots` at
  runtime. A struct with fixed properties silently truncates the moment
  `Tuning.movesPerSession` changes.
- A completed session's Health bounds are capped at the routine's own length.
  Wall-clock includes pauses and any time the app was suspended before it
  noticed it had finished.
- The Health weight import watermarks on `.health` entries only. Counting her
  own typed weigh-ins closed the ninety-day backfill on the first launch, with
  no path that could ever reopen it.
- Week bins reject a completion dated before the block began. `days / 7`
  truncates toward zero, so the six days before a start date all landed in
  week 1 of the new block.

- `IntervalEngine` takes an injected clock and an `autoTick` flag. Both exist so
  tests assert exact values without sleeping. Keep them.
- `Phase.Kind` has three cases, not two. `flow` holds the field still, gets no
  countdown tick, and is not a round.
- A routine with **zero rounds** is legal: that is the morning practice, all
  flow and no work. `RoutineSchedule` returns early rather than inventing an
  interval to satisfy `max(rounds, 1)`.
- Ruling a move out **rewrites the sessions already written** (`PlanRepair`),
  not just the next ones. Recording the opinion and leaving today's session
  asking for the move is the app agreeing with her and changing nothing.
- `MorningPractice` rows exist only for days she **finished**. There is no
  record of a day she missed — a table of absences is a ledger of failure.
- `IntervalRoutine.warmUpMoves` and `Move.kindRaw` are Optional because the
  synthesized decoder *throws* on a missing key rather than using a default.
  Anything new added to a stored routine must be Optional too.
- `MoveStrip` draws a move as 2-3 panels on one shared floor. Three things are
  load-bearing: the stroke is 1.1pt at **every** size, the head is a fixed
  fraction of panel height, and nothing uses opacity — it renders twice inside
  the timer's knockout and the boundary cuts both.
- `Facing` decides panel aspect: portrait for side-on, square for front-on and
  for the wide low shapes (lying, all fours, incline push-up). A front figure
  with both arms out is as wide as it is tall and cannot share a portrait frame.
- `Pose.supine` draws at `Anatomy.recumbent`. It is the one scale exception and
  it is deliberate: a body on the floor has no height to trade against a tall
  panel.
- The projection chart's scrubbing is a **tap plus an 18pt-minimum
  simultaneous drag**, and every part of that is load-bearing. A `DragGesture`
  attached with `.gesture` — at any minimum distance, and even sequenced behind
  a `LongPressGesture` — takes the touch from the `ScrollView` it sits in, and
  Signals stopped scrolling anywhere a finger landed on the chart. Only a tap
  and a simultaneous drag that refuses to commit until the finger has clearly
  gone sideways leave the page scrollable. Verified by hand in the simulator;
  the hit-testing itself is `ProjectionPlot.nearestIndex`, which is tested.
- `MovePlates.strip(for:)` is a lookup, not a matcher. It returns nil only for
  a name outside the library — a stored routine from before it closed. A
  diagram of the wrong movement is worse than none.
- **`MovePlates.deferred` is grouped by *why*, and only one group is a to-do.**
  88 of 124 moves are drawn. Of the rest: the band has no `Prop` (it is a line
  between the hands and it changes the silhouette); twelve want a pose builder
  that does not exist (no prone, side-lying, seated or kneel-back, and `supine`
  places one arm, one leg and a pinned sole); and the remainder were refused
  because the movement is smaller than the one-head panel rule or because what
  names the move is invisible in both projections. Do not "fix" the last two
  groups by exaggerating a movement to clear the test.
- The engine derives state from elapsed wall-clock time against a precomputed
  schedule. It must never accumulate per-tick decrements.
- The Live Activity is handed phase start/end **dates**, not a countdown, so the
  system ticks it. Do not convert this to per-second updates.
- Headline weight is a seven-day mean, not the latest reading.
- `projectedDate(toGoal:)` returns nil on a flat or rising trend rather than a date.
- Recovery guidance is three coarse states, not a score. Missing data holds the plan.
- CloudKit failure falls back to a local store instead of crashing.

## Voice

Plain, warm, specific. Names real numbers and real equipment. Never exclaims,
never implies the user failed.

> Twenty-four minutes, three moves you already know. Slow beats heavy today.

> Sleep and heart rate are both off your usual. Today drops a round — that is
> the plan working, not you failing.

No "Crush it!", no "Great job!", no exclamation marks, no emoji in the UI.

## Workflow

- Branch: `claude/ai-fitness-planner-ios-nh2obt`. Do not push to the default branch.
- No pull request unless asked.
- **Tests must never reach the API.** `PlannerService.planWeek` defaults to a
  real `ClaudePlanner`, which reads her key from the Keychain and calls
  Anthropic — a suite run on a machine with a key spent real money, ten
  requests a time. Pass `planner: .blocked` in tests, and keep her key off
  development simulators.
- Run tests with ⌘U or:
  `xcodebuild test -project WrkTime.xcodeproj -scheme WrkTime -destination 'platform=iOS Simulator,name=iPhone 16'`
