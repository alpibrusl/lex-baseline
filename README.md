# lex-baseline

**Measurement and verification for demand flexibility.** A named, content-addressed baseline method, and a delivered-volume computation any counterparty can replay from the same readings.

## The claim this makes, and the one it does not

Delivered flexibility is the difference between a counterfactual and the meter: what the site *would* have drawn, minus what it did. The meter is measured. **The counterfactual is not** — it is a model output, and no amount of hashing makes it true.

So this package does not try to make it true. It makes it checkable:

- the method is **named**, with every parameter it depends on
- the method is **content-addressed**, so "the method we agreed on" is a hash rather than a description in an email
- the computation is **pure**, so a counterparty re-running it on the same readings gets the same number or has found a real disagreement

That reduces a dispute from *"whose spreadsheet do we believe"* to *"we disagree about the published method"* — smaller, and tractable. It is also the **only** claim this package supports. Do not build a larger one on top of it.

## Two methods

**`Nominated`** takes the baseline from what the controller declared it was about to do. Exact when the declaration is honest, worthless when it is not: the party being paid for the shed is the party stating what it would otherwise have drawn. Cheap, and fine where the controller is trusted or independently constrained — but never present it as measurement.

**`HighXofY`** is the demand-response standard: average the same clock interval across the X highest of the Y most recent comparable days, optionally adjusted for how the site is behaving today. Nobody's word is required. It needs history, it is only as good as its notion of a comparable day, and it is what an aggregator and a DSO can argue about on equal terms.

```lex
let spec := { method: HighXofY({ x: 3, y: 5, adjust_cap_pct: 20, adjust_window_ms: 3600000 }),
              interval_ms: 900000, version: 1 }

method.fingerprint(spec)   # the method's identity — goes on the trail
compute.deliver(spec, from_ms, to_ms, actual, nominated_w, history, offsets)
```

## Decisions worth knowing about

**What counts as a comparable day is the caller's problem.** `HighXofY` takes the candidate days as an argument rather than deriving them. Whether a Sunday compares to a Tuesday, or a holiday to a working day, is a question about the site and its contract — encoding a guess here would bury a contractual assumption inside a library.

**The same-day adjustment applies to the run-up, never the event window.** Adjusting on the event period would let the curtailment being measured move its own baseline. The result is clamped by `adjust_cap_pct`, because an unbounded ratio turns a quiet morning into a large paid delivery. The adjustment window is part of the hashed spec: "we adjusted on the preceding hour" and "we adjusted on the preceding three" are different methods, and neither party should get to pick afterwards.

**Days are ranked highest-first.** The programme convention biases the counterfactual upward: a baseline that is too low understates delivery, and the party at risk of that is the one being measured.

**An underperforming shed is a zero, not a debt.** A window where the site drew more than its baseline delivers nothing. Netting a negative against another window would pay the average of a promise kept and a promise broken.

**Everything is integer.** Power in whole watts, time in epoch milliseconds, energy as `W × ms ÷ 3_600_000` with the division done once at the end. A settled volume should never turn on a float comparison, and rounding should not accumulate across a long window.

## What it does not do

It does not read a meter, talk to a database, or know what a charge point is. Readings in, watt-hours out.

## License

Matches the rest of the lex ecosystem.
