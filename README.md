# WrkTime

An interval workout timer and fitness planner for one person's kit: two 2 lb
dumbbells, a 15 lb Bala Beam, three Bala rings, and a walking pad. Work
intervals are capped at sixty seconds.

Design direction: **Almanac** — the approved lane from the design round. See
`docs/design-lanes-round-three.md` for the pitch it came from.

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
| Season and Signals screens | Placeholder |
| HealthKit reads — Loftilla weight, Whoop sleep/HRV | Not started |
| Claude planner | Not started |
| Live Activity and Dynamic Island | Not started |
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

### Two things deliberately turned off

- **CloudKit sync** is off. `Store.container()` defaults to a local store
  because `.automatic` without the iCloud capability and a paid team fails at
  launch, which is a worse first run than no sync. Turn it on by adding
  `CLOUDKIT_SYNC` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` once the capability
  is set up. The watch app will need this.
- **HealthKit** usage strings are in the build settings, but no entitlement is
  configured and no reads are implemented yet. Both need a paid developer
  account.

## Layout

```
WrkTime/
  App/            entry point, tab structure, first-run seed
  DesignSystem/   Palette, Typography, Components — the lane, enforced in code
  Model/          Equipment (the guardrail), SwiftData store
  Timer/          IntervalRoutine, IntervalEngine, timer screen, routine builder
  Today/          Today screen and the generative growth form
  Support/        haptics
WrkTimeTests/     interval engine and schedule tests
```

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

## Next

1. HealthKit reads for weight, sleep and HRV, behind a protocol so the planner
   can be tested without Health.
2. The Claude planner: equipment-aware program generation against a strict
   schema, weekly re-planning from the weight trend, and a deterministic
   offline fallback so the app is never dead without a network.
3. Live Activity and Dynamic Island for the running interval.
4. Season and Signals screens.
5. The watch app, which needs CloudKit turned on first.
