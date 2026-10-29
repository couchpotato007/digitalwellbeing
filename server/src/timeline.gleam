//// Screen time over time per app, for the app's timeline: a stacked area
//// chart of the most used apps, and the sessions with what they were made of.

import db.{type Day, type Filter, type Usage, Usage}
import gleam/dict
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import server/sql.{type Activity}
import sqlight
import stats.{type Slot, Slot}

/// How many apps get their own series, the others are "Other".
const top_apps = 6

/// Breaks shorter than this belong to the same session, as in stats.
const session_gap_ms = 300_000

/// Sessions are listed for up to this many days.
pub const max_session_days = 7

pub type Timeline {
  Timeline(
    /// The time the chart is split into: 15 minutes for a day, hours for up
    /// to a week, days for longer. `label` is the local time ("07:15"), the
    /// weekday and hour ("Mon 07:00") or the date ("10-26").
    buckets: List(Bucket),
    /// The most used apps first, then "Other". The values of a bucket add up
    /// to its screen time: apps used at once on several devices share it.
    series: List(Series),
    /// For up to `max_session_days` days, oldest first
    sessions: List(Session),
  )
}

pub type Bucket {
  Bucket(start_ms: Int, end_ms: Int, label: String, ms: Int)
}

pub type Series {
  Series(name: String, total_ms: Int, values: List(Int))
}

/// Screen time without breaks of 5 minutes or more. `start` and `end` are
/// local times, `apps` the most used in it.
pub type Session {
  Session(
    date: String,
    start_ms: Int,
    end_ms: Int,
    start: String,
    end: String,
    active_ms: Int,
    devices: List(String),
    apps: List(Usage),
  )
}

pub fn load(
  conn: sqlight.Connection,
  filter: Filter,
  days: List(Day),
) -> Result(Timeline, sqlight.Error) {
  use rows <- result.map(db.activity(
    conn,
    filter.since_ms,
    filter.until_ms,
    filter.device,
  ))
  build(days, list.filter(rows, fn(row) { row.kind == "window" }))
}

pub fn build(days: List(Day), windows: List(Activity)) -> Timeline {
  let count = list.length(days)
  let per_day = case count {
    1 -> 96
    n if n <= 7 -> 24
    _ -> 1
  }
  let slots = buckets(days, per_day)
  let total =
    stats.spread(intervals(windows), slots) |> list.map(fn(entry) { entry.1 })

  let by_app =
    list.group(windows, fn(row) { row.app })
    |> dict.to_list
    |> list.map(fn(entry) {
      let values =
        stats.spread(intervals(list.reverse(entry.1)), slots)
        |> list.map(fn(entry) { entry.1 })
      #(entry.0, values)
    })
    |> list.sort(fn(a, b) { int.compare(int.sum(b.1), int.sum(a.1)) })
  let #(top, rest) = list.split(by_app, top_apps)
  let other =
    list.filter(windows, fn(row) {
      !list.any(top, fn(app) { app.0 == row.app })
    })
  let raw = case rest {
    [] -> top
    _ ->
      list.append(top, [
        #(
          "Other",
          stats.spread(intervals(other), slots)
            |> list.map(fn(entry) { entry.1 }),
        ),
      ])
  }
  let series = share(raw, total)

  Timeline(
    buckets: list.map2(slots, total, fn(slot, ms) {
      Bucket(slot.start_ms, slot.end_ms, label(slot, days, count), ms)
    }),
    series: list.map(series, fn(entry) {
      Series(entry.0, int.sum(entry.1), entry.1)
    }),
    sessions: case count <= max_session_days {
      True -> sessions(days, windows)
      False -> []
    },
  )
}

/// `per_day` buckets of each day, as long as the day allows (days with a
/// clock change have an hour more or less).
fn buckets(days: List(Day), per_day: Int) -> List(Slot) {
  list.flat_map(days, fn(day) {
    let length = { day.end_ms - day.start_ms } / per_day
    int.range(from: 0, to: per_day, with: [], run: list.prepend)
    |> list.reverse
    |> list.map(fn(i) {
      let start = day.start_ms + i * length
      let end = case i == per_day - 1 {
        True -> day.end_ms
        False -> start + length
      }
      Slot(day.date, i, start, end)
    })
  })
}

fn label(slot: Slot, days: List(Day), count: Int) -> String {
  case count {
    1 -> local_clock(days, slot.start_ms)
    n if n <= 7 ->
      weekday_of(days, slot.date) <> " " <> local_clock(days, slot.start_ms)
    _ -> string.slice(slot.date, 5, 5)
  }
}

fn weekday_of(days: List(Day), date: String) -> String {
  list.find(days, fn(day) { day.date == date })
  |> result.map(fn(day) { stats.weekday(day.weekday) })
  |> result.unwrap("")
}

/// The local time of `ms` ("07:15"), from the start of its day.
fn local_clock(days: List(Day), ms: Int) -> String {
  let start =
    list.find(days, fn(day) { day.start_ms <= ms && ms < day.end_ms })
    |> result.map(fn(day) { day.start_ms })
    // after the last day: its end is midnight
    |> result.lazy_unwrap(fn() {
      list.last(days) |> result.map(fn(day) { day.end_ms }) |> result.unwrap(ms)
    })
  let minutes = int.max(0, ms - start) / 60_000
  let pad = fn(n) { int.to_string(n) |> string.pad_start(2, "0") }
  pad(minutes / 60 % 24) <> ":" <> pad(minutes % 60)
}

/// Each app's union per bucket, scaled down where they add up to more than
/// the bucket's screen time (several devices at once), so the stack is as
/// high as the screen time.
fn share(
  series: List(#(String, List(Int))),
  total: List(Int),
) -> List(#(String, List(Int))) {
  let sums =
    list.fold(series, list.map(total, fn(_) { 0 }), fn(sums, entry) {
      list.map2(sums, entry.1, fn(a, b) { a + b })
    })
  list.map(series, fn(entry) {
    #(
      entry.0,
      list.zip(entry.1, list.zip(sums, total))
        |> list.map(fn(x) {
          let #(value, #(sum, total)) = x
          case sum > total && sum > 0 {
            True -> value * total / sum
            False -> value
          }
        }),
    )
  })
}

fn intervals(rows: List(Activity)) -> List(#(Int, Int)) {
  list.map(rows, fn(row) { #(row.start_ms, row.end_ms) })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> stats.merge(0)
}

fn sessions(days: List(Day), windows: List(Activity)) -> List(Session) {
  let sorted =
    list.sort(windows, fn(a, b) { int.compare(a.start_ms, b.start_ms) })
  intervals(sorted)
  |> stats.merge(session_gap_ms)
  |> list.map(fn(session) {
    let #(start, end) = session
    let rows =
      list.filter(sorted, fn(row) { row.start_ms < end && row.end_ms > start })
    let apps =
      list.group(rows, fn(row) { row.app })
      |> dict.to_list
      |> list.map(fn(entry) {
        Usage(entry.0, "", intervals(entry.1) |> union_ms)
      })
      |> list.sort(fn(a, b) { int.compare(b.ms, a.ms) })
      |> list.take(5)
    Session(
      date: list.find(days, fn(day) {
        day.start_ms <= start && start < day.end_ms
      })
        |> result.map(fn(day) { day.date })
        |> result.unwrap(""),
      start_ms: start,
      end_ms: end,
      start: local_clock(days, start),
      end: local_clock(days, end),
      active_ms: intervals(rows) |> union_ms,
      devices: list.map(rows, fn(row) { row.device }) |> list.unique,
      apps:,
    )
  })
}

fn union_ms(intervals: List(#(Int, Int))) -> Int {
  list.fold(intervals, 0, fn(sum, i) { sum + i.1 - i.0 })
}

pub fn to_json(timeline: Timeline) -> Json {
  json.object([
    #(
      "buckets",
      json.array(timeline.buckets, fn(b) {
        json.object([
          #("start_ms", json.int(b.start_ms)),
          #("end_ms", json.int(b.end_ms)),
          #("label", json.string(b.label)),
          #("ms", json.int(b.ms)),
        ])
      }),
    ),
    #(
      "series",
      json.array(timeline.series, fn(s) {
        json.object([
          #("name", json.string(s.name)),
          #("total_ms", json.int(s.total_ms)),
          #("values", json.array(s.values, json.int)),
        ])
      }),
    ),
    #(
      "sessions",
      json.array(timeline.sessions, fn(s) {
        json.object([
          #("date", json.string(s.date)),
          #("start_ms", json.int(s.start_ms)),
          #("end_ms", json.int(s.end_ms)),
          #("start", json.string(s.start)),
          #("end", json.string(s.end)),
          #("active_ms", json.int(s.active_ms)),
          #("devices", json.array(s.devices, json.string)),
          #("apps", json.array(s.apps, stats.usage_to_json)),
        ])
      }),
    ),
  ])
}
