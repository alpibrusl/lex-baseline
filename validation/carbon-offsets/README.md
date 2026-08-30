# The same screen, on California forest carbon offsets

**Second market, same lesson: the dominant systematic bias belongs to the
methodology, not to any counterparty — and a naive run would have named three
real companies for it.**

## The data

CarbonPlan's per-project crediting estimates for the CARB compliance Improved
Forest Management programme, published alongside Badgley et al., *"Systematic
over-crediting in California's forest carbon offsets program"*. 74 projects, 65
with an estimate, from
[carbonplan/forest-offsets-web](https://github.com/carbonplan/forest-offsets-web).

Reproduces the published headline, which is how we know the join is right:

| | |
|---|---|
| credits issued (analysed set) | 102.1M |
| estimated over-credited | **30.5M — 29.9%** |
| CarbonPlan's published figure | 30.0M — 29.4% |
| projects *under*-credited | 12 of 65 |

## Run naively, it accuses everyone

| developer | projects | median | | |
|---|---:|---:|---|---|
| Blue Source | 15 | +49% | 15/15 over | **investigate** |
| Finite Carbon | 18 | +25% | 16/18 over | **investigate** |
| New Forests | 11 | +15% | 9/11 over | watch |

## Run correctly, it clears all of them

Score each project against the **population** rather than against zero, so the
shared protocol flaw is netted out and only a developer-specific excess
survives:

| developer | own median | vs population | | |
|---|---:|---:|---|---|
| Blue Source | +33.0% | +25.3% | 9/14 worse, p=0.212 | consistent |
| Finite Carbon | +20.3% | +25.3% | 7/18 worse, p=0.881 | consistent |
| New Forests | +13.4% | +25.3% | 5/11 worse, p=0.726 | consistent |

**No developer is over-credited by more than the protocol itself explains.**
That is also the paper's own conclusion — the over-crediting follows from
"ecological and statistical failures in its design" — and the screen reaches it
from the data.

## Why this is the important result

This is the second dataset in a row where the naive signal was a **method
artefact**:

| market | naive flags | actual cause |
|---|---|---|
| GB balancing | 47 of 52 wind farms | a PN is a forecast, not a claim |
| CA forest offsets | all 3 major developers | the CARB protocol over-credits ~25% |

Two markets, two mechanisms, same shape. The conclusion is not that the screen
is unreliable — it found a real, large, statistically robust bias both times.
It is that **the first thing a claim-versus-measurement screen detects is a
broken methodology**, and only after netting that out can it say anything about
a counterparty.

That reorders the product. The screen is a **methodology auditor** first and a
counterparty screen second — and the first job is the one regulators, registries
and standard-setters are actually buying.

## The caveat that stays

Both sides here are models: an issuance computed under a protocol, and a
re-estimate computed by researchers. The screen measures **persistent material
disagreement between two models**, not truth. In the GB case there was at least
a meter on one side; here there is not.

## Reproducing it

```bash
python3 analyse.py
```

Uses `../uk-balancing/screen.py`, which is cross-checked against
`src/divergence.lex` on vectors emitted by the Lex implementation.
