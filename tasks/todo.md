# WrkTime reorganization — phased plan (22 Aug 2026)

Goal restated: build strength and get lean, as a complete beginner, at home,
with the app organized around *movement* rather than around the drawer the
implement came out of. Nothing below reaches the Claude API without explicit
approval; every phase is local arithmetic and data until Phase 6.

Coach panel (women's strength coach, fat-loss coach, physiologist) consulted
locally on 22 Aug; their brief is summarized in §0 and drives the choices.

## 0. What the coaches said (the parts that shape the plan)

- Rep-based strength sets are the base: 3 sets, 8–12 reps, stop 1–2 reps in
  reserve, 60–90 s rest, slow lower. AMRAP intervals are conditioning, not
  muscle — honest copy should say so. A third mode, EMOM strength (one hard set
  of 5–8 every minute, two moves alternating, 10–16 min) maps onto the timer
  and is the clean way to practise the heavy bells.
- Week for five targets: full body ×3 (rep mode), one EMOM, one AMRAP. Never
  push/pull/legs with five moves a day.
- The current pace rule (18 reps/min) measures speed, not effort, and cannot
  fire on rep sets. Replace with double progression: every set hits 12 at RIR 2
  two sessions running → offer the next load. Offer-never-apply stays.
- Baseline test: six moves, one per pattern, fixed loads, max tempo reps to
  RIR 2, under 25 min, retest every 6 weeks. Working load = test load if score
  8–15; down if under 8; up (or intensify) if over 15.
- Ordering: position first (standing → kneeling → floor, never back up), then
  at most one or two implement changes, then compound before isolation.
- Lean: strength base untouched, steps on the pad (Whoop already sees them),
  one conditioning session, Whoop amber = drop a set, red ×2 = walk. No
  fat-placement language, no rate promises.
- Taxonomy: planner programs by **pattern** (squat, hinge, lunge, push,
  pull, carry, core anti-rotation / flexion / extension); UI groups by
  **position**; equipment becomes a constraint, not a category.
- Most valuable purchase was an adjustable pair 5–25 lb. Your new kettlebells
  (9/13/18/35) and singles (10/15) cover most of that ladder for two-hand and
  single-arm work; the remaining gap is a heavier *pair* for bilateral
  dumbbell moves, and a band anchor.

## 1. Equipment audit — state after your answers

Ladder the app will know, in lb:
- Pairs: 2 · 3 · 5                      (gap above 5 — see note)
- Singles: 10 · 15                      (15 is new)
- Rings: 5 · 8 · 10
- Beam: 15
- Kettlebells: 9 · 13 · 18 · 35         (9, 13, 35 are new)
- Walking pad · bodyweight. **No band** — never bought; drawer stays off, band
  moves drop out of the audit. Posture reset is rewritten without them (kept,
  hers to edit).

Decisions proposed:
- `singleDumbbell.availableLoadsPounds` → `[10, 15]`; `kettlebell` → `[9, 13, 18, 35]`.
  Labels become "One 15 lb dumbbell", "13 lb kettlebell". No new enum cases —
  the implement types have not changed, only their loads.
- Nothing retired now. Retirement is a test outcome: after the baseline, any
  load no pattern uses is switched off via the existing `ownedEquipment`
  drawer (which already repairs written weeks).
- The 35 lb bell is deliberately held back from the planner's rotation until
  the baseline says the 18 scored over 15 on hinge — the app should never hand a
  first-time lifter a 35 lb bell by default. Implemented as a per-load
  "unlocked" flag on the ladder, unlocked by her hand (the same `MoveOverride`
  path a step-up takes).

## 2. Phases

### Phase 0 — Stop the bleeding (no new design)
- [ ] Build + test the uncommitted tree on the simulator; install on the phone.
      This alone restores the "what to pick up" line on the timer
      (`WorkoutTimerView.swift:693`).
- [ ] Commit the August work in a few readable commits (kit, core set, reviewer,
      widget, timer label). Three weeks uncommitted is the disorganization.
- [ ] Equipment loads above (§1). Validator and pickers read the ladder, so no
      other code changes; tests cover `label(forLoad:)` and the new loads.

### Phase 1 — Give every move a shape (taxonomy, data only)
- [ ] Add `MovePattern` (squat, hinge, lunge, pushH, pushV, pullH, pullV, carry,
      coreAntiRotation, coreFlexion, coreExtension, mobility) and
      `Position` (standing, kneeling, floor) as a lookup table beside the library
      (`MoveTaxonomy`, same shape as `MoveMuscles`) — **not** stored fields, so no
      routine on disk changes shape and the decoder rule in CLAUDE.md holds.
- [ ] Names lose their implement prefix where the implement is a parameter, not
      the move: "Row" with equipment variants, instead of Beam/Ring/Kettlebell/
      Dumbbell row as four moves. Kept as an alias table so stored routines,
      `SetLog` rows and `MovePreference` keys still resolve. (Her refusals match
      by containment — aliasing must preserve that.)
- [ ] Test: every strength move has a pattern and a position; every pattern has
      at least one move per owned-kit level.

### Phase 2 — Sessions that flow
- [ ] `MoveLibrary.rotation` (the single builder — not a second one) gains a
      *shape*: cover patterns first (one lower, one pull, one push, one carry/
      core, one free), then order standing → kneeling → floor, then minimise
      implement changes (≤2). Same inputs, same refusal rules, new ordering.
- [ ] `PlanRepair` and `ExtraSession` inherit it, since both go through
      `rotation`.
- [ ] UI: Moves tab grouped by **position** with pattern chips as filters;
      equipment becomes a line on the row, not a section. Seeded routines
      re-ordered to the same rule.
- [ ] Warm-up unchanged (it is flow, already standing→floor).

### Phase 3 — Two session modes (plus EMOM)
- [ ] `SessionMode` on `IntervalRoutine` — Optional, like every stored
      addition: `.interval` (today's AMRAP-style, default for old data),
      `.reps` (sets × reps, rest is the timed phase, work is untimed "until you
      hit the target at RIR 2"), `.emom` (60 s slots, alternating two moves).
- [ ] Engine: `.reps` work phases are open-ended (tap to end set, counts
      during the rest as now — `setEnding(before:)` already exists);
      `.emom` is a written-out sequence the builder can already express.
- [ ] Field register on the timer for `.reps`: the dark field rises with the
      *set count*, not a clock. One design decision to review with you.
- [ ] Whoop summary, `SetLog`, Live Activity each get the mode's honest line
      ("3 × 10 at 13 lb", not "3 × 40 s").
- [ ] Week shape (offline, arithmetic): Mon/Wed/Fri reps, one EMOM, one AMRAP.
      `OfflinePlanner` writes it; nothing asks the model.

### Phase 4 — Baseline test and working loads
- [ ] `BaselineTest`: six moves, one per pattern, fixed load, tempo reps to
      RIR 2, under 25 min, recorded as a `RoutineRun` + six `SetLog` rows (no
      mark — it is not the plan). Offered on Today when none exists or the last
      is 6 weeks old, never on a red recovery day.
- [ ] Outcome → `WorkingLoad` per pattern (test load / down / up by the 8–15
      rule), written through `MoveOverrides` so every surface already honours
      it. Retire-kit and unlock-35-lb prompts fall out of the same result.
- [ ] Copy: "Where you are", never a grade. Beginner framing throughout.

### Phase 5 — Progression that means "too light"
- [ ] Replace the pace ceiling in `LoadProgression` with double progression:
      all sets ≥ 12 at the current load in two consecutive **rep-mode**
      sessions → offer next load on the ladder. Interval sessions never qualify.
- [ ] Bridge rule for big jumps (>30 %): offer "same load, harder" first
      (pause / slow lower / 1.5 reps / unilateral) — one intensifier per move per
      block — and the next load second. Both are still her tap.
- [ ] Overrides: withhold the offer after 3 red Whoop days or loosely counted
      sets (rows without `setSeconds`).
- [ ] Tests replace `repsPerMinuteCeiling` cases.

### Phase 6 — The planner learns the new vocabulary (needs your OK per call)
- [ ] `PlanContext` carries pattern coverage, working loads, baseline age,
      mode split, and Whoop state. Schema gains `mode` per session; validator
      rejects a mode the week shape does not allow.
- [ ] Prompt rewrite with the coach rules above as explicit constraints.
- [ ] First live call only with your explicit approval, in the simulator,
      usage reported.

### Phase 7 — Aesthetics
- [ ] Moves tab by position with a compact row: name · pattern · load line ·
      small strip. Section numerals stay (Almanac).
- [ ] Timer `.reps` field (set-count rise), EMOM minute ticks on the field edge.
- [ ] Today card states the mode in one line of the existing voice.
- [ ] Drawings for the deferred kettlebell/core moves remain deferred unless
      you want them prioritized.

## 2b. Amendments from the 22 Aug follow-up (panel + her answers)

- Rest is two numbers: between sets (lower compound 90 s, upper compound 75 s,
  isolation 45–60 s, core 45 s) and between moves (30 s, or 90 s after a big
  lower lift). A labelled **setup buffer** — 20 s position change, 15 s
  implement change, 30 s both — reuses the warm-up pause shape. Rest is never
  lengthened to absorb transitions.
- Session shape: one bell standing (hinge, squat/lunge, row, press/push-up),
  then one floor block to close. ≤ 2 implements; validator rejects 3. Preview
  says what to set out before start.
- AMRAP: 40/20, but 30/30 when any bell above 13 lb is in the round.
- EMOM: set capped at 8 reps / 25 s.
- Rep mode work phase capped at 90 s (safety net, not target).
- Baseline every 4 weeks; weekly check = one move's last set to RIR 1, rotating
  through patterns, plotted on the move sheet.
- 35 lb bell unlocked for the deadlift now with the bridge (3×5 dead-stop,
  then 3×6–8, working bell at 10×3 twice). Goblet squat stays on 18.
- Custom and saved routines are never removed. Rename dropped from the plan.

## 3. Open questions for you
1. Phase ordering: 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 as written, or pull the
   baseline test (4) ahead of modes (3) so your first new week is informed?
2. The 35 lb bell held back until the baseline unlocks it — agree?
3. Rep mode "work" phase: open-ended until you tap, or a generous 90 s cap?
4. Do you want the rename (drop the implement prefix from move names)? It is
   the biggest data-migration risk in the plan and is separable.

## Review
(filled in as phases complete)
