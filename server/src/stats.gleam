//// Everything the dashboard and the app show for a filter. The HTML
//// dashboard renders a `Report`, `/api/stats` sends it as JSON.

import categories.{type Rule}
import db.{type Day, type Filter, type Stretch, type Usage, Usage}
import gleam/dict
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import sqlight

/// Screen time breaks shorter than this belong to the same session.
const session_gap_ms = 300_000

/// Stretches of a category closer than this are drawn as one segment.
const segment_gap_ms = 60_000

/// Activity strips are only drawn for up to this many days.
pub const max_strip_days = 31

pub type Report {
  Report(
    filter: Filter,
    days: List(Day),
    /// Time spent on several devices at once counts once
    total_ms: Int,
    /// The total of the period of the same length before
    previous_ms: Int,
    /// Stretches of screen time without breaks of 5 minutes or more
    sessions: Int,
    longest_session_ms: Int,
    /// Local time ("07:45") of the first and last screen time, "" if none
    first_active: String,
    last_active: String,
    /// Per hour ("07") for one day, otherwise per day ("2026-10-26", the
    /// detail is the weekday "Mon")
    timeline: List(Usage),
    /// Per hour of the day ("07"), summed over all days
    hours: List(Usage),
    /// When which category was used: per device for one day, otherwise per
    /// day (with all devices), empty for more than `max_strip_days` days
    strips: List(Strip),
    /// Top-level categories in the order of their rules, the index picks the
    /// color. "Uncategorized" and the ones from the 9th on are gray.
    category_order: List(String),
    /// All devices that ever sent something, to pick from
    device_names: List(String),
    /// Usage per device in the period, the detail is when it was last active
    devices: List(Usage),
    categories: List(Usage),
    apps: List(Usage),
    titles: List(Usage),
    domains: List(Usage),
  )
}

/// A row of the activity view, from `start_ms` to `end_ms` (a day). `date` is
/// the day for rows of a day, "" for rows of a device.
pub type Strip {
  Strip(
    label: String,
    date: String,
    start_ms: Int,
    end_ms: Int,
    segments: List(Segment),
  )
}

pub type Segment {
  Segment(start_ms: Int, end_ms: Int, category: String)
}

pub fn load(
  conn: sqlight.Connection,
  filter: Filter,
) -> Result(Report, sqlight.Error) {
  use rules <- result.try(db.rules(conn))
  use days <- result.try(db.days(conn, filter))
  use stretches <- result.try(db.screen_time(conn, filter))
  use previous <- result.try(db.screen_time(conn, db.previous(filter)))
  use device_names <- result.try(db.device_names(conn))
  use devices <- result.try(db.devices(conn, filter))
  use categories <- result.try(db.categories(conn, filter))
  use apps <- result.try(db.apps(conn, filter))
  use titles <- result.try(db.titles(conn, filter))
  use domains <- result.map(db.domains(conn, filter))
  let report = build(filter, rules, days, stretches, previous)
  Report(
    ..report,
    device_names:,
    devices:,
    categories:,
    apps:,
    titles:,
    domains:,
  )
}

/// The report without the lists that come straight from the database.
pub fn build(
  filter: Filter,
  rules: List(Rule),
  days: List(Day),
  stretches: List(Stretch),
  previous: List(Stretch),
) -> Report {
  let sessions = sessions(intervals(stretches))
  let #(first_active, last_active) = case stretches {
    [] -> #("", "")
    [first, ..] -> {
      let assert Ok(last) =
        list.max(stretches, fn(a, b) { int.compare(a.end_ms, b.end_ms) })
      #(first.start_time, last.end_time)
    }
  }
  Report(
    filter:,
    days:,
    total_ms: union_ms(intervals(stretches)),
    previous_ms: union_ms(intervals(previous)),
    sessions: list.length(sessions),
    longest_session_ms: list.fold(sessions, 0, int.max),
    first_active:,
    last_active:,
    timeline: timeline(filter, days, stretches),
    hours: per_hour(stretches),
    strips: strips(filter, days, stretches),
    category_order: category_order(rules),
    device_names: [],
    devices: [],
    categories: [],
    apps: [],
    titles: [],
    domains: [],
  )
}

fn intervals(stretches: List(Stretch)) -> List(#(Int, Int)) {
  list.map(stretches, fn(s) { #(s.start_ms, s.end_ms) })
}

/// Merges intervals sorted by start that are less than `gap` apart.
pub fn merge(intervals: List(#(Int, Int)), gap: Int) -> List(#(Int, Int)) {
  list.fold(intervals, [], fn(merged, interval) {
    case merged {
      [#(start, end), ..rest] if interval.0 <= end + gap -> [
        #(start, int.max(end, interval.1)),
        ..rest
      ]
      _ if interval.1 > interval.0 -> [interval, ..merged]
      _ -> merged
    }
  })
  |> list.reverse
}

/// The screen time of each session, breaks shorter than `session_gap_ms`
/// within it don't count.
fn sessions(intervals: List(#(Int, Int))) -> List(Int) {
  let #(sessions, _) =
    list.fold(merge(intervals, 0), #([], 0), fn(acc, interval) {
      let #(sessions, reach) = acc
      let length = interval.1 - interval.0
      case sessions {
        [current, ..rest] if interval.0 < reach + session_gap_ms -> #(
          [current + length, ..rest],
          interval.1,
        )
        _ -> #([length, ..sessions], interval.1)
      }
    })
  list.reverse(sessions)
}

/// Length of the union of intervals sorted by start.
pub fn union_ms(intervals: List(#(Int, Int))) -> Int {
  merge(intervals, 0)
  |> list.fold(0, fn(total, interval) { total + interval.1 - interval.0 })
}

fn hour_labels() -> List(String) {
  int.range(from: 0, to: 24, with: [], run: list.prepend)
  |> list.reverse
  |> list.map(fn(hour) { int.to_string(hour) |> string.pad_start(2, "0") })
}

/// Union of the stretches grouped by `key`, one entry per label.
fn totals_by(
  stretches: List(Stretch),
  key: fn(Stretch) -> String,
) -> dict.Dict(String, Int) {
  // list.group reverses the order within a group
  list.group(stretches, key)
  |> dict.map_values(fn(_, group) {
    list.reverse(group) |> intervals |> union_ms
  })
}

fn timeline(
  filter: Filter,
  days: List(Day),
  stretches: List(Stretch),
) -> List(Usage) {
  case filter.days {
    1 -> per_hour(stretches)
    _ -> {
      let totals = totals_by(stretches, fn(s) { s.date })
      list.map(days, fn(day) {
        Usage(
          day.date,
          weekday(day.weekday),
          dict.get(totals, day.date) |> result.unwrap(0),
        )
      })
    }
  }
}

/// Stretches of different days never overlap, so the union per hour of the
/// day is the sum over the days.
fn per_hour(stretches: List(Stretch)) -> List(Usage) {
  let totals = totals_by(stretches, fn(s) { s.hour })
  list.map(hour_labels(), fn(hour) {
    Usage(hour, "", dict.get(totals, hour) |> result.unwrap(0))
  })
}

pub fn weekday(day: Int) -> String {
  case day {
    0 -> "Sun"
    1 -> "Mon"
    2 -> "Tue"
    3 -> "Wed"
    4 -> "Thu"
    5 -> "Fri"
    _ -> "Sat"
  }
}

fn strips(
  filter: Filter,
  days: List(Day),
  stretches: List(Stretch),
) -> List(Strip) {
  case filter.days, days {
    1, [day] ->
      list.group(stretches, fn(s) { s.device })
      |> dict.to_list
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.map(fn(group) {
        Strip(group.0, "", day.start_ms, day.end_ms, segments(group.1, day))
      })
    days_count, _ if days_count <= max_strip_days -> {
      let by_date = list.group(stretches, fn(s) { s.date })
      list.map(days, fn(day) {
        let group = dict.get(by_date, day.date) |> result.unwrap([])
        Strip(
          weekday(day.weekday) <> " " <> string.slice(day.date, 5, 5),
          day.date,
          day.start_ms,
          day.end_ms,
          segments(group, day),
        )
      })
    }
    _, _ -> []
  }
}

/// `stretches` in the reverse order of list.group, cut to the day.
fn segments(stretches: List(Stretch), day: Day) -> List(Segment) {
  stretches
  |> list.sort(fn(a, b) { int.compare(a.start_ms, b.start_ms) })
  |> list.fold([], fn(merged: List(Segment), s) {
    let start = int.max(s.start_ms, day.start_ms)
    let end = int.min(s.end_ms, day.end_ms)
    case merged {
      _ if end <= start -> merged
      [last, ..rest]
        if last.category == s.category && start <= last.end_ms + segment_gap_ms
      -> [Segment(..last, end_ms: int.max(last.end_ms, end)), ..rest]
      _ -> [Segment(start, end, s.category), ..merged]
    }
  })
  |> list.reverse
}

/// Top-level categories in the order their first rule has.
pub fn category_order(rules: List(Rule)) -> List(String) {
  list.map(rules, fn(rule) { top_level(rule.name) })
  |> list.unique
}

/// "Work > Programming" -> "Work"
pub fn top_level(category: String) -> String {
  case string.split_once(category, " > ") {
    Ok(#(top, _)) -> top
    Error(Nil) -> category
  }
}

/// The color slot of a category, 0 to 7, or Error for gray.
pub fn color_slot(order: List(String), category: String) -> Result(Int, Nil) {
  let top = top_level(category)
  list.index_fold(order, Error(Nil), fn(found, name, index) {
    case found, name == top && index < 8 {
      Error(Nil), True -> Ok(index)
      _, _ -> found
    }
  })
}

/// Percentage change from `before` to `now`, Error if there was nothing
/// before.
pub fn change(now: Int, before: Int) -> Result(Int, Nil) {
  case before {
    0 -> Error(Nil)
    _ -> Ok({ now - before } * 100 / before)
  }
}

pub fn to_json(report: Report) -> Json {
  let filter = report.filter
  let usages = fn(items: List(Usage)) {
    json.array(items, fn(item) {
      json.object([
        #("name", json.string(item.name)),
        #("detail", json.string(item.detail)),
        #("ms", json.int(item.ms)),
      ])
    })
  }
  json.object([
    #("date", json.string(filter.date)),
    #("first_date", json.string(filter.first_date)),
    #("days", json.int(filter.days)),
    #("device", json.string(filter.device)),
    #("previous_date", json.string(filter.previous_date)),
    #("next_date", json.string(filter.next_date)),
    #("today", json.string(filter.today)),
    #("total_ms", json.int(report.total_ms)),
    #("previous_ms", json.int(report.previous_ms)),
    #("sessions", json.int(report.sessions)),
    #("longest_session_ms", json.int(report.longest_session_ms)),
    #("first_active", json.string(report.first_active)),
    #("last_active", json.string(report.last_active)),
    #("timeline", usages(report.timeline)),
    #("hours", usages(report.hours)),
    #(
      "strips",
      json.array(report.strips, fn(strip) {
        json.object([
          #("label", json.string(strip.label)),
          #("date", json.string(strip.date)),
          #("start_ms", json.int(strip.start_ms)),
          #("end_ms", json.int(strip.end_ms)),
          #(
            "segments",
            json.array(strip.segments, fn(segment) {
              json.object([
                #("start_ms", json.int(segment.start_ms)),
                #("end_ms", json.int(segment.end_ms)),
                #("category", json.string(segment.category)),
              ])
            }),
          ),
        ])
      }),
    ),
    #("category_order", json.array(report.category_order, json.string)),
    #("device_names", json.array(report.device_names, json.string)),
    #("devices", usages(report.devices)),
    #("categories", usages(report.categories)),
    #("apps", usages(report.apps)),
    #("titles", usages(report.titles)),
    #("domains", usages(report.domains)),
  ])
}
