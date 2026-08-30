#!/usr/bin/env python3
"""Build (declared, measured) pairs per BM unit from public Elexon data.

PN  — the unit's Final Physical Notification: what it declared it would do.
B1610 — metered actual output for the same half hour.

One settlement period sampled across many days, so the pairs for a unit are at
the same time of day and a diurnal pattern cannot be mistaken for bias.
"""
import json, sys, urllib.request, urllib.error
from datetime import date, timedelta
from collections import defaultdict

BASE = "https://data.elexon.co.uk/bmrs/api/v1"

def get(url, tries=3):
    for i in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=90) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            if i == tries - 1:
                print(f"  ! {e}", file=sys.stderr); return {"data": []}
    return {"data": []}

def pn_mwh(rows):
    """Integrate each unit's declared level over the period, trapezoidally.

    PN arrives as segments with a level at the start and end of each; the
    declared energy is the area under that, not the last level seen.
    """
    out = defaultdict(float)
    for r in rows:
        try:
            t0 = r["timeFrom"]; t1 = r["timeTo"]
            hrs = (int(t1[11:13]) * 60 + int(t1[14:16]) - int(t0[11:13]) * 60 - int(t0[14:16])) / 60.0
            if hrs < 0: hrs += 24.0
            out[r["bmUnit"]] += (r["levelFrom"] + r["levelTo"]) / 2.0 * hrs
        except Exception:
            continue
    return out

PERIOD = 20
days = int(sys.argv[1]) if len(sys.argv) > 1 else 20
start = date(2026, 8, 20)
pairs = defaultdict(list)
for i in range(days):
    d = (start - timedelta(days=i)).isoformat()
    pn = pn_mwh(get(f"{BASE}/datasets/PN?settlementDate={d}&settlementPeriod={PERIOD}&format=json").get("data", []))
    act = {}
    for r in get(f"{BASE}/datasets/B1610?settlementDate={d}&settlementPeriod={PERIOD}&format=json").get("data", []):
        if r.get("quantity") is not None:
            act[r["bmUnit"]] = act.get(r["bmUnit"], 0.0) + float(r["quantity"])
    n = 0
    for u, declared in pn.items():
        if u in act:
            pairs[u].append({"date": d, "declared_mwh": round(declared, 4), "measured_mwh": round(act[u], 4)})
            n += 1
    print(f"  {d}  units paired: {n}", file=sys.stderr)

json.dump(pairs, open("pairs.json", "w"), indent=1)
print(f"units: {len(pairs)}  total pairs: {sum(len(v) for v in pairs.values())}")
