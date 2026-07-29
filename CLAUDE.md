# WrkTime

iOS interval workout timer and fitness planner. SwiftUI, SwiftData + CloudKit,
HealthKit, Live Activity, Xcode 16+, iOS 18+.

**Read `docs/HANDOFF.md` before substantial work.** It has the decisions already
settled with the user, the state of every area, and the plan for what is next.
This file is only the things worth having in context always.

## Status

Builds, runs and passes its tests on the iPhone 17 Pro simulator. Never run on
a physical device, which is why the audio cues and the haptic vocabulary are
still unverified — both were written to spec and never heard or felt.
`WrkTime.xcodeproj/project.pbxproj` is hand-written and remains the riskiest
artifact; it uses file-system synchronized groups, so new files under
`WrkTime/` are picked up without editing it.

Built: design system, interval engine (tested), timer screen, routine builder,
growth form, Today, Season, Signals, block setup, SwiftData + CloudKit,
HealthKit, Live Activity, backup/restore, the Claude planner with a
deterministic offline fallback, interrupted-session recovery, the flow warm-up,
timer-only routines, and drawn move diagrams.

Not built: the watch app, `LiveActivityIntent` (the lock screen is read-only),
and cycle-aware programming (opt-in only, awaiting the user's decision).

**The planner has never reached the live API.** Every path so far has run
through the offline fallback because no key was set, and `ClaudePlanner`'s
response handling is tested against recorded response shapes rather than real
ones. The first real call is the outstanding verification.

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

- **Equipment is a closed enum** (`WrkTime/Model/Equipment.swift`): two 2 lb
  dumbbells, a 15 lb Bala Beam, three Bala rings, a walking pad. Nothing may
  offer or generate anything else.
- **The move library is closed too.** `MoveLibrary.names` is an enum in the
  planner's response schema and `PlanValidator` rejects anything outside it, so
  every move in every plan has a drawing by construction. Do not reopen it to
  let the planner invent a name — that is where the fuzzy matching, the
  wrong-shape plates and the fallback glyphs all came from.
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
  repeated within a day.
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
- **Fasting is an input, not a feature.** Stats stay visible; it never gets a
  tab or a hero screen.
- Health content is educational, never medical advice.

## Design: the Almanac lane

Two registers, and the switch between them is the whole idea.

- **Document** — oat ground, ink type, moss hairlines, slab serif. Screens you read.
- **Field** — a set starts, the ground inverts, and a dark field rises to the
  height of the time remaining with the count knocked out of its edge.

`Register` in `Shared/Palette.swift` is the single value deciding which. Views
read it; they never hard-code colours.

- Saffron means live: a running round, today's mark. Nothing else.
- Sage never carries body text — it fails contrast on oat.
- One mark is one finished session; `completedAt` is the only thing that counts.

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
- `MovePlates.strip(for:)` is a lookup, not a matcher. It returns nil only for
  a name outside the library — a stored routine from before it closed. A
  diagram of the wrong movement is worse than none.
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
- Run tests with ⌘U or:
  `xcodebuild test -project WrkTime.xcodeproj -scheme WrkTime -destination 'platform=iOS Simulator,name=iPhone 16'`
