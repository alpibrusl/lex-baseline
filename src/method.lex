# method.lex — what a baseline method IS, and how it is pinned.
#
# Delivered flexibility is the difference between a counterfactual and the
# meter: what the site WOULD have drawn, minus what it did. The meter is
# measured. The counterfactual is not — it is a model output, and no amount of
# hashing makes it true.
#
# So this package does not try to make it true. It makes it *checkable*:
#
#   - the method is NAMED, with every parameter it depends on
#   - the method is CONTENT-ADDRESSED, so "the method we agreed on" is a hash
#     rather than a description in an email
#   - the computation is PURE, so a counterparty re-running it on the same
#     readings gets the same number or has found a real disagreement
#
# That reduces a dispute from "whose spreadsheet do we believe" to "we disagree
# about the published method" — a smaller and much more tractable argument. It
# is also the only claim this package supports, and callers should not make a
# larger one.
#
# ---- The two methods --------------------------------------------------
#
# `Nominated` takes the baseline from what the controller declared it was about
# to do. It is exact when the declaration is honest and worthless when it is
# not: the party being paid for the shed is the party stating what it would
# otherwise have drawn. Cheap, and appropriate where the controller is trusted
# or independently constrained — but never present it as measurement.
#
# `HighXofY` is the demand-response standard: average the same clock interval
# across the X highest of the Y most recent comparable days, optionally
# adjusted for how the site is behaving today. Nobody's word is required. It
# needs history, it is only as good as its notion of a comparable day, and it
# is what an aggregator and a DSO can actually argue about on equal terms.

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.bytes" as bytes

import "std.crypto" as crypto

import "lex-schema/json_value" as jv

# A single interval reading. Power in whole watts, timestamp in epoch
# milliseconds — the same exact-integer discipline the rest of the settlement
# path uses, so a volume never turns on a float comparison.
type Reading = { ts_ms :: Int, w :: Int }

# `adjust_cap_pct` bounds the same-day adjustment, as a percentage of the
# unadjusted baseline. Demand-response programmes cap it (CAISO's ±20% is the
# familiar one) because an uncapped adjustment lets today's behaviour rewrite
# the counterfactual it is supposed to be measured against. 0 disables
# adjustment entirely.
# `adjust_window_ms` is how much of the run-up to the event the adjustment
# looks at — 0 disables adjustment entirely. It lives in the spec, and is
# therefore hashed, because "we adjusted on the preceding hour" and "we
# adjusted on the preceding three" are different methods producing different
# numbers, and neither party should be able to pick afterwards.
#
# `Spec` below pairs a method with everything else the computation depends on,
# and the whole record is what gets hashed: change the interval, a parameter or
# the version and you are running a different method, which the fingerprint
# says. (Its own comment lives up here because `lex fmt` deletes a comment
# sitting between a variant type and what follows it — lex-lang#755.)
type Method = Nominated | HighXofY({ x :: Int, y :: Int, adjust_cap_pct :: Int, adjust_window_ms :: Int })

type Spec = { method :: Method, interval_ms :: Int, version :: Int }

fn method_name(m :: Method) -> Str {
  match m {
    Nominated => "nominated",
    HighXofY(_) => "high-x-of-y",
  }
}

# The canonical form. Fixed field order and no formatting slack, so two parties
# who believe they agreed on a method produce byte-identical text — which is
# the only reason the fingerprint means anything.
fn canonical(spec :: Spec) -> Str {
  let params := match spec.method {
    Nominated => JObj([]),
    HighXofY(p) => JObj([("x", JInt(p.x)), ("y", JInt(p.y)), ("adjust_cap_pct", JInt(p.adjust_cap_pct)), ("adjust_window_ms", JInt(p.adjust_window_ms))]),
  }
  jv.stringify(JObj([("method", JStr(method_name(spec.method))), ("params", params), ("interval_ms", JInt(spec.interval_ms)), ("version", JInt(spec.version))]))
}

# The method's identity: sha256 of its canonical form, hex. This is what goes
# on the trail beside a settled volume, and what a counterparty checks before
# arguing about the number.
fn fingerprint(spec :: Spec) -> [crypto] Str {
  crypto.hex_encode(crypto.sha256(bytes.from_str(canonical(spec))))
}

# A human-readable label for logs and disputes. Not a substitute for the
# fingerprint — two labels can read alike and hash differently, and it is the
# hash that settles it.
fn label(spec :: Spec) -> Str {
  match spec.method {
    Nominated => "nominated baseline",
    HighXofY(p) => str.concat("high ", str.concat(int.to_str(p.x), str.concat(" of ", str.concat(int.to_str(p.y), " comparable days")))),
  }
}

# Is this spec self-consistent enough to compute with? Checked explicitly, so a
# nonsensical method fails loudly at settlement rather than quietly producing a
# number somebody then has to defend.
fn validate(spec :: Spec) -> Result[Unit, Str] {
  if spec.interval_ms <= 0 {
    Err("interval_ms must be positive")
  } else {
    if spec.version <= 0 {
      Err("a method spec must carry a version")
    } else {
      match spec.method {
        Nominated => Ok(()),
        HighXofY(p) => if p.y <= 0 {
          Err("y (the pool of comparable days) must be positive")
        } else {
          if p.x <= 0 or p.x > p.y {
            Err("x must be between 1 and y")
          } else {
            if p.adjust_cap_pct < 0 or p.adjust_cap_pct > 100 {
              Err("adjust_cap_pct must be between 0 and 100")
            } else {
              if p.adjust_window_ms < 0 {
                Err("adjust_window_ms cannot be negative")
              } else {
                Ok(())
              }
            }
          }
        },
      }
    }
  }
}

