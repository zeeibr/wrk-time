# Design direction

The approved lane is **Almanac** (lane G of round three).

`design-lane-almanac.html` in this folder is the original mockup: five screens
at true iPhone size — Today, mid-set, the routine builder, Progress, and the
lock screen with a Live Activity. Open it in a browser. It is self-contained,
with no external assets.

## Where it came from

Almanac is a synthesis of three earlier directions:

- **Season** supplied the character — oat ground, slab serif, the generative
  growth form where one mark is one finished session, and the copy voice.
- **Baseline** supplied the bones — hairline rules, ruled tables, the marginal
  index, mono labels, optical alignment.
- **Signal** supplied the timer — the draining field with the count knocked out
  of its edge, and the lock-screen Live Activity.

## What the build must preserve

1. **The register change.** Document screens and the field are two different
   worlds, and the switch between them is the idea. Do not soften it.
2. **Saffron discipline.** It marks a live round and today's mark. Nothing else.
3. **One mark is one finished session.** A session started and abandoned does
   not earn a mark. The model enforces this with `completedAt`.
4. **Fasting is an input, not a feature.** One cell on Today, one stated input
   to the projection. It never gets a tab or a hero screen.
