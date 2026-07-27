# WrkTime

An interval workout timer and fitness planner for one person's kit: two 2 lb
dumbbells, a 15 lb Bala Beam, three Bala rings, and a walking pad. Work
intervals are capped at sixty seconds.

Design direction: **Almanac** — the approved lane. The mockups it was built
from, and the two rounds of alternatives it beat, are in `docs/design/`.

**Picking this up cold? Read [`docs/HANDOFF.md`](docs/HANDOFF.md) first.** It
covers the decisions already settled with the user, the state of every area,
the judgement calls that should not be quietly reversed, and the plan for the
next milestone.

## The idea the design rests on

The app has two registers, and the whole visual system is built to make the
switch between them unmistakable.

- **Document.** Oat ground, ink type, moss hairlines, a slab serif for the
  things you'd read aloud. This is Today, Season, Signals — screens you read.
- **Field.** The moment a set starts, the ground inverts. A dark field rises
  from the bottom of the screen to the height of the time left in the interval,
  and the count is knocked out of the boundary — ink on oat above the line, oat
  on field below, one continuous numeral cut by the edge.

`Register` in `Palette.swift` is the single value that decides which world a
surface is in. Views read it rather than hard-coding colours.

## What is built

| Area | State |
| --- | --- |
| Design system — palette, type, components | Built |
| Interval engine — drift-free clock, phases, skip, pause | Built, tested |
| Growth form — generative season rings | Built |
| Today screen | Built |
| Routine builder — compose and save your own intervals | Built |
| Workout timer screen — the register change | Built |
| SwiftData models | Built |
| HealthKit — weight, sleep, HRV, resting HR; workout write-back | Built |
| Weight trend and goal projection | Built, tested |
| Live Activity and Dynamic Island | Built |
| CloudKit sync | On |
| Season and Signals screens | Placeholder |
| Claude planner | Not started |
| Watch app | Not started |

## Running it

Open `WrkTime.xcodeproj` in Xcode 16 or later and build to a device or
simulator on iOS 18+. There are no dependencies and nothing to install.

**This has never been compiled.** It was written in a Linux container with no
Xcode, so the first build is yours. The Swift was read back carefully and
several compile-blockers were fixed before commit, but expect to fix a few
more — treat the first build as a code review with a compiler.

The project uses Xcode 16 file-system synchronized groups, so new files added
to `WrkTime/` are picked up without editing the project file.

### Before the first build

Three things need your developer account, and Xcode cannot guess them:

1. **Team.** Set `DEVELOPMENT_TEAM` on all three targets (or pick your team in
   Signing & Capabilities once — Xcode will write it).
2. **Bundle identifiers.** They default to `com.wrktime.app`,
   `com.wrktime.app.widgets` and `com.wrktime.app.tests`. Change the prefix to
   something you own.
3. **Capabilities.** The entitlements files ask for HealthKit, iCloud/CloudKit
   with container `iCloud.com.wrktime.app`, and app group
   `group.com.wrktime.app`. Create the container and group under your account,
   or rename them to match ones you already have — the container identifier
   also appears in `Store.cloudKitContainerIdentifier`.

If iCloud is unavailable at launch, `Store.container()` falls back to a local
store rather than crashing. Losing sync should not cost you the ability to run
a workout.

## Layout

```
Shared/           compiled into both the app and the widget
  Palette         the two registers, as one value
  Typography      the three faces
  WorkoutActivity Live Activity attributes — the app/widget contract
WrkTime/
  App/            entry point, tab structure, first-run seed
  DesignSystem/   Components — rules, marginal index, stats, controls
  Health/         HealthService protocol, HealthKit implementation, trend maths
  Model/          Equipment (the guardrail), SwiftData store
  Timer/          routine, engine, timer screen, builder, Live Activity control
  Today/          Today screen and the generative growth form
  Support/        haptics
WrkTimeWidgets/   lock screen and Dynamic Island presentation
WrkTimeTests/     engine, schedule, weight trend and recovery tests
```

Note on the shared group: `Shared/` is listed in both the app and the widget
target. Xcode 16 synchronized groups handle this, but if the widget target
comes up missing those files, add the folder to its membership once and it will
stick.

## The engine

`IntervalEngine` never accumulates decrements. It records when the routine
started and how long it has been paused, then derives everything from

```
elapsed = now − start − pausedTotal + skipOffset
```

against a precomputed `RoutineSchedule`. A dropped frame, a slow tick, or the
app being backgrounded for ten minutes cannot make the count wrong — the next
`refresh()` simply reports the truth. That property is what the tests in
`WrkTimeTests` mostly exist to pin down, including a case that jumps the clock
forward across two whole phases.

Time is injected, so tests drive it by hand and never sleep.

## Constraints the code enforces

- `Equipment` is a closed enum. The routine builder only offers moves from it,
  and the planner's output will be validated against it, so a generated session
  can never ask for a barbell.
- `IntervalRoutine.workCeiling` is 60 seconds and clamping happens in the model,
  not the UI, so nothing downstream can exceed it.
- Saffron is reserved for a live round and today's mark. It is never spent on a
  button that isn't running.
- Sage never carries body text — it doesn't clear 4.5:1 on oat.

## The Live Activity

The widget is handed the phase's start and end *dates*, not a countdown value,
and renders its own live timer from them. That means one update per phase
change rather than one per second — which is both what the system allows in the
background and the only way the lock screen stays correct while the app is
suspended.

## Judgement calls worth knowing about

- **The headline weight is a seven-day mean, not this morning's reading.**
  Day-to-day weight is mostly water, and presenting the raw number as progress
  is the most demoralising thing a weight tracker can do.
- **A goal date is only projected when the trend is actually heading there.**
  A projection drawn from a flat or rising trend is a lie told with arithmetic,
  so `projectedDate(toGoal:)` returns nil instead.
- **Recovery guidance is three coarse states, not a score.** A continuous
  "recovery number" would imply a precision this data does not have. Two
  signals must be down before the plan changes, and missing data holds the plan
  rather than inventing a reason to alter it.
- **Only *asleep* samples count as sleep.** Time in bed awake is not sleep, and
  counting it would flatter the numbers.

## Next

1. The Claude planner: equipment-aware program generation against a strict
   schema, weekly re-planning from the weight trend and recovery snapshot, and
   a deterministic offline fallback so the app is never dead without a network.
2. Season and Signals screens.
3. The watch app — a standalone interval runner reading the same synced store.
