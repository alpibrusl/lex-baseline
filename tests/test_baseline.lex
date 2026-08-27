# lex-baseline — method.lex + compute.lex tests.
#
# The claim this package supports is narrow and worth testing exactly: not that
# the baseline is right, but that the method is pinned and the computation is
# replayable. So the load-bearing tests are the fingerprint ones — same method,
# same hash; any parameter changed, different hash — and the determinism one.
#
# The arithmetic tests use a depot at 22 kW held to 7 kW for an hour, so the
# expected numbers are checkable by hand: 15 kW off for 3600 s is 15 000 Wh.

import "std.io" as io

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "../src/method" as method

import "../src/compute" as compute

fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn fail(why :: Str) -> Result[Unit, Str] {
  Err(why)
}

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    pass()
  } else {
    fail(label)
  }
}

# ---- Fixtures ----------------------------------------------------------
fn t0() -> Int {
  1000000000
}

fn hour() -> Int {
  3600000
}

fn day() -> Int {
  86400000
}

fn interval() -> Int {
  900000
}

# Four quarter-hourly readings at a steady power, starting at `from`.
fn steady(from :: Int, w :: Int) -> List[method.Reading] {
  list.map([0, 1, 2, 3], fn (i :: Int) -> method.Reading {
    { ts_ms: from + i * interval(), w: w }
  })
}

fn nominated_spec() -> method.Spec {
  { method: Nominated, interval_ms: interval(), version: 1 }
}

fn high_spec(x :: Int, y :: Int, cap :: Int, adj_ms :: Int) -> method.Spec {
  { method: HighXofY({ x: x, y: y, adjust_cap_pct: cap, adjust_window_ms: adj_ms }), interval_ms: interval(), version: 1 }
}

fn no_history() -> List[List[method.Reading]] {
  []
}

fn no_offsets() -> List[Int] {
  []
}

# ---- The fingerprint is the point --------------------------------------
fn test_the_same_method_always_fingerprints_the_same() -> [crypto] Result[Unit, Str] {
  assert_true(method.fingerprint(high_spec(3, 5, 20, hour())) == method.fingerprint(high_spec(3, 5, 20, hour())), "the same method produces the same fingerprint, which is what makes \"the method we agreed on\" checkable")
}

# Every parameter must move the hash. A parameter that does not is a parameter
# two parties can disagree about while believing they agreed.
fn test_every_parameter_changes_the_fingerprint() -> [crypto] Result[Unit, Str] {
  let base := method.fingerprint(high_spec(3, 5, 20, hour()))
  assert_true(base != method.fingerprint(high_spec(4, 5, 20, hour())) and base != method.fingerprint(high_spec(3, 6, 20, hour())) and base != method.fingerprint(high_spec(3, 5, 10, hour())) and base != method.fingerprint(high_spec(3, 5, 20, 2 * hour())), "x, y, the adjustment cap and the adjustment window each change the method's identity")
}

fn test_the_interval_and_version_are_part_of_the_method() -> [crypto] Result[Unit, Str] {
  let a := high_spec(3, 5, 20, hour())
  let other_interval := { method: a.method, interval_ms: 300000, version: a.version }
  let other_version := { method: a.method, interval_ms: a.interval_ms, version: 2 }
  assert_true(method.fingerprint(a) != method.fingerprint(other_interval) and method.fingerprint(a) != method.fingerprint(other_version), "the interval and the version are part of what was agreed, not incidental")
}

fn test_different_methods_fingerprint_differently() -> [crypto] Result[Unit, Str] {
  assert_true(method.fingerprint(nominated_spec()) != method.fingerprint(high_spec(3, 5, 20, hour())), "a nominated baseline and a measured one are not interchangeable")
}

# ---- A spec that cannot be computed with is refused ---------------------
fn test_a_nonsensical_method_is_refused() -> Result[Unit, Str] {
  let bad_x := high_spec(6, 5, 20, 0)
  let bad_cap := high_spec(3, 5, 200, 0)
  let bad_interval := { method: Nominated, interval_ms: 0, version: 1 }
  let unversioned := { method: Nominated, interval_ms: interval(), version: 0 }
  assert_true(is_err(method.validate(bad_x)) and is_err(method.validate(bad_cap)) and is_err(method.validate(bad_interval)) and is_err(method.validate(unversioned)), "x > y, an out-of-range cap, a zero interval and a missing version are all refused up front")
}

fn is_err(r :: Result[Unit, Str]) -> Bool {
  match r {
    Err(_) => true,
    Ok(_) => false,
  }
}

# ---- The volume --------------------------------------------------------
fn deliver_nominated(nominated_w :: Int, actual_w :: Int) -> Result[compute.Delivery, Str] {
  compute.deliver(nominated_spec(), t0(), t0() + hour(), steady(t0(), actual_w), nominated_w, no_history(), no_offsets())
}

fn test_a_shed_settles_to_the_energy_it_actually_moved() -> Result[Unit, Str] {
  match deliver_nominated(22000, 7000) {
    Err(e) => fail(str.concat("should have computed: ", e)),
    Ok(d) => assert_true(d.delivered_wh == 15000 and d.baseline_w == 22000 and d.actual_w == 7000, "22kW held at 7kW for an hour delivers 15000Wh"),
  }
}

# An underperforming shed is a zero, not a debt. Netting a negative against
# another window would pay the average of a promise kept and one broken.
fn test_drawing_more_than_the_baseline_delivers_nothing() -> Result[Unit, Str] {
  match deliver_nominated(22000, 25000) {
    Err(e) => fail(str.concat("should have computed: ", e)),
    Ok(d) => assert_true(d.delivered_wh == 0, "a site that drew more than its baseline delivers zero, never a negative volume"),
  }
}

fn test_a_backwards_window_is_refused() -> Result[Unit, Str] {
  match compute.deliver(nominated_spec(), t0() + hour(), t0(), steady(t0(), 7000), 22000, no_history(), no_offsets()) {
    Ok(_) => fail("a window that ends before it starts must not produce a volume"),
    Err(_) => pass(),
  }
}

fn test_readings_outside_the_window_are_ignored() -> Result[Unit, Str] {
  let mixed := list.concat(steady(t0(), 7000), steady(t0() + 2 * hour(), 22000))
  match compute.deliver(nominated_spec(), t0(), t0() + hour(), mixed, 22000, no_history(), no_offsets()) {
    Err(e) => fail(str.concat("should have computed: ", e)),
    Ok(d) => assert_true(d.actual_w == 7000 and d.intervals == 4, "only the readings inside the window count toward the metered figure"),
  }
}

# ---- HighXofY ----------------------------------------------------------
#
# Five prior days at the same clock hour, drawing 20, 21, 22, 23 and 24 kW. The
# three highest average 23 kW.
fn five_days() -> List[List[method.Reading]] {
  list.map([20000, 21000, 22000, 23000, 24000], fn (w :: Int) -> List[method.Reading] {
    steady(t0(), w)
  })
}

# Each historical day's series is written at the event's own clock time, so the
# offsets that map them back are zero here; the shape is what matters.
fn zero_offsets() -> List[Int] {
  [0, 0, 0, 0, 0]
}

fn test_the_baseline_is_the_mean_of_the_highest_x_days() -> Result[Unit, Str] {
  match compute.deliver(high_spec(3, 5, 0, 0), t0(), t0() + hour(), steady(t0(), 7000), 0, five_days(), zero_offsets()) {
    Err(e) => fail(str.concat("should have computed: ", e)),
    Ok(d) => assert_true(d.baseline_w == 23000, "the three highest of five days (24, 23, 22 kW) average 23kW"),
  }
}

fn test_fewer_days_than_the_method_requires_is_refused() -> Result[Unit, Str] {
  match compute.deliver(high_spec(3, 5, 0, 0), t0(), t0() + hour(), steady(t0(), 7000), 0, [steady(t0(), 20000)], [0]) {
    Ok(_) => fail("a 5-day method must not settle against one day of history"),
    Err(_) => pass(),
  }
}

# The measured method takes nobody's word: the nominated figure is ignored.
fn test_the_measured_method_ignores_the_nomination() -> Result[Unit, Str] {
  match compute.deliver(high_spec(3, 5, 0, 0), t0(), t0() + hour(), steady(t0(), 7000), 99000, five_days(), zero_offsets()) {
    Err(e) => fail(str.concat("should have computed: ", e)),
    Ok(d) => assert_true(d.baseline_w == 23000, "a measured baseline does not move when the controller claims a different one"),
  }
}

# ---- Replayability, which is the whole claim ---------------------------
fn test_the_same_inputs_always_produce_the_same_number() -> Result[Unit, Str] {
  let once := compute.deliver(high_spec(3, 5, 20, hour()), t0(), t0() + hour(), steady(t0(), 7000), 0, five_days(), zero_offsets())
  let twice := compute.deliver(high_spec(3, 5, 20, hour()), t0(), t0() + hour(), steady(t0(), 7000), 0, five_days(), zero_offsets())
  match once {
    Err(_) => fail("should have computed"),
    Ok(a) => match twice {
      Err(_) => fail("should have computed"),
      Ok(b) => assert_true(a.delivered_wh == b.delivered_wh and a.baseline_w == b.baseline_w, "a counterparty re-running this on the same readings gets the same number"),
    },
  }
}

# ---- Suite -------------------------------------------------------------
#
# `lex test` calls `run_all` and DISCARDS what it returns (lex-lang#757), so a
# returned failure count reports `ok` however many assertions failed. This
# prints each failure by name and then raises.
fn results() -> [crypto] List[(Str, Result[Unit, Str])] {
  [("the_same_method_always_fingerprints_the_same", test_the_same_method_always_fingerprints_the_same()), ("every_parameter_changes_the_fingerprint", test_every_parameter_changes_the_fingerprint()), ("the_interval_and_version_are_part_of_the_method", test_the_interval_and_version_are_part_of_the_method()), ("different_methods_fingerprint_differently", test_different_methods_fingerprint_differently()), ("a_nonsensical_method_is_refused", test_a_nonsensical_method_is_refused()), ("a_shed_settles_to_the_energy_it_actually_moved", test_a_shed_settles_to_the_energy_it_actually_moved()), ("drawing_more_than_the_baseline_delivers_nothing", test_drawing_more_than_the_baseline_delivers_nothing()), ("a_backwards_window_is_refused", test_a_backwards_window_is_refused()), ("readings_outside_the_window_are_ignored", test_readings_outside_the_window_are_ignored()), ("the_baseline_is_the_mean_of_the_highest_x_days", test_the_baseline_is_the_mean_of_the_highest_x_days()), ("fewer_days_than_the_method_requires_is_refused", test_fewer_days_than_the_method_requires_is_refused()), ("the_measured_method_ignores_the_nomination", test_the_measured_method_ignores_the_nomination()), ("the_same_inputs_always_produce_the_same_number", test_the_same_inputs_always_produce_the_same_number())]
}

fn report(rs :: List[(Str, Result[Unit, Str])]) -> [io] Int {
  list.fold(rs, 0, fn (n :: Int, r :: (Str, Result[Unit, Str])) -> [io] Int {
    match r {
      (name, Ok(_)) => n,
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

fn run_all() -> [io, crypto] Unit {
  let failures := report(results())
  if failures == 0 {
    ()
  } else {
    let __p := io.print(str.concat(int.to_str(failures), " test(s) failed"))
    let __boom := raise_failure(0)
    ()
  }
}

