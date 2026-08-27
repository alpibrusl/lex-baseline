# compute.lex — the baseline, and the volume derived from it.
#
# Pure throughout: readings in, watt-hours out, no clock and no database. That
# is not tidiness. It is the property that lets a DSO, an aggregator and an
# auditor each run this on their own copy of the readings and get the same
# number — so a disagreement is about the method or the data, never about who
# ran the arithmetic.
#
# Everything is integer. Energy is watt-hours computed as watts × milliseconds
# ÷ 3_600_000, and the division happens once at the end rather than per
# interval, so rounding cannot accumulate across a long window.

import "std.int" as int

import "std.list" as list

import "./method" as method

fn ms_per_hour() -> Int {
  3600000
}

# ---- Selecting the intervals a window covers ---------------------------
fn in_window(r :: method.Reading, from_ms :: Int, to_ms :: Int) -> Bool {
  r.ts_ms >= from_ms and r.ts_ms < to_ms
}

fn within(readings :: List[method.Reading], from_ms :: Int, to_ms :: Int) -> List[method.Reading] {
  list.filter(readings, fn (r :: method.Reading) -> Bool {
    in_window(r, from_ms, to_ms)
  })
}

fn mean_w(rs :: List[method.Reading]) -> Int {
  let n := list.len(rs)
  if n == 0 {
    0
  } else {
    let total := list.fold(rs, 0, fn (acc :: Int, r :: method.Reading) -> Int {
      acc + r.w
    })
    total / n
  }
}

# ---- HighXofY ----------------------------------------------------------
#
# The baseline for a window is the mean of that same clock window across the X
# highest of the Y preceding comparable days. "Comparable" is the caller's
# problem — it hands in the candidate days it considers comparable, because
# whether a Sunday compares to a Tuesday, or a holiday to a working day, is a
# question about the site and its contract, not about arithmetic. Encoding a
# guess here would bury a contractual assumption inside a library.
#
# Days are ranked by their mean power in the window, highest first, because the
# programme convention is to bias the counterfactual UPWARD: a baseline that is
# too low understates delivery, and the party at risk of that is the one being
# measured.
fn day_means(days :: List[List[method.Reading]], from_ms :: Int, to_ms :: Int, day_offsets_ms :: List[Int]) -> List[Int] {
  list.map(list.enumerate(days), fn (pair :: (Int, List[method.Reading])) -> Int {
    match pair {
      (i, readings) => {
        let shift := match list.head(list.fold(list.enumerate(day_offsets_ms), [], fn (acc :: List[Int], o :: (Int, Int)) -> List[Int] {
          match o {
            (j, v) => if j == i {
              list.concat(acc, [v])
            } else {
              acc
            },
          }
        })) {
          Some(v) => v,
          None => 0,
        }
        mean_w(within(readings, from_ms - shift, to_ms - shift))
      },
    }
  })
}

fn descending(xs :: List[Int]) -> List[Int] {
  list.reverse(list.sort_by(xs, fn (v :: Int) -> Int {
    v
  }))
}

fn take(xs :: List[Int], n :: Int) -> List[Int] {
  list.fold(list.enumerate(xs), [], fn (acc :: List[Int], p :: (Int, Int)) -> List[Int] {
    match p {
      (i, v) => if i < n {
        list.concat(acc, [v])
      } else {
        acc
      },
    }
  })
}

fn mean_of(xs :: List[Int]) -> Int {
  let n := list.len(xs)
  if n == 0 {
    0
  } else {
    list.fold(xs, 0, fn (a :: Int, v :: Int) -> Int {
      a + v
    }) / n
  }
}

# Clamp `adjusted` to within `cap_pct` of `base`. An uncapped same-day
# adjustment would let today's behaviour rewrite the counterfactual it is
# supposed to be judged against.
fn clamp_pct(base :: Int, adjusted :: Int, cap_pct :: Int) -> Int {
  if cap_pct <= 0 {
    base
  } else {
    let margin := base * cap_pct / 100
    if adjusted > base + margin {
      base + margin
    } else {
      if adjusted < base - margin {
        base - margin
      } else {
        adjusted
      }
    }
  }
}

# ---- Same-day adjustment ------------------------------------------------
#
# A baseline built from history says what a comparable day looked like. It
# cannot know that today the depot is half empty, or that a heatwave has every
# vehicle drawing harder. The adjustment scales the historical baseline by how
# today's run-up compares to the same run-up on those days.
#
# It is applied to the run-up BEFORE the event window, never to the window
# itself: adjusting on the event period would let the curtailment being
# measured move its own baseline.
#
# The result is clamped by `adjust_cap_pct`, because an unbounded ratio turns a
# quiet morning into a large paid delivery.
fn adjust(base :: Int, adjust_window_ms :: Int, from_ms :: Int, actual :: List[method.Reading], history :: List[List[method.Reading]], offsets :: List[Int]) -> Int {
  if adjust_window_ms <= 0 {
    base
  } else {
    let today := mean_w(within(actual, from_ms - adjust_window_ms, from_ms))
    let historical := mean_of(day_means(history, from_ms - adjust_window_ms, from_ms, offsets))
    if today <= 0 or historical <= 0 {
      base
    } else {
      base * today / historical
    }
  }
}

# ---- The result --------------------------------------------------------
#
# `baseline_w` is reported alongside the volume because a counterparty checking
# a settlement wants to see the counterfactual, not just the difference it
# produced.
type Delivery = { baseline_w :: Int, actual_w :: Int, delivered_wh :: Int, intervals :: Int }

fn energy_wh(power_w :: Int, duration_ms :: Int) -> Int {
  power_w * duration_ms / ms_per_hour()
}

# Delivered volume for one window.
#
#   `actual`    metered readings inside the window
#   `nominated` what the controller declared it would otherwise have drawn,
#               used only by the Nominated method
#   `history`   candidate comparable days, each a full series, with the offset
#               (in ms) that maps each one back onto the event window
#
# A window where the site drew MORE than its baseline delivers nothing, not a
# negative amount: an underperforming shed is a zero, and netting it against
# another window's delivery would pay for the average of a promise kept and a
# promise broken.
fn deliver(spec :: method.Spec, from_ms :: Int, to_ms :: Int, actual :: List[method.Reading], nominated_w :: Int, history :: List[List[method.Reading]], history_offsets_ms :: List[Int]) -> Result[Delivery, Str] {
  match method.validate(spec) {
    Err(e) => Err(e),
    Ok(_) => {
      let window := to_ms - from_ms
      if window <= 0 {
        Err("the window must end after it starts")
      } else {
        let inside := within(actual, from_ms, to_ms)
        let actual_mean := mean_w(inside)
        match spec.method {
          Nominated => Ok(finish(nominated_w, actual_mean, window, list.len(inside))),
          HighXofY(p) => {
            let means := descending(day_means(history, from_ms, to_ms, history_offsets_ms))
            if list.len(means) < p.y {
              Err("not enough comparable days for this method")
            } else {
              let base := mean_of(take(means, p.x))
              let adjusted := adjust(base, p.adjust_window_ms, from_ms, actual, history, history_offsets_ms)
              Ok(finish(clamp_pct(base, adjusted, p.adjust_cap_pct), actual_mean, window, list.len(inside)))
            }
          },
        }
      }
    },
  }
}

fn finish(baseline :: Int, actual :: Int, window_ms :: Int, intervals :: Int) -> Delivery {
  let shed := baseline - actual
  let wh := if shed <= 0 {
    0
  } else {
    energy_wh(shed, window_ms)
  }
  { baseline_w: baseline, actual_w: actual, delivered_wh: wh, intervals: intervals }
}

