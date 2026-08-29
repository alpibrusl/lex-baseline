# divergence.lex — is a counterparty's over-claiming a pattern, or a bad month?
#
# Every settlement made against a measured volume produces a pair: what was
# CLAIMED and what was MEASURED. One pair says nothing — measurement is
# imperfect and a baseline is a model, so any single settlement can miss in
# either direction. A sequence says more, because of one asymmetry:
#
#   honest measurement error is symmetric around zero.
#   systematic over-claiming is not.
#
# A counterparty whose claim exceeds the meter in nine settlements out of ten is
# not making measurement errors. That is a sign test, it needs no model of the
# error distribution, and it runs on data a settlement chain already carries.
#
# ---- What this is NOT ------------------------------------------------
#
# It is not evidence of fraud, and it must never be reported as such. Three
# reasons, all of which apply to real data:
#
#   dependence   consecutive settlements at one site share equipment, weather
#                and process. The sign test assumes independent trials; these
#                are not independent, so the p-value here is OPTIMISTIC — the
#                true significance is weaker than the number suggests.
#   selection    a baseline method that is biased for a site's load shape will
#                produce persistent one-sided error with nobody gaming anything.
#                That is a badly chosen method, and it is the counterparty's
#                grievance, not their guilt.
#   magnitude    a persistent 0.4% bias can be statistically overwhelming and
#                commercially irrelevant. Significance is not size.
#   power        the sign test is weak on short histories. At ten settlements it
#                cannot reach p = 0.05 unless nine are one-sided, so eight of
#                ten — a realistic gaming shape, since nobody over-claims every
#                time — sits at p = 0.055. Watch is therefore set at 0.10 and
#                Investigate at 0.01: a screen should be sensitive where the
#                cost of being wrong is a second look, and strict where it is
#                someone accusing a counterparty.
#
# So a flag here means "look at this relationship", never "this party is
# cheating". Getting that wrong would be over-claiming about over-claiming.

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.math" as math

import "std.list" as list

# One settled window: what the seller claimed against what the meter showed.
type Observation = { declared_wh :: Int, measured_wh :: Int }

# What to do about it, in the language of an operator's queue rather than a
# court's. Insufficient is a first-class answer: most relationships will not
# have enough history, and saying so beats inventing confidence.
type Flag = Insufficient | Consistent | Watch | Investigate

type Finding = { n :: Int, over :: Int, under :: Int, ties :: Int, median_bias_pct :: Int, p_value :: Float, flag :: Flag }

# Fewer than this and the sign test cannot separate a pattern from a run of
# luck: eight straight one-sided results is p = 0.004, seven is 0.008, but at
# n = 5 even a perfect sweep is p = 0.03 on one tail and reads as noise beside
# any real-world dependence.
fn min_observations() -> Int {
  8
}

# A bias smaller than this is not worth an operator's morning however
# significant it is. Measurement drift, method mismatch and rounding all live
# down here.
fn material_bias_pct() -> Int {
  5
}

fn bias_pct(o :: Observation) -> Int {
  if o.measured_wh <= 0 {
    0
  } else {
    (o.declared_wh - o.measured_wh) * 100 / o.measured_wh
  }
}

fn count_where(obs :: List[Observation], f :: (Observation) -> Bool) -> Int {
  list.fold(obs, 0, fn (n :: Int, o :: Observation) -> Int {
    if f(o) {
      n + 1
    } else {
      n
    }
  })
}

# C(n, k) built multiplicatively in Float. Factorials overflow Int by n = 21;
# this stays finite to well past any settlement history.
fn choose(n :: Int, k :: Int) -> Float {
  if k < 0 or k > n {
    0.0
  } else {
    list.fold(list.range(0, min_int(k, n - k)), 1.0, fn (acc :: Float, i :: Int) -> Float {
      acc * int.to_float(n - i) / int.to_float(i + 1)
    })
  }
}

fn min_int(a :: Int, b :: Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

# One-sided binomial tail: the chance of seeing AT LEAST this many one-sided
# results if the direction were a coin flip. Ties are excluded from n before
# this is called, as a sign test requires.
fn tail_p(n :: Int, k :: Int) -> Float {
  if n <= 0 {
    1.0
  } else {
    let total := list.fold(list.range(k, n + 1), 0.0, fn (acc :: Float, i :: Int) -> Float {
      acc + choose(n, i)
    })
    total / math.pow(2.0, int.to_float(n))
  }
}

# The middle bias, not the mean: one catastrophic settlement should not decide
# whether a relationship looks systematic.
fn median_bias(obs :: List[Observation]) -> Int {
  let sorted := list.sort_by(list.map(obs, bias_pct), fn (v :: Int) -> Int {
    v
  })
  let n := list.len(sorted)
  if n == 0 {
    0
  } else {
    match nth_int(sorted, n / 2) {
      Some(v) => v,
      None => 0,
    }
  }
}

fn nth_int(xs :: List[Int], i :: Int) -> Option[Int] {
  if i < 0 {
    None
  } else {
    if i == 0 {
      list.head(xs)
    } else {
      nth_int(list.tail(xs), i - 1)
    }
  }
}

# Both conditions or neither. Significance without magnitude is drift; a large
# bias in one or two settlements is a bad month. Only a pattern that is both
# persistent AND material is worth interrupting someone about.
fn assess(obs :: List[Observation]) -> Finding {
  let over := count_where(obs, fn (o :: Observation) -> Bool {
    o.declared_wh > o.measured_wh
  })
  let under := count_where(obs, fn (o :: Observation) -> Bool {
    o.declared_wh < o.measured_wh
  })
  let ties := list.len(obs) - over - under
  let n := over + under
  let p := tail_p(n, over)
  let bias := median_bias(obs)
  let flag := if n < min_observations() {
    Insufficient
  } else {
    if bias < material_bias_pct() {
      Consistent
    } else {
      if p <= 0.01 {
        Investigate
      } else {
        if p <= 0.1 {
          Watch
        } else {
          Consistent
        }
      }
    }
  }
  { n: n, over: over, under: under, ties: ties, median_bias_pct: bias, p_value: p, flag: flag }
}

fn flag_str(f :: Flag) -> Str {
  match f {
    Insufficient => "insufficient",
    Consistent => "consistent",
    Watch => "watch",
    Investigate => "investigate",
  }
}

# Deliberately carries the caveat with the number. Anyone reading this JSON is
# one copy-paste from putting it in front of a counterparty.
fn to_json(f :: Finding) -> Str {
  str.join(["{\"settlements\":", int.to_str(f.n), ",\"over\":", int.to_str(f.over), ",\"under\":", int.to_str(f.under), ",\"ties\":", int.to_str(f.ties), ",\"median_bias_pct\":", int.to_str(f.median_bias_pct), ",\"p_value\":", float.to_str(f.p_value), ",\"flag\":\"", flag_str(f.flag), "\",\"note\":\"screening signal only: settlements at one site are not independent, so this p-value is optimistic; a biased baseline method produces the same pattern as gaming\"}"], "")
}

