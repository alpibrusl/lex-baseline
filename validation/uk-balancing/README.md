# Validating the over-claim screen on public UK balancing data

**Result: the screen detects a real, statistically strong, systematic one-sided
bias in live money-bearing data — and the bias is not fraud.** That is the most
useful thing this exercise could have produced, and it is the reason the screen
must never be sold as fraud detection.

## What was run

47,240 (declared, measured) pairs across 2,363 GB Balancing Mechanism units,
from [Elexon's open Insights API](https://bmrs.elexon.co.uk/) — no key, no
licence:

- **PN** — a unit's Final Physical Notification: what it declared it would do
- **B1610** — metered actual output for the same half hour

One settlement period (20, i.e. 09:00–09:30) sampled across 20 days, so a
unit's pairs share a time of day and a diurnal pattern cannot masquerade as
bias. 461 units had ≥8 periods of positive output and were screened.

`screen.py` is a reimplementation of `src/divergence.lex`, **cross-checked
against the Lex implementation on fixed vectors before being trusted at
scale** — the same discipline as the wire format spec. If they disagree, the
Python is wrong.

## What it found

| | investigate | watch | consistent |
|---|---:|---:|---:|
| all units (461) | 18 | 34 | 408 |

Strong signals, e.g. `T_KTHLW-1` at a **median +182% over-declaration, 17 of 18
periods one-sided, p = 0.0001**.

And then the finding that matters:

| category | flagged | of |
|---|---:|---:|
| **wind** | **47** | 213 (22%) |
| CCGT | 1 | 18 |
| biomass / hydro / other | 3 | 32 |
| thermal, storage, nuclear, solar | **0** | 38 |
| unknown | 1 | 157 |

Named: Keith Hill Windfarm, Douglas West Extension, Race Bank, Moray East OWF3,
Pogbie, Lochluichart, Sheringham Shoal. Almost every flag is a wind farm.

## Why this is a validation and not an accusation

**A PN is a forecast, not a claim for payment.** A wind farm declaring more than
it metered is doing what a forecast does, and it is paid on metered output
regardless. There is no over-claim, and reporting these units as suspicious
would be exactly the over-claiming this tool exists to detect.

So the screen behaved correctly — it found the strongest one-sided bias in the
data — and the bias is a technology artefact. That is the caveat compiled into
`divergence.lex` (*"a badly chosen baseline produces the same pattern as
gaming"*) showing up in real data on the first attempt.

## What it means for the product

**The screen is only meaningful where the declared quantity is a claim for
payment.** Applied to a forecast it measures forecast bias, which is real,
knowable, and none of a settlement system's business.

## An inconclusive test, reported as inconclusive

The obvious innocent mechanism is curtailment: the System Operator pays a unit
to reduce, so declared exceeds metered with nobody at fault. Netting out
instructed volumes (BOALF acceptances) cleared exactly **one** unit of 52 —
but that test is **underpowered, not negative**: only 9 of 53 flagged units had
any acceptance in the sampled period, and GB wind curtailment concentrates
overnight while this sampled 09:00. A proper test would sample periods 1–10.

The remaining explanation is ordinary wind forecast error. This has not been
demonstrated here and is not claimed.

## Reproducing it

```bash
python3 fetch.py 20        # writes pairs.json  (~40 API calls, no key)
python3 screen.py          # cross-checks the screen against the Lex vectors
```
