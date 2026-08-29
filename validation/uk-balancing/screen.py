#!/usr/bin/env python3
"""The over-claim screen, reimplemented from lex-baseline/src/divergence.lex.

Cross-checked against the Lex implementation on fixed vectors before being
trusted at scale — the same discipline as the wire format. If they disagree,
this file is wrong, not the Lex one.
"""
from math import comb

MIN_OBS = 8
MATERIAL_PCT = 5

def bias_pct(o):
    return 0 if o["measured_wh"] <= 0 else (o["declared_wh"] - o["measured_wh"]) * 100 // o["measured_wh"]

def tail_p(n, k):
    if n <= 0: return 1.0
    return sum(comb(n, i) for i in range(k, n + 1)) / (2 ** n)

def median_bias(obs):
    xs = sorted(bias_pct(o) for o in obs)
    return xs[len(xs) // 2] if xs else 0

def assess(obs):
    over = sum(1 for o in obs if o["declared_wh"] > o["measured_wh"])
    under = sum(1 for o in obs if o["declared_wh"] < o["measured_wh"])
    ties = len(obs) - over - under
    n = over + under
    p = tail_p(n, over)
    bias = median_bias(obs)
    if n < MIN_OBS:            flag = "insufficient"
    elif bias < MATERIAL_PCT:  flag = "consistent"
    elif p <= 0.01:            flag = "investigate"
    elif p <= 0.10:            flag = "watch"
    else:                      flag = "consistent"
    return {"n": n, "over": over, "under": under, "ties": ties,
            "median_bias_pct": bias, "p_value": p, "flag": flag}

if __name__ == "__main__":
    # Cross-check against vectors emitted by the Lex implementation.
    def m(pct): return {"declared_wh": 10000 + 100 * pct, "measured_wh": 10000}
    cases = {
      "all-over-10":  [m(x) for x in (40,35,50,45,38,42,55,36,48,41)],
      "eight-of-ten": [m(x) for x in (40,35,-10,45,38,42,-8,36,48,41)],
      "symmetric":    [m(x) for x in (30,-30,25,-25,35,-35,20,-20,28,-28)],
      "tiny-bias":    [m(x) for x in (1,1,2,1,2,1,1,2,1,1)],
      "short":        [m(x) for x in (40,35,50)],
      "under":        [m(x) for x in (-40,-35,-50,-45,-38,-42,-55,-36,-48,-41)],
    }
    bad = 0
    # Emitted by src/divergence.lex — the authoritative implementation.
    LEX_VECTORS = """all-over-10|10|10|42|investigate|0.0009765625
eight-of-ten|10|8|40|watch|0.0546875
symmetric|10|5|20|consistent|0.623046875
tiny-bias|10|10|1|consistent|0.0009765625
short|3|3|40|insufficient|0.125
under|10|0|-41|consistent|1"""
    for line in LEX_VECTORS.strip().splitlines():
        label, n, over, bias, flag, p = line.strip().split("|")
        got = assess(cases[label])
        ok = (got["n"] == int(n) and got["over"] == int(over)
              and got["median_bias_pct"] == int(bias) and got["flag"] == flag
              and abs(got["p_value"] - float(p)) < 1e-9)
        if not ok:
            bad += 1
            print(f"  MISMATCH {label}: lex={n},{over},{bias},{flag},{p} py={got}")
    print("ok  python screen matches the Lex implementation on all vectors" if not bad
          else f"FAIL {bad} vector(s) disagree")
