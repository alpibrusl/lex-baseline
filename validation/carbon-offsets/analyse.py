#!/usr/bin/env python3
"""The over-claim screen on California forest carbon offsets.

Data: CarbonPlan's per-project crediting estimates for the CARB compliance
Improved Forest Management programme (carbonplan/forest-offsets-web), which
accompany Badgley et al., "Systematic over-crediting in California's forest
carbon offsets program". Public, and small enough to commit.

Run naively the screen flags every major developer. Run correctly — scoring
each project against the population, so the shared protocol flaw is netted out
— it clears all of them. The over-crediting is real and it belongs to the
methodology, not to any participant.
"""
import json, statistics, sys, os
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "uk-balancing"))
from screen import assess  # cross-checked against src/divergence.lex

d = json.load(open(os.path.join(os.path.dirname(__file__), "crediting.json")))
a = [x for x in d if x.get("over_crediting") and x["over_crediting"].get("percent")]
for x in a:
    x["_pct"] = x["over_crediting"]["percent"][1]   # published [low, central, high]
    x["_over"] = x["over_crediting"]["arbocs"][1]

med = statistics.median(x["_pct"] for x in a)
issued = sum(x["arbocs"] for x in a)
over = sum(x["_over"] for x in a)
print(f"projects with an estimate : {len(a)} of {len(d)}")
print(f"credits issued            : {issued/1e6:.1f}M")
print(f"estimated over-credited   : {over/1e6:.1f}M  ({over/issued:.1%})")
print(f"population median         : {med:.1%}   (under-credited projects: {sum(1 for x in a if x['_pct']<0)})")

by = defaultdict(list)
for x in a:
    for dev in (x.get("developers") or ["(undisclosed)"]):
        by[dev].append(x)

print("\nNAIVE — issuance against the re-estimate:")
for dev, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    if len(xs) < 8: continue
    f = assess([{"declared_wh": int(x["arbocs"]), "measured_wh": int(x["arbocs"] - x["_over"])} for x in xs])
    print(f"  {dev:<24} {len(xs):>3} proj  median +{f['median_bias_pct']}%  {f['over']}/{f['n']}  {f['flag']}")

print("\nADJUSTED — scored against the population, netting out the protocol:")
for dev, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    if len(xs) < 8: continue
    f = assess([{"declared_wh": int(1e6*(1+x["_pct"])), "measured_wh": int(1e6*(1+med))} for x in xs])
    own = statistics.median(x["_pct"] for x in xs)
    print(f"  {dev:<24} {len(xs):>3} proj  own {own:+.1%} vs pop {med:+.1%}  "
          f"{f['over']}/{f['n']} worse  p={f['p_value']:.3f}  {f['flag']}")
