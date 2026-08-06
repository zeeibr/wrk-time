# Handoff

Everything a new person — or a new session — needs to pick this up. Written
after the second milestone, with the app not yet compiled.

---

## 1. What this is

An iOS interval workout timer and fitness planner, built for one person and
one specific set of equipment. Claude generates an adaptive multi-week program;
the user runs it against a drift-free interval timer; weight and recovery come
in from Apple Health and steer the next week's plan.

**The equipment is the whole constraint.** Two 2 lb dumbbells, one 15 lb Bala
Beam, a set of three Bala rings, a walking pad. Nothing else exists as far as
this app is concerned, and `Equipment` in `WrkTime/Model/Equipment.swift` is a
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
| Fasting | **Removed.** It began as a headline feature with a functional-medicine lens, was demoted to a supporting stat, and has now been cut from the app entirely. The model, the Today cell and the planner input are all gone. Do not reintroduce it. |
| Functional-medicine lens | Narrowed to what survives without fasting: sleep, recovery and stress load, read from Health. Framed as education, never medical advice. |
| Profile data | Placeholders only. The user enters real numbers in onboarding — **which does not exist yet.** |
| Design lane | **G, "Almanac."** |

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
4. **There is no fasting.** The design mockups in `docs/design/` still show a
   fasting cell — they predate its removal. The code is the source of truth.

---

## 4. State of the build

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
| Weight trend and goal projection | Built, tested | `WrkTime/Health/HealthSync.swift` |
| Live Activity and Dynamic Island | Built | `WrkTimeWidgets/`, `WrkTime/Timer/LiveActivityController.swift` |
| **Onboarding** | **Not started** | — |
| **Claude planner** | **Not started** | — |
| Season and Signals screens | Placeholder | `WrkTime/App/WrkTimeApp.swift` |
| Watch app | Not started | — |

### The single biggest caveat

**None of this has ever been compiled.** It was written in a Linux container
with no Xcode. The Swift was read back carefully and a number of real
compile-blockers were found and fixed before each commit — a type shadowing
`SwiftUI.Section`, `.fill().strokeBorder()` which is not valid on a filled
shape, `UIScreen.main` under Swift 6 concurrency, a live ticker that would race
the fake clock in tests — but expect more. **Treat the first build as a code
review with a compiler.**

The riskiest single artifact is `WrkTime.xcodeproj/project.pbxproj`. It is
hand-written, using Xcode 16 file-system synchronized groups, and now carries
three targets plus an embed phase for the widget extension. Its structure was
validated (balanced delimiters, no dangling object references) but Xcode is the
real test. If it will not open, regenerating the project and re-adding the four
source folders is a perfectly reasonable recovery — no source file depends on
the project file's contents.

---

## 5. Before the first build

Four things need the developer account and Xcode cannot guess them:

1. **Team.** Set `DEVELOPMENT_TEAM` on all three targets, or pick the team once
   in Signing & Capabilities and let Xcode write it.
2. **Bundle identifiers.** Currently `com.wrktime.app`, `com.wrktime.app.widgets`,
   `com.wrktime.app.tests`. Change the prefix to something owned.
3. **CloudKit container.** `iCloud.com.wrktime.app`, named in both
   `WrkTime/WrkTime.entitlements` and `Store.cloudKitContainerIdentifier` —
   change both together if you rename it.
4. **App group.** `group.com.wrktime.app`, in both entitlements files.

If `Shared/` does not appear in the widget target, add the folder to its
membership once; synchronized groups shared between two targets are supported
but occasionally need a nudge.

---

## 6. Architecture notes worth knowing

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

## 7. Judgement calls made without asking

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

## 8. Next milestone: the Claude planner

The largest remaining piece, and the one with the most ways to go wrong.

**Shape it like this.**

1. **Key handling.** The user's API key goes in the Keychain, entered in
   settings. Never in `UserDefaults`, never in the repo, never logged.
2. **Strict schema.** The model returns a program as structured output matching
   `IntervalRoutine` exactly. Do not parse prose.
3. **Validate before trusting.** Every returned move must resolve to an
   `Equipment` case, and every work interval must be ≤ 60 s. Reject and retry
   on violation — the enum is the guardrail, but only if something checks it.
4. **A deterministic offline fallback is required, not optional.** The app must
   be able to produce a sensible week with no network and no key. A workout app
   that is dead without an API call is a broken workout app.
5. **Inputs to a weekly re-plan:** completed sessions, the weight trend
   (`WeightTrend.weeklyRate`), and the `RecoverySnapshot`. Nothing about
   eating — the app does not ask and does not model it.
6. **Explain every change.** When the plan changes, the app says why, in one
   sentence, in the app's voice. `RecoverySnapshot.explanation` is the model to
   follow: plain, warm, never exclamatory, and never implying the user failed.

**Then:** onboarding (real starting weight, goal, target date, schedule),
Season and Signals screens, and the watch app — which reads the same synced
store, so CloudKit needs to be working first.

---

## 9. Voice

The copy is part of the design and is easy to wreck. It is plain, warm, and
specific; it names real numbers and real equipment; it never exclaims and never
implies fault. Some existing lines to match:

> Twenty-four minutes, three moves you already know. Slow beats heavy today.

> If the last two rounds come slower, that still counts as finished.

> Sleep and heart rate are both off your usual. Today drops a round — that is
> the plan working, not you failing.

No "Crush it!", no "Great job!", no exclamation marks.

---

## 10. Working agreements

- Branch: `claude/ai-fitness-planner-ios-nh2obt`. Push there, not to the
  default branch.
- No pull request unless the user asks for one.
- Health content is educational, never medical advice. That framing is both
  correct and what keeps a health app through App Store review.
