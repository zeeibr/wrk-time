# Almanac on the wrist — the watch app plan

Written 22 August 2026 for a build session that starts from this document
alone. Read `CLAUDE.md`, `docs/HANDOFF.md` and `WrkTime/Coach/COACH-BRIEF.md`
first; this plan assumes them and repeats nothing they say. Every rule in
CLAUDE.md holds on the watch: the voice, no emoji, saffron means live, the
bug shape (an effect that must happen for every instance lives where the
instance is detected, never in a caller), tests never reach the API.

## 0. Why, and what "done" means

The phone lives on the floor during a session; the watch is on the arm
that is lifting. The watch app exists so that the thing she looks at
mid-set — the count, the move, the load, the rest, Done — is on her wrist,
and so that the two numbers the phone cannot see live, heart rate and
"am I still in the set", are.

Done means, on her real Apple Watch paired to her iPhone 17 Pro:

1. She can start today's session, the morning practice, a saved routine,
   or a test from the watch, with no phone in the room, and it is recorded
   exactly as the phone would record it (mark, `RoutineRun`, `SetLog`,
   Health workout) — once, never twice.
2. A session started on the phone shows live on the watch with the same
   count and the same controls, and a rep counted on either device lands
   in one record.
3. The timer keeps running on the wrist when the screen sleeps and when
   she raises her arm mid-set, and every boundary is felt as a haptic.
4. Heart rate is recorded for the session and shown on Signals.
5. The Smart Stack shows today's session and the running one.
6. Every existing test passes; new tests cover the handoff and ownership
   rules; nothing on disk changes shape.

Not in scope, deliberately: the coach chat on the watch, the library, the
builder, Settings, the baseline's results card. The watch does; the phone
reads and decides.

## 1. The project as it stands (facts the builders need)

- Xcode 16, iOS 18 deployment target, Swift 6 strict concurrency, SwiftUI,
  SwiftData with CloudKit (`iCloud.com.wrktime.app`), app group
  `group.com.wrktime.app` (`Shared/TodaySnapshot.swift` uses it).
- Targets: `WrkTime` (app, bundle `com.zee.wrktime`), `WrkTimeTests`,
  `WrkTimeWidgetsExtension` (widgets + Live Activity). Team `ZD68VKT8X2`,
  automatic signing.
- `WrkTime.xcodeproj/project.pbxproj` is **hand-written**, with
  `PBXFileSystemSynchronizedRootGroup`s for `WrkTime/`, `WrkTimeTests/`,
  `Shared/` and `WrkTimeWidgets/`. Object ids follow
  `1A00000000000000000000NN`. Files under a synchronized folder join the
  target automatically; the widget target is the template for adding
  another target by hand (its `PBXNativeTarget`, build phases, the
  "Embed Foundation Extensions" copy phase, `PBXTargetDependency`,
  `PBXContainerItemProxy`, and its two `XCBuildConfiguration`s).
- The engine, `WrkTime/Timer/IntervalEngine.swift`, derives state from
  wall-clock time against a precomputed `RoutineSchedule`; it has `start`,
  `restore(to:running:)`, `pause`, `resume`, `skip`, `endSet`, `end`,
  `onEnded`, `onPhaseChange`, `onCountdownTick`, an injected clock and
  `autoTick`. It is `@MainActor` and owns no UI.
- `ActiveSession` (`WrkTime/Timer/ActiveSession.swift`) is the Codable
  snapshot of a running session — routine, `startedAt`, `elapsed`,
  `running`, `savedAt`, and a `Subject` (session id / practice / routine /
  extra / test) — persisted to `UserDefaults` by `ActiveSessionStore`. It
  is the unit the watch and phone will exchange.
- `WorkoutTimerView.report()` is where a finished session is recorded
  (mark via Today's `mark`, or `RoutineRuns.record` + `SetLogs.record`);
  it is wired from `IntervalEngine.onEnded`. HealthKit workouts are
  written by `HealthSync` on completion.
- `Shared/WorkoutActivity.swift` defines the Live Activity attributes; the
  phone's `LiveActivityController` hands it phase dates, not a countdown.
- The library is `MovementCatalog` (`WrkTime/Model/Movements/`); routines
  are `IntervalRoutine` JSON; the store's models are in `Model/Store.swift`.

## 2. Architecture

### 2.1 Carve out `Core/` (shared code, no UI)

Create a new synchronized folder `Core/` and **move** (git mv, keeping
history) the files that have no UIKit/SwiftUI-view dependency and that
both apps need:

- `Timer/IntervalRoutine.swift`, `Timer/IntervalEngine.swift`,
  `Timer/ActiveSession.swift`, `Model/Equipment.swift`,
  `Model/Movements/*`, `Model/MoveTaxonomy.swift`, `Model/MoveMuscles.swift`,
  `Model/MoveForm.swift`, `Model/MovePreference.swift`, `Model/Store.swift`,
  `Model/Tuning.swift`, `Model/Rotation.swift`, `Model/WarmUp.swift`,
  `Model/MorningPractice.swift`, `Model/ExtraSession.swift`,
  `Model/PlanRepair.swift`, `Model/LoadProgression.swift`,
  `Model/Baseline.swift`, `Model/WhoopSummary.swift`, `Model/Glossary.swift`,
  `Health/HealthService.swift` (protocol + `RecoverySnapshot`),
  `Health/RecoveryLog.swift`, `Support/KeychainStore.swift`,
  `Coach/CoachBrief.swift` is **not** moved (the watch never calls the model).
- Anything that imports `SwiftUI` for a `View`, `UIKit`, `ActivityKit` or
  `WidgetKit` stays in `WrkTime/`. `Palette`, `Typography` already live in
  `Shared/` and are SwiftUI-but-not-views; the watch uses them.
- `Core/` joins three targets: `WrkTime`, `WrkTimeTests`, `WrkTimeWatch`.
  `Shared/` joins those and the widget extension, as now.
- Audit with `grep -l "import UIKit\|import SwiftUI"` over `Core/`; a
  file that needs `#if canImport(UIKit)` for one call (`UIPasteboard`,
  `UIApplication.isIdleTimerDisabled`) gets the guard, not a copy.
- **Acceptance:** the iPhone app and tests build and pass unchanged; no
  file is duplicated; `MoveDiagram.swift` (Canvas drawing) stays on the
  phone for now (see 2.6).

### 2.2 The watch target

- `WrkTimeWatch/` synchronized folder; watchOS app target `WrkTimeWatch`
  (product type `com.apple.product-type.application`, `SDKROOT = watchos`,
  `WATCHOS_DEPLOYMENT_TARGET = 11.0`, `TARGETED_DEVICE_FAMILY = 4`,
  bundle `com.zee.wrktime.watchkitapp`, `WKCompanionAppBundleIdentifier =
  com.zee.wrktime`, `INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES`),
  embedded in `WrkTime` via an "Embed Watch Content" copy-files phase
  (`dstSubfolderSpec = 16`, `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`).
- Entitlements: the same app group, the same iCloud container and
  CloudKit service, HealthKit (`com.apple.developer.healthkit` plus
  `healthkit.background-delivery` is not needed).
- Info.plist keys: `NSHealthShareUsageDescription`,
  `NSHealthUpdateUsageDescription`, `WKBackgroundModes` → `workout-processing`.
- A `WrkTimeWatchTests` target is optional; the engine and ownership
  rules are tested in `WrkTimeTests` because the code is in `Core/`.

### 2.3 The store on the watch

The watch opens the **same** `Store.schema` through the same CloudKit
container; SwiftData syncs it. Rules:

- A device **owns** a session it started. The owner writes the record at
  `onEnded` exactly as the phone does today; the other device never
  writes a record for a session it did not start.
- Counts made on the non-owner are sent to the owner (2.4) and applied by
  the owner through the same `applyReps` path. If the owner is
  unreachable, the non-owner keeps them in its `ActiveSession` mirror and
  resends on reconnect; a count never goes straight into a second record.
- CloudKit latency is minutes; the watch must not wait on it for anything
  live. Everything live goes over `WCSession`.
- `ActiveSessionStore` on the watch uses `UserDefaults.standard` of the
  watch; it is a separate process with its own interrupted-session
  recovery, the same rules (`staleAfter`, `ranOut`).

### 2.4 Handoff and mirroring (`WCSession`)

New file `Core/SessionLink.swift`, one type used by both apps:

```swift
/// What the two devices say to each other about the running session.
enum SessionLinkMessage: Codable, Sendable {
    /// The owner announces a session it started or restored; sent on start,
    /// on every phase change, on pause/resume, and on request.
    case running(ActiveSession, owner: DeviceRole)
    /// The owner announces the session ended (reason, skipped moves).
    case ended(subjectID: UUID?, completed: Bool)
    /// A non-owner counted reps for a set ordinal; the owner applies.
    case reps(setOrdinal: Int, count: Int)
    /// A non-owner asks the owner to pause, resume, skip, end a set, end.
    case transport(TransportAction)
    /// Either side asks "what is running?"; the owner answers `.running`.
    case whatIsRunning
}
enum DeviceRole: String, Codable, Sendable { case phone, watch }
enum TransportAction: String, Codable, Sendable { case pause, resume, skip, endSet, end }
```

`SessionLink` is an `@MainActor` final class wrapping `WCSession`
(`WCSessionDelegate`), with `send(_:)` (uses `sendMessage` when reachable,
else `transferUserInfo`, and `updateApplicationContext` for the latest
`.running`), and `onMessage: (SessionLinkMessage) -> Void`. Encoded as
JSON `Data` under one key. The phone's `WorkoutTimerView` and the watch's
timer both install it: the owner's engine callbacks call `send(.running)`;
the non-owner's controls call `send(.transport)` and show the mirrored
state by `restore(to: elapsed, running:)` on a local engine that is
**read-only** (its `onEnded` records nothing). Ownership is decided by who
called `engine.start()`; it is written into `ActiveSession` as a new
Optional field `ownerRaw: String?` (nil reads as `.phone`, which is what
every stored session today was).

The non-owner's rep stepper on a rest phase sends `.reps`; the owner
stores it in its `reps` dictionary exactly as its own stepper would, and
`applyReps` runs at the end as now. This is the one rule that keeps the
bug shape out: there is still exactly one place a record is written.

### 2.5 The watch timer

`WrkTimeWatch/WatchTimerView.swift`, built on the same engine. The Almanac
register at watch size:

- Oat ground, ink type; the **field** rises from the bottom with time
  remaining and the count is knocked out of its edge, exactly as the phone
  (`Palette.field`, the same mask technique; the watch's `Canvas` and
  `mask` both exist). Saffron square when a work round is live.
- Layout top to bottom: position line ("Set 2 / 12", mono), the count
  (slab, as large as the face allows, `minimumScaleFactor`), the move name
  (one or two lines), the load line ("18 lb kettlebell"), and a one-row
  transport: stop · pause/resume · skip, or **Done** in place of skip on
  an open set (`phase.openEnded`). No cue text: the wrist is not where
  she reads a sentence.
- On a rest phase: "Next up" and the move, and the rep stepper bound to
  the **Digital Crown** (`.digitalCrownRotation`) with ± buttons as well,
  filing to `setEnding(before:)` as the phone does.
- Haptics via `WKInterfaceDevice.current().play(_:)`: `.start` at round
  start, `.stop` at round end, `.directionUp` for each of the last three
  seconds, `.success` at the session's end, `.click` on Done. Mirror the
  phone's `Haptics` vocabulary in a `WatchHaptics` enum with the same
  method names, so the engine callbacks bind identically.
- Always-on: the view supports `isLuminanceReduced` by dropping the
  field to a hairline and keeping the count; the engine keeps time
  regardless because it is wall-clock.
- Form: the **Form** button is not on the watch; the phone has it.

### 2.6 Workout session and heart rate

`WrkTimeWatch/WatchWorkout.swift`: an `HKWorkoutSession` with
`HKLiveWorkoutBuilder` (`.traditionalStrengthTraining`, `.indoor`) started
when the engine starts and ended at `onEnded`. It keeps the app running
with the screen off, collects heart rate, and the builder's
`finishWorkout` writes the workout — **so the phone's `HealthSync` must
not also write one for a watch-owned session**: the owner writes Health,
the non-owner never does (the same rule as the record). Heart rate
samples reach the phone through Health itself; Signals gains a
"Session heart rate" line (average and peak for the last session) read
from HealthKit, phone-side, no new storage.

Drawings on the watch: `MoveDiagram.swift` is Canvas-based SwiftUI with
no UIKit; move it to `Core/` only if it compiles for watchOS without
change, and show the `.signature` panel on the rest phase. If it needs
work, leave it on the phone and ship the watch without plates — the
count and the name are the wrist's job.

### 2.7 Starting from the watch

`WrkTimeWatch/WatchTodayView.swift`: a list in the document register —
today's session (or rest-day offer), the practice, the extras the phone
offers (saved routines, the composed extra, a due test), and "Running on
your phone" when the link reports a phone-owned session, tapping into the
mirror. It reads the same store; it builds routines with the same
`PlannedSession.routine` read seam and `ExtraSession.build`. A session
started here is watch-owned and recorded by the watch.

### 2.8 Complications

`WrkTimeWidgets` already exists for the phone; add a watch widget
extension target `WrkTimeWatchWidgets` with one accessory family set
(`.accessoryRectangular`, `.accessoryCircular`, `.accessoryInline`)
reading `TodaySnapshot` from the app group: today's session name and
shape, marks this week, and — while a session runs — the running phase
with its end date (the system ticks it). Reuse `Shared/TodaySnapshot`.

## 3. Build order and parallelism

Phase 0 is sequential and must land first; it is the spine every other
phase builds on. Phases 1–4 can run as parallel agents in worktrees once
Phase 0 is committed, provided each agent touches only the files named
for it and the interfaces in §2.4 are created in Phase 0 as stubs.

| Phase | Agent | Files | Proof |
|---|---|---|---|
| 0 | one | `Core/` carve-out; `SessionLink` types + stub class; watch target and widget target in the pbxproj; `ActiveSession.ownerRaw` | iPhone app + tests build and pass; `xcodebuild -scheme WrkTimeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)'` builds an empty watch app |
| 1 | A | `WrkTimeWatch/WatchTimerView.swift`, `WatchHaptics.swift`, field/count rendering | engine-driven UI on the watch simulator, screenshots of work, rest, open set, finished |
| 2 | B | `Core/SessionLink.swift` full implementation; phone-side install in `WorkoutTimerView`; watch-side install | `SessionLinkTests`: ownership, reps routing, reconnect resend, stale messages ignored; manual: start on phone, see on watch, count on watch, record has it |
| 3 | C | `WrkTimeWatch/WatchWorkout.swift`; Signals heart-rate line on the phone | watch simulator records a workout; phone reads HR after sync |
| 4 | D | `WatchTodayView`, starting each kind of session; `WrkTimeWatchWidgets` complications | list shows what the phone shows; a watch-started session records once |
| 5 | one | Device pass on her watch and phone; HANDOFF, CLAUDE.md, the one-pager and release notes | the six "done" points in §0, each ticked by hand |

Agents must not edit `project.pbxproj` concurrently; all project-file
edits are Phase 0 (and Phase 5 if needed). Each agent commits in its
worktree; the integrator merges, runs the full suite, and installs.

## 4. Tests to write (in `WrkTimeTests`, since the code is in `Core/`)

- `SessionLinkTests`: a `.running` from the phone makes a watch-side
  mirror engine read the same phase at the same elapsed; a `.reps` from
  the non-owner lands in the owner's counts; a `.reps` arriving after
  `.ended` is dropped; `.transport(.endSet)` on the owner calls `endSet`
  and a later `.running` shows the rest; an `ActiveSession` without
  `ownerRaw` decodes as phone-owned.
- `OwnershipTests`: a watch-owned session ending writes one `RoutineRun`
  on the watch's context and none on the phone's (simulate with two
  in-memory contexts and two `SessionLink` stubs wired back to back).
- `WatchScheduleTests`: the watch timer's position line, count string and
  Done/skip choice match the phone's for every `SessionMode`.
- Snapshot tests are untouched; `LibrarySnapshotTests` must still pass
  after the `Core/` move (it is a move, not a change).

## 5. Risks and how to take them

- **The pbxproj.** Hand-edit with the widget target as the template; add
  ids in the existing `1A…` series; build after every edit; commit the
  project file alone as its own commit so a bad edit is one revert.
- **Two writers.** The ownership rule is the whole defence. Any path that
  could write a record on the non-owner is a bug of the documented shape;
  put recording behind `engine.onEnded` on the owner and nowhere else.
- **Swift 6 concurrency on `WCSessionDelegate`.** The delegate is called
  off the main actor; hop with `Task { @MainActor in … }` and keep
  `SessionLink` `@MainActor`.
- **CloudKit on the watch simulator** has no account; the store falls back
  to local exactly as the phone does (`Store` already handles it).
- **Her watch model is unknown.** Ask before Phase 5; the simulator pass
  uses Series 10 46mm and the SE 40mm for the small face.
- **Installing.** The watch app rides inside the iPhone app;
  `xcrun devicectl device install app` on the iPhone installs both when
  the watch is paired and "Automatically install apps" is on; otherwise
  the Watch app on the phone offers it. Say which happened.

## 6. Voice on the wrist

Fewer words, same voice. "Set 2 / 12" not "Set 2 of 12 sets". "Next up"
then the move. "Done" on the open set. "Rest" on the rest. Never an
exclamation mark, never an emoji, never "Great job". The finish screen
says one line: "One mark on the season." or "Kept with your own
workouts." exactly as the phone does (`completionRecordNote`).
