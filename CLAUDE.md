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

## The two planners

`OfflinePlanner` is not a degraded mode — it is the floor the app stands on,
and every failure path in `ClaudePlanner` lands there. A week is never blocked
on a network. `PlanValidator` sits between both and the store: a generated week
that names a load the kit cannot be set to is rejected **whole**, never trimmed.

## Hard constraints

- **Equipment is a closed enum** (`WrkTime/Model/Equipment.swift`): two 2 lb
  dumbbells, a 15 lb Bala Beam, three Bala rings, a walking pad. Nothing may
  offer or generate anything else.
- **Work intervals cap at 60 seconds**, clamped in `IntervalRoutine`, not in
  the UI.
- **Every session opens with 3–5 flow movements**, built by `WarmUp` rather
  than by either planner. It is additive: never a round removed, never a work
  interval shortened.
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

## Things not to "fix"

These look like oversights and are not:

- `IntervalEngine` takes an injected clock and an `autoTick` flag. Both exist so
  tests assert exact values without sleeping. Keep them.
- `Phase.Kind` has three cases, not two. `flow` holds the field still, gets no
  countdown tick, and is not a round.
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
- `MovePlates.strip(for:)` returns nil for an unknown move. A diagram of the
  wrong movement is worse than none.
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
