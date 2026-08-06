# WrkTime

iOS interval workout timer and fitness planner. SwiftUI, SwiftData + CloudKit,
HealthKit, Live Activity, Xcode 16+, iOS 18+.

**Read `docs/HANDOFF.md` before substantial work.** It has the decisions already
settled with the user, the state of every area, and the plan for what is next.
This file is only the things worth having in context always.

## Status

Never compiled — written without access to Xcode. Expect compile errors on
first build; fixing them is the current priority. `WrkTime.xcodeproj/project.pbxproj`
is hand-written and the riskiest artifact; regenerating the project is a fine
recovery, since no source file depends on its contents.

Built: design system, interval engine (tested), timer screen, routine builder,
growth form, Today, SwiftData + CloudKit, HealthKit, Live Activity.
Not built: onboarding, the Claude planner, Season and Signals screens, watch app.

## Hard constraints

- **Equipment is a closed enum** (`WrkTime/Model/Equipment.swift`): two 2 lb
  dumbbells, a 15 lb Bala Beam, three Bala rings, a walking pad. Nothing may
  offer or generate anything else.
- **Work intervals cap at 60 seconds**, clamped in `IntervalRoutine`, not in
  the UI.
- **No fasting.** It was cut from the app entirely. Do not reintroduce a
  fasting timer, an eating window, or fasting stats — not on Today, not in the
  planner's inputs, not as a "small" addition. The mockups in `docs/design/`
  predate the removal and still show it.
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
