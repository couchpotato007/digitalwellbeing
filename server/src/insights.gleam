//// What the numbers say beyond totals: phone habits, focus, how the devices
//// are used together and how a period compares with what is usual. Computed
//// from the raw events, see src/sql/insights.sql.
////
//// "Usual" is robust on purpose: the median of the same period in earlier
//// weeks, and how far off a period is in units of their median absolute
//// deviation. One holiday or sick day doesn't move it, unlike an average.

import categories
import db.{type Day, type Filter, type Usage, Usage}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import server/sql.{type Activity}
import sqlight
import stats.{Slot}

/// Something that happened `count` times, like notifications of an app.
pub type Count {
  Count(name: String, count: Int)
}

/// `ms` against the median of the same period before (`usual_ms`), over
/// `periods` earlier periods with data. `score` is how unusual it is, a
/// robust z-score: beyond ±2 is unusual.
pub type Comparison {
  Comparison(name: String, ms: Int, usual_ms: Int, periods: Int, score: Float)
}

pub type Insights {
  Insights(
    /// Unlocks of phones, and per hour of the day (24 entries)
    pickups: Int,
    pickup_hours: List(Int),
    /// Local time ("07:12") of the first unlock of the day, for several days
    /// the median of them, "" if none
    first_pickup: String,
    /// Unlocks up to a minute after a notification on the same device
    notification_pickups: Int,
    /// The app used first after an unlock
    pickup_apps: List(Count),
    notifications: Int,
    notification_apps: List(Count),
    /// Times a phone's screen turned on, how many were on for less than a
    /// minute, and how long it usually was on
    screen_ons: Int,
    short_screen_ons: Int,
    median_screen_on_ms: Int,
    /// Media playing, it overlaps screen time
    audio_ms: Int,
    audio_apps: List(Usage),
    /// Screen time per rating of its category, overlaps of devices count
    /// once (in the first rating, productive before neutral)
    productive_ms: Int,
    neutral_ms: Int,
    distracting_ms: Int,
    /// Stretches of `long_stretch_ms` or more in one top-level productive
    /// category on one device. Interruptions under a minute don't end them.
    long_stretches: Int,
    long_stretch_ms: Int,
    /// The longest of them, `detail` is when ("10:05–11:40")
    longest_stretch: Usage,
    long_stretch_categories: List(Usage),
    /// Changes from one app to another within a session on a device
    app_switches: Int,
    median_session_ms: Int,
    /// Phone screen time while a computer was in use, and unlocks then.
    /// Phones are devices that send unlocks or screen events.
    phone_during_computer_ms: Int,
    pickups_during_computer: Int,
    /// Screen time against what is usual, and per top-level category and
    /// per app, the most unusual first. While the period is still going (it
    /// ends today), earlier ones only count up to the same time of day:
    /// `until_now`.
    total: Comparison,
    until_now: Bool,
    categories: List(Comparison),
    apps: List(Comparison),
    /// For several days: per day the average screen time of the 7 days up to
    /// it, `name` is the date
    trend: List(Usage),
    /// Average screen time per weekday (0 Sunday to 6 Saturday) and hour, of
    /// the 4 weeks up to the filter's date
    week_hours: List(List(Int)),
  )
}

/// A long stretch in one category.
pub const long_stretch_ms = 1_500_000

/// Interruptions shorter than this don't end a long stretch.
const interruption_ms = 60_000

/// A notification this long before an unlock is what it was for.
const notification_window_ms = 60_000

/// The app opened up to this long after an unlock is what it was for.
const pickup_app_window_ms = 60_000

/// Breaks of this length end a session, as in stats.
const session_gap_ms = 300_000

pub fn load(
  conn: sqlight.Connection,
  filter: Filter,
  days: List(Day),
) -> Result(Insights, sqlight.Error) {
  use rows <- result.try(db.activity(
    conn,
    filter.since_ms,
    filter.until_ms,
    filter.device,
  ))
  // earlier periods to compare with, see `history`
  let #(step, periods) = history(filter.days)
  use wide <- result.try(db.filter(
    conn,
    filter.date,
    filter.days + periods * step,
    filter.device,
  ))
  use wide_days <- result.try(db.days(conn, wide))
  use intervals <- result.try(db.screen_intervals(
    conn,
    wide.since_ms,
    wide.until_ms,
    filter.device,
  ))
  use categories <- result.try(db.daily_categories(
    conn,
    wide.since_ms,
    wide.until_ms,
    filter.device,
  ))
  use apps <- result.try(db.daily_apps(
    conn,
    wide.since_ms,
    wide.until_ms,
    filter.device,
  ))
  use defined <- result.map(db.category_list(conn))
  let ratings =
    list.map(defined, fn(c) { #(c.name, c.rating) }) |> dict.from_list
  build(filter, days, rows, wide_days, intervals, categories, apps, ratings)
}

/// How far apart the earlier periods are (in days) and how many there are:
/// the same weekday or week in the 8 weeks before, longer periods 6 times.
fn history(days: Int) -> #(Int, Int) {
  case days {
    days if days < 7 -> #(7, 8)
    7 -> #(7, 8)
    days -> #(days, 6)
  }
}

pub fn build(
  filter: Filter,
  days: List(Day),
  rows: List(Activity),
  wide_days: List(Day),
  intervals: List(#(Int, Int)),
  categories: List(db.Daily),
  apps: List(db.Daily),
  ratings: Dict(String, categories.Rating),
) -> Insights {
  let of_kind = fn(kind) { list.filter(rows, fn(row) { row.kind == kind }) }
  let windows = of_kind("window")
  let unlocks = of_kind("unlock")
  let notifications = of_kind("notification")
  let screens = of_kind("screen")
  let audio = of_kind("audio")

  let phones =
    list.append(unlocks, screens)
    |> list.map(fn(row) { row.device })
    |> list.unique
  let #(phone_windows, computer_windows) =
    list.partition(windows, fn(row) { list.contains(phones, row.device) })
  let computer_use = merge_rows(computer_windows, 120_000)

  let rating = fn(row: Activity) {
    dict.get(ratings, row.category) |> result.unwrap(categories.Neutral)
  }
  let productive =
    list.filter(windows, fn(w) { rating(w) == categories.Productive })
  let rated = fn(r) {
    list.filter(windows, fn(w) { rating(w) == r }) |> merge_rows(0)
  }
  let productive_time = rated(categories.Productive)
  let neutral_time = rated(categories.Neutral)
  let neutral_ms =
    union_ms(neutral_time) - overlap_ms(neutral_time, productive_time)
  let all_ms = merge_rows(windows, 0) |> union_ms
  let stretches = long_stretches(productive)
  let longest =
    list.fold(stretches, Usage("", "", 0), fn(longest, stretch) {
      case stretch.ms > longest.ms {
        True -> stretch
        False -> longest
      }
    })
  let screen_ms = list.map(screens, fn(row) { row.end_ms - row.start_ms })

  let #(step, periods) = history(filter.days)
  // how much of a period's last day has passed, if it is today
  let elapsed = case filter.date == filter.today, list.last(days) {
    True, Ok(today) -> option.Some(filter.now_ms - today.start_ms)
    _, _ -> option.None
  }
  let daily = daily_totals(wide_days, intervals, option.None)
  let partial = daily_totals(wide_days, intervals, elapsed)
  let total_of = fn(dates) { period_total(dates, daily, partial) }
  let by_category = daily_by(categories, stats.top_level, option.None)
  let partial_by_category = daily_by(categories, stats.top_level, elapsed)
  let by_app = daily_by(apps, fn(app) { app }, option.None)
  let partial_by_app = daily_by(apps, fn(app) { app }, elapsed)
  let periods = periods_of(wide_days, daily, filter.days, step, periods)

  Insights(
    pickups: list.length(unlocks),
    pickup_hours: per_hour(unlocks),
    first_pickup: first_pickup(unlocks),
    notification_pickups: notification_pickups(unlocks, notifications),
    pickup_apps: pickup_apps(unlocks, windows),
    notifications: list.length(notifications),
    notification_apps: count_by(notifications, fn(row) { row.app }),
    screen_ons: list.length(screens),
    short_screen_ons: list.count(screen_ms, fn(ms) { ms < 60_000 }),
    median_screen_on_ms: median(screen_ms),
    audio_ms: merge_rows(audio, 0) |> union_ms,
    audio_apps: sum_by(audio, fn(row) { row.app }),
    productive_ms: union_ms(productive_time),
    neutral_ms:,
    distracting_ms: all_ms - union_ms(productive_time) - neutral_ms,
    long_stretches: list.length(stretches),
    long_stretch_ms: list.fold(stretches, 0, fn(sum, s) { sum + s.ms }),
    longest_stretch: longest,
    long_stretch_categories: sum_usages(stretches),
    app_switches: app_switches(windows),
    median_session_ms: merge_rows(windows, 0) |> stats.sessions |> median,
    phone_during_computer_ms: overlap_ms(
      merge_rows(phone_windows, 0),
      computer_use,
    ),
    pickups_during_computer: list.count(unlocks, fn(row) {
      list.any(computer_use, fn(use_) {
        use_.0 <= row.start_ms && row.start_ms < use_.1
      })
    }),
    total: comparison("Screen time", list.map(periods, total_of), filter.days),
    until_now: option.is_some(elapsed),
    categories: compare_each(
      periods,
      by_category,
      partial_by_category,
      filter.days,
    ),
    apps: compare_each(periods, by_app, partial_by_app, filter.days),
    trend: case filter.days {
      1 -> []
      _ -> trend(days, wide_days, daily)
    },
    week_hours: week_hours(wide_days, intervals),
  )
}

// --- phone habits ---

fn per_hour(rows: List(Activity)) -> List(Int) {
  let counts =
    list.fold(rows, dict.new(), fn(counts, row) {
      dict.upsert(counts, row.hour, fn(n) { option.unwrap(n, 0) + 1 })
    })
  int.range(from: 0, to: 24, with: [], run: list.prepend)
  |> list.reverse
  |> list.map(fn(hour) { dict.get(counts, hour) |> result.unwrap(0) })
}

/// The first unlock of each day, the median of them for several days.
fn first_pickup(unlocks: List(Activity)) -> String {
  let firsts =
    list.fold(unlocks, dict.new(), fn(firsts, row) {
      let time = minutes(row.time)
      dict.upsert(firsts, row.date, fn(first) {
        int.min(option.unwrap(first, time), time)
      })
    })
    |> dict.values
  case firsts {
    [] -> ""
    _ -> clock(median(firsts))
  }
}

/// "07:45" -> 465
fn minutes(time: String) -> Int {
  case string.split(time, ":") {
    [h, m] -> {
      let h = int.parse(h) |> result.unwrap(0)
      let m = int.parse(m) |> result.unwrap(0)
      h * 60 + m
    }
    _ -> 0
  }
}

/// 465 -> "07:45"
fn clock(minutes: Int) -> String {
  let pad = fn(n) { int.to_string(n) |> string.pad_start(2, "0") }
  pad(minutes / 60) <> ":" <> pad(minutes % 60)
}

/// Per device, both sorted by start.
fn by_device(rows: List(Activity)) -> Dict(String, List(Activity)) {
  list.group(rows, fn(row) { row.device })
  // list.group reverses the order within a group
  |> dict.map_values(fn(_, group) { list.reverse(group) })
}

fn notification_pickups(
  unlocks: List(Activity),
  notifications: List(Activity),
) -> Int {
  let notifications = by_device(notifications)
  by_device(unlocks)
  |> dict.fold(0, fn(sum, device, unlocks) {
    let notifications = dict.get(notifications, device) |> result.unwrap([])
    sum + count_after(unlocks, notifications, 0)
  })
}

/// Unlocks with a notification up to `notification_window_ms` before them,
/// going through both in order.
fn count_after(
  unlocks: List(Activity),
  notifications: List(Activity),
  count: Int,
) -> Int {
  case unlocks {
    [] -> count
    [unlock, ..rest] -> {
      let notifications =
        list.drop_while(notifications, fn(n) {
          n.start_ms < unlock.start_ms - notification_window_ms
        })
      let found = case notifications {
        [n, ..] if n.start_ms <= unlock.start_ms -> 1
        _ -> 0
      }
      count_after(rest, notifications, count + found)
    }
  }
}

fn pickup_apps(
  unlocks: List(Activity),
  windows: List(Activity),
) -> List(Count) {
  let windows = by_device(windows)
  by_device(unlocks)
  |> dict.to_list
  |> list.flat_map(fn(entry) {
    let #(device, unlocks) = entry
    first_apps(unlocks, dict.get(windows, device) |> result.unwrap([]), [])
  })
  |> count_strings
}

/// The app of the first window up to `pickup_app_window_ms` after each
/// unlock. The app behind the lock screen starts at the unlock, a little
/// earlier is allowed for clocks of different events.
fn first_apps(
  unlocks: List(Activity),
  windows: List(Activity),
  apps: List(String),
) -> List(String) {
  case unlocks {
    [] -> apps
    [unlock, ..rest] -> {
      let windows =
        list.drop_while(windows, fn(w) { w.start_ms < unlock.start_ms - 2000 })
      let apps = case windows {
        [w, ..] if w.start_ms <= unlock.start_ms + pickup_app_window_ms -> [
          w.app,
          ..apps
        ]
        _ -> apps
      }
      first_apps(rest, windows, apps)
    }
  }
}

fn count_by(rows: List(Activity), key: fn(Activity) -> String) -> List(Count) {
  list.map(rows, key) |> count_strings
}

/// The 10 most common, most first.
fn count_strings(names: List(String)) -> List(Count) {
  list.fold(names, dict.new(), fn(counts, name) {
    dict.upsert(counts, name, fn(n) { option.unwrap(n, 0) + 1 })
  })
  |> dict.to_list
  |> list.map(fn(entry) { Count(entry.0, entry.1) })
  |> list.sort(fn(a, b) {
    int.compare(b.count, a.count)
    |> order.break_tie(string.compare(a.name, b.name))
  })
  |> list.take(10)
}

/// Time per `key`, the 10 largest. Overlaps within a key count once.
fn sum_by(rows: List(Activity), key: fn(Activity) -> String) -> List(Usage) {
  list.group(rows, key)
  |> dict.to_list
  |> list.map(fn(entry) {
    Usage(entry.0, "", list.reverse(entry.1) |> merge_rows(0) |> union_ms)
  })
  |> top_usages
}

fn top_usages(usages: List(Usage)) -> List(Usage) {
  list.sort(usages, fn(a, b) { int.compare(b.ms, a.ms) })
  |> list.take(10)
}

// --- focus ---

/// Per device: runs of the same top-level category, without interruptions
/// shorter than `interruption_ms`, that are at least `long_stretch_ms` long.
/// `name` is the category, `detail` when it was.
fn long_stretches(windows: List(Activity)) -> List(Usage) {
  by_device(windows)
  |> dict.values
  |> list.flat_map(fn(windows) {
    windows
    |> list.map(fn(w) {
      Run(
        stats.top_level(w.category),
        w.start_ms,
        w.end_ms,
        w.time,
        end_time(w),
      )
    })
    |> join_runs(interruption_ms)
    |> list.filter(fn(run) { run.end_ms - run.start_ms >= interruption_ms })
    |> join_runs(2 * interruption_ms)
    |> list.filter(fn(run) { run.end_ms - run.start_ms >= long_stretch_ms })
    |> list.map(fn(run) {
      Usage(run.category, run.from <> "–" <> run.to, run.end_ms - run.start_ms)
    })
  })
}

type Run {
  Run(category: String, start_ms: Int, end_ms: Int, from: String, to: String)
}

/// The local end time of a window, from its start time and length.
fn end_time(w: Activity) -> String {
  clock({ minutes(w.time) + { w.end_ms - w.start_ms } / 60_000 } % { 24 * 60 })
}

/// Joins runs of the same category less than `gap` apart, in order.
fn join_runs(runs: List(Run), gap: Int) -> List(Run) {
  list.fold(runs, [], fn(joined: List(Run), run: Run) {
    case joined {
      [last, ..rest]
        if last.category == run.category && run.start_ms <= last.end_ms + gap
      -> [
        Run(
          ..last,
          end_ms: int.max(last.end_ms, run.end_ms),
          to: case run.end_ms > last.end_ms {
            True -> run.to
            False -> last.to
          },
        ),
        ..rest
      ]
      _ -> [run, ..joined]
    }
  })
  |> list.reverse
}

/// Time per name, the largest first.
fn sum_usages(usages: List(Usage)) -> List(Usage) {
  list.fold(usages, dict.new(), fn(sums, usage) {
    dict.upsert(sums, usage.name, fn(ms) { option.unwrap(ms, 0) + usage.ms })
  })
  |> dict.to_list
  |> list.map(fn(entry) { Usage(entry.0, "", entry.1) })
  |> top_usages
}

/// Changes to another app on the same device, without a session break
/// between them.
fn app_switches(windows: List(Activity)) -> Int {
  by_device(windows)
  |> dict.fold(0, fn(sum, _, windows) {
    let #(switches, _) =
      list.fold(windows, #(0, option.None), fn(acc, w) {
        let #(switches, last) = acc
        let switched = case last {
          option.Some(#(app, end)) ->
            app != w.app && w.start_ms - end < session_gap_ms
          option.None -> False
        }
        #(
          case switched {
            True -> switches + 1
            False -> switches
          },
          option.Some(#(w.app, w.end_ms)),
        )
      })
    sum + switches
  })
}

// --- intervals ---

fn merge_rows(rows: List(Activity), gap: Int) -> List(#(Int, Int)) {
  list.map(rows, fn(row) { #(row.start_ms, row.end_ms) })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> stats.merge(gap)
}

fn union_ms(intervals: List(#(Int, Int))) -> Int {
  list.fold(intervals, 0, fn(sum, i) { sum + i.1 - i.0 })
}

/// How long two sorted lists of disjoint intervals overlap.
pub fn overlap_ms(a: List(#(Int, Int)), b: List(#(Int, Int))) -> Int {
  case a, b {
    [], _ | _, [] -> 0
    [x, ..xs], [y, ..ys] -> {
      let both = int.max(0, int.min(x.1, y.1) - int.max(x.0, y.0))
      case x.1 < y.1 {
        True -> both + overlap_ms(xs, b)
        False -> both + overlap_ms(a, ys)
      }
    }
  }
}

// --- compared with what is usual ---

/// Screen time per date, cut at midnight, or only the first `elapsed` ms of
/// each day.
fn daily_totals(
  days: List(Day),
  intervals: List(#(Int, Int)),
  elapsed: option.Option(Int),
) -> Dict(String, Int) {
  let slots =
    list.map(days, fn(day) {
      let end = case elapsed {
        option.Some(ms) -> int.min(day.start_ms + ms, day.end_ms)
        option.None -> day.end_ms
      }
      Slot(day.date, 0, day.start_ms, end)
    })
  stats.spread(stats.merge(intervals, 0), slots)
  |> list.map(fn(entry) { #({ entry.0 }.date, entry.1) })
  |> dict.from_list
}

/// Per date the screen time per `key` of the rows' names, or only of the
/// first `elapsed` ms of each day. The rows are per hour, the hour that is
/// partly over counts in proportion.
fn daily_by(
  rows: List(db.Daily),
  key: fn(String) -> String,
  elapsed: option.Option(Int),
) -> Dict(String, Dict(String, Int)) {
  list.fold(rows, dict.new(), fn(days, row) {
    let ms = case elapsed {
      option.None -> row.ms
      option.Some(elapsed) ->
        case int.compare(row.hour, elapsed / 3_600_000) {
          order.Lt -> row.ms
          order.Eq -> row.ms * { elapsed % 3_600_000 } / 3_600_000
          order.Gt -> 0
        }
    }
    dict.upsert(days, row.date, fn(categories) {
      option.unwrap(categories, dict.new())
      |> dict.upsert(key(row.name), fn(sum) { option.unwrap(sum, 0) + ms })
    })
  })
}

/// The total of a period's dates (newest first), its newest day from
/// `partial`.
fn period_total(
  dates: List(String),
  daily: Dict(String, Int),
  partial: Dict(String, Int),
) -> Int {
  case dates {
    [] -> 0
    [newest, ..rest] ->
      list.fold(
        rest,
        dict.get(partial, newest) |> result.unwrap(0),
        fn(sum, date) { sum + { dict.get(daily, date) |> result.unwrap(0) } },
      )
  }
}

/// The dates of the filter's period (index 0) and the earlier ones, newest
/// first. `wide_days` ends with the filter's last day. Periods before the
/// first day with screen time are left out, they would only say that
/// nothing was recorded yet.
fn periods_of(
  wide_days: List(Day),
  daily: Dict(String, Int),
  days: Int,
  step: Int,
  count: Int,
) -> List(List(String)) {
  let dates = list.map(wide_days, fn(day) { day.date }) |> list.reverse
  let first_data =
    list.reverse(dates)
    |> list.find(fn(date) { dict.get(daily, date) |> result.unwrap(0) > 0 })
    |> result.unwrap("9999")
  int.range(from: 0, to: count + 1, with: [], run: list.prepend)
  |> list.reverse
  |> list.filter_map(fn(i) {
    let period = dates |> list.drop(i * step) |> list.take(days)
    let before_data = case list.last(period) {
      Ok(first) -> string.compare(first, first_data) == order.Lt
      Error(Nil) -> True
    }
    case i == 0 || !before_data {
      True -> Ok(period)
      False -> Error(Nil)
    }
  })
}

/// Each name (a category or app) against what is usual for it.
fn compare_each(
  periods: List(List(String)),
  by_category: Dict(String, Dict(String, Int)),
  partial: Dict(String, Dict(String, Int)),
  days: Int,
) -> List(Comparison) {
  let names =
    dict.values(by_category)
    |> list.flat_map(dict.keys)
    |> list.unique
  list.map(names, fn(name) {
    let of = fn(by_date) {
      dict.map_values(by_date, fn(_, categories) {
        dict.get(categories, name) |> result.unwrap(0)
      })
    }
    let daily = of(by_category)
    let partial = of(partial)
    list.map(periods, period_total(_, daily, partial))
    |> comparison(name, _, days)
  })
  // at least 5 minutes a day now or usually, below that changes are noise
  |> list.filter(fn(c) { int.max(c.ms, c.usual_ms) >= 300_000 * days })
  |> list.sort(fn(a, b) {
    float.compare(float.absolute_value(b.score), float.absolute_value(a.score))
  })
  |> list.take(8)
}

/// `totals` starts with the period itself. The score's scale is the median
/// absolute deviation (×1.4826, the standard deviation of normal data), but
/// at least a tenth of the usual and 10 minutes a day: a very regular habit
/// shouldn't make every small change look unusual.
fn comparison(name: String, totals: List(Int), days: Int) -> Comparison {
  case totals {
    [] -> Comparison(name, 0, 0, 0, 0.0)
    [now, ..earlier] -> {
      let usual = median(earlier)
      let mad =
        median(
          list.map(earlier, fn(total) { int.absolute_value(total - usual) }),
        )
      let scale =
        int.to_float(mad) *. 1.4826
        |> float.max(int.to_float(usual) /. 10.0)
        |> float.max(int.to_float(600_000 * days))
      let score = case earlier {
        [] -> 0.0
        _ -> int.to_float(now - usual) /. scale
      }
      Comparison(name, now, usual, list.length(earlier), round(score))
    }
  }
}

fn round(x: Float) -> Float {
  int.to_float(float.round(x *. 10.0)) /. 10.0
}

/// The median, 0 for none.
pub fn median(values: List(Int)) -> Int {
  let sorted = list.sort(values, int.compare)
  let n = list.length(sorted)
  case n, list.drop(sorted, { n - 1 } / 2) {
    0, _ -> 0
    _, [a, b, ..] if n % 2 == 0 -> { a + b } / 2
    _, [a, ..] -> a
    _, [] -> 0
  }
}

/// The average of each day and the 6 before, of the days with data.
fn trend(
  days: List(Day),
  wide_days: List(Day),
  daily: Dict(String, Int),
) -> List(Usage) {
  let dates = list.map(wide_days, fn(day) { day.date })
  let first_data =
    list.find(dates, fn(date) { dict.get(daily, date) |> result.unwrap(0) > 0 })
    |> result.unwrap("9999")
  list.map(days, fn(day) {
    let window =
      list.take_while(dates, fn(date) {
        string.compare(date, day.date) != order.Gt
      })
      |> list.reverse
      |> list.take(7)
      |> list.filter(fn(date) { string.compare(date, first_data) != order.Lt })
    let ms = case window {
      [] -> 0
      _ ->
        list.fold(window, 0, fn(sum, date) {
          sum + { dict.get(daily, date) |> result.unwrap(0) }
        })
        / list.length(window)
    }
    Usage(day.date, "", ms)
  })
}

/// The 28 days up to the last of `wide_days`, from the first with data.
fn week_hours(
  wide_days: List(Day),
  intervals: List(#(Int, Int)),
) -> List(List(Int)) {
  let recent = list.reverse(wide_days) |> list.take(28) |> list.reverse
  let first =
    list.first(intervals) |> result.map(fn(i) { i.0 }) |> result.unwrap(0)
  let recent = list.filter(recent, fn(day) { day.end_ms > first })
  let weekdays =
    list.map(recent, fn(day) { #(day.date, day.weekday) }) |> dict.from_list
  let sums =
    stats.spread(stats.merge(intervals, 0), stats.slots(recent))
    |> list.fold(dict.new(), fn(sums, entry) {
      let #(slot, ms) = entry
      let weekday = dict.get(weekdays, slot.date) |> result.unwrap(0)
      dict.upsert(sums, #(weekday, slot.hour), fn(sum) {
        option.unwrap(sum, 0) + ms
      })
    })
  let count = fn(weekday) {
    int.max(1, list.count(recent, fn(day) { day.weekday == weekday }))
  }
  int.range(from: 0, to: 7, with: [], run: list.prepend)
  |> list.reverse
  |> list.map(fn(weekday) {
    int.range(from: 0, to: 24, with: [], run: list.prepend)
    |> list.reverse
    |> list.map(fn(hour) {
      { dict.get(sums, #(weekday, hour)) |> result.unwrap(0) } / count(weekday)
    })
  })
}

// --- JSON ---

pub fn to_json(insights: Insights) -> Json {
  let counts = fn(items: List(Count)) {
    json.array(items, fn(item) {
      json.object([
        #("name", json.string(item.name)),
        #("count", json.int(item.count)),
      ])
    })
  }
  let usages = fn(items) { json.array(items, stats.usage_to_json) }
  let comparison_json = fn(c: Comparison) {
    json.object([
      #("name", json.string(c.name)),
      #("ms", json.int(c.ms)),
      #("usual_ms", json.int(c.usual_ms)),
      #("periods", json.int(c.periods)),
      #("score", json.float(c.score)),
    ])
  }
  json.object([
    #("pickups", json.int(insights.pickups)),
    #("pickup_hours", json.array(insights.pickup_hours, json.int)),
    #("first_pickup", json.string(insights.first_pickup)),
    #("notification_pickups", json.int(insights.notification_pickups)),
    #("pickup_apps", counts(insights.pickup_apps)),
    #("notifications", json.int(insights.notifications)),
    #("notification_apps", counts(insights.notification_apps)),
    #("screen_ons", json.int(insights.screen_ons)),
    #("short_screen_ons", json.int(insights.short_screen_ons)),
    #("median_screen_on_ms", json.int(insights.median_screen_on_ms)),
    #("audio_ms", json.int(insights.audio_ms)),
    #("audio_apps", usages(insights.audio_apps)),
    #("productive_ms", json.int(insights.productive_ms)),
    #("neutral_ms", json.int(insights.neutral_ms)),
    #("distracting_ms", json.int(insights.distracting_ms)),
    #("long_stretches", json.int(insights.long_stretches)),
    #("long_stretch_ms", json.int(insights.long_stretch_ms)),
    #("longest_stretch", stats.usage_to_json(insights.longest_stretch)),
    #("long_stretch_categories", usages(insights.long_stretch_categories)),
    #("app_switches", json.int(insights.app_switches)),
    #("median_session_ms", json.int(insights.median_session_ms)),
    #("phone_during_computer_ms", json.int(insights.phone_during_computer_ms)),
    #("pickups_during_computer", json.int(insights.pickups_during_computer)),
    #("total", comparison_json(insights.total)),
    #("until_now", json.bool(insights.until_now)),
    #("categories", json.array(insights.categories, comparison_json)),
    #("apps", json.array(insights.apps, comparison_json)),
    #("trend", usages(insights.trend)),
    #(
      "week_hours",
      json.array(insights.week_hours, fn(hours) { json.array(hours, json.int) }),
    ),
  ])
}
