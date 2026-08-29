# lex-baseline — the over-claim screen, tested from both directions.
#
# A detector is only useful if it stays quiet. The cases that matter most here
# are the ones that must NOT flag: large but symmetric error, a small
# persistent bias, and a short run of bad luck. A screen that fires on those
# would be worse than none, because someone would act on it in front of a
# counterparty.

import "std.io" as io

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.float" as float

import "../src/divergence" as div

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(label)
  }
}

fn obs(declared :: Int, measured :: Int) -> div.Observation {
  { declared_wh: declared, measured_wh: measured }
}

# A settled window where the claim missed by `pct`, in whichever direction.
fn miss(pct :: Int) -> div.Observation {
  obs(10000 + 100 * pct, 10000)
}

fn flag_of(os :: List[div.Observation]) -> Str {
  div.flag_str(div.assess(os).flag)
}

# ---- it must stay quiet ---------------------------------------------
# Honest measurement is noisy. Ten settlements missing by 30% in ALTERNATING
# directions is a terrible baseline method and not a pattern of over-claiming;
# the screen must not confuse imprecision with bias.
fn test_large_symmetric_error_does_not_flag() -> Result[Unit, Str] {
  let os := [miss(30), miss(0 - 30), miss(25), miss(0 - 25), miss(35), miss(0 - 35), miss(20), miss(0 - 20), miss(28), miss(0 - 28)]
  assert_true(flag_of(os) == "consistent", str.concat("symmetric error, however large, is not over-claiming; got ", flag_of(os)))
}

# Persistent but tiny. Overwhelming statistically — ten out of ten one-sided —
# and commercially irrelevant. Drift, rounding, a method half a percent off.
# Interrupting an operator for this teaches them to ignore the screen.
fn test_a_persistent_but_immaterial_bias_does_not_flag() -> Result[Unit, Str] {
  let os := [miss(1), miss(1), miss(2), miss(1), miss(2), miss(1), miss(1), miss(2), miss(1), miss(1)]
  assert_true(flag_of(os) == "consistent", str.concat("a 1-2% persistent bias is drift, not a case to answer; got ", flag_of(os)))
}

# Three settlements all one way is a coin landing heads three times.
fn test_a_short_run_is_not_a_pattern() -> Result[Unit, Str] {
  let os := [miss(40), miss(35), miss(50)]
  assert_true(flag_of(os) == "insufficient", str.concat("three one-sided settlements is luck, not evidence; got ", flag_of(os)))
}

fn test_no_history_is_insufficient_not_clean() -> Result[Unit, Str] {
  assert_true(div.flag_str(div.assess([]).flag) == "insufficient", "no settlements must read as insufficient, never as consistent — absence of evidence is not a clean bill")
}

# ---- it must fire -----------------------------------------------------
# The Rumford shape: every settlement claims materially more than the meter.
fn test_persistent_material_over_claiming_is_investigated() -> Result[Unit, Str] {
  let os := [miss(40), miss(35), miss(50), miss(45), miss(38), miss(42), miss(55), miss(36), miss(48), miss(41)]
  let f := div.assess(os)
  assert_true(div.flag_str(f.flag) == "investigate" and f.over == 10 and f.under == 0, str.concat("ten material one-sided settlements must be investigated; got ", div.flag_str(f.flag)))
}

# Mostly one-sided, materially — the realistic shape, since nobody over-claims
# every single time.
# Eight of ten is p = 0.055 — the realistic gaming shape, and beyond the reach
# of a sign test at n = 10 under a 0.05 rule. It lands in Watch rather than
# Investigate, which is the honest verdict: worth a look, not worth an
# accusation.
fn test_a_mostly_one_sided_pattern_is_caught() -> Result[Unit, Str] {
  let os := [miss(40), miss(35), miss(0 - 10), miss(45), miss(38), miss(42), miss(0 - 8), miss(36), miss(48), miss(41)]
  let f := div.assess(os)
  assert_true(div.flag_str(f.flag) == "watch" and f.over == 8 and f.under == 2, str.concat("eight of ten materially over-claimed is a watch, not an accusation and not silence; got ", div.flag_str(f.flag)))
}

# Under-claiming is not this screen's business. A seller who is paid LESS than
# it delivered has a grievance, not a case to answer, and flagging it would put
# an operator in front of the wrong counterparty.
fn test_persistent_under_claiming_is_not_flagged() -> Result[Unit, Str] {
  let os := [miss(0 - 40), miss(0 - 35), miss(0 - 50), miss(0 - 45), miss(0 - 38), miss(0 - 42), miss(0 - 55), miss(0 - 36), miss(0 - 48), miss(0 - 41)]
  assert_true(flag_of(os) == "consistent", str.concat("systematic UNDER-claiming is the seller's loss, not a case against them; got ", flag_of(os)))
}

# ---- the arithmetic underneath ---------------------------------------
# Ten one-sided results out of ten is 1/1024 on one tail. If this drifts the
# thresholds mean something other than what the comments claim.
fn test_the_tail_probability_is_right() -> Result[Unit, Str] {
  let p := div.tail_p(10, 10)
  assert_true(p > 0.0009 and p < 0.0011, str.concat("P(10 of 10 one-sided) must be about 1/1024, got ", float.to_str(p)))
}

fn test_an_even_split_is_not_surprising() -> Result[Unit, Str] {
  let p := div.tail_p(10, 5)
  assert_true(p > 0.5 and p < 0.7, str.concat("P(at least 5 of 10) must be just above a half, got ", float.to_str(p)))
}

# Ties carry no direction and must leave the count, or a counterparty whose
# claims match the meter exactly would be diluted toward "consistent".
fn test_exact_matches_are_excluded_from_the_test() -> Result[Unit, Str] {
  let os := [miss(40), miss(35), miss(0), miss(0), miss(50), miss(45), miss(38), miss(42), miss(55), miss(36), miss(48), miss(41)]
  let f := div.assess(os)
  assert_true(f.ties == 2 and f.n == 10, str.concat("exact matches are ties and leave n; got n=", int.to_str(f.n)))
}

# The number travels with its own caveat, because whoever reads this JSON is
# one copy-paste away from showing it to the counterparty it describes.
fn test_the_output_carries_its_own_caveat() -> Result[Unit, Str] {
  let j := div.to_json(div.assess([miss(40), miss(35), miss(50), miss(45), miss(38), miss(42), miss(55), miss(36), miss(48), miss(41)]))
  assert_true(str.contains(j, "screening signal only") and str.contains(j, "not independent"), "the JSON must carry the caveat that this is a screen and the p-value is optimistic")
}

fn results() -> List[(Str, Result[Unit, Str])] {
  [("large_symmetric_error_does_not_flag", test_large_symmetric_error_does_not_flag()), ("a_persistent_but_immaterial_bias_does_not_flag", test_a_persistent_but_immaterial_bias_does_not_flag()), ("a_short_run_is_not_a_pattern", test_a_short_run_is_not_a_pattern()), ("no_history_is_insufficient_not_clean", test_no_history_is_insufficient_not_clean()), ("persistent_material_over_claiming_is_investigated", test_persistent_material_over_claiming_is_investigated()), ("a_mostly_one_sided_pattern_is_caught", test_a_mostly_one_sided_pattern_is_caught()), ("persistent_under_claiming_is_not_flagged", test_persistent_under_claiming_is_not_flagged()), ("the_tail_probability_is_right", test_the_tail_probability_is_right()), ("an_even_split_is_not_surprising", test_an_even_split_is_not_surprising()), ("exact_matches_are_excluded_from_the_test", test_exact_matches_are_excluded_from_the_test()), ("the_output_carries_its_own_caveat", test_the_output_carries_its_own_caveat())]
}

fn report(rs :: List[(Str, Result[Unit, Str])]) -> [io] Int {
  list.fold(rs, 0, fn (n :: Int, r :: (Str, Result[Unit, Str])) -> [io] Int {
    match r {
      (_, Ok(_)) => n,
      (name, Err(why)) => {
        let __p := io.print(str.concat("FAIL ", str.concat(name, str.concat(" — ", why))))
        n + 1
      },
    }
  })
}

# The stdlib is total — there is no `panic` — so a division by zero is the
# raise. `zero` arrives as an argument so it survives constant folding.
fn raise_failure(zero :: Int) -> Int {
  1 / zero
}

fn run_all() -> [io] Unit {
  let failures := report(results())
  if failures == 0 {
    ()
  } else {
    let __p := io.print(str.concat(int.to_str(failures), " test(s) failed"))
    let __boom := raise_failure(0)
    ()
  }
}

