//// What the category settings show, on the web page and in the app: the
//// rules with the time of their category, what has no category yet, and
//// what a rule being edited would match.

import categories.{type Rule, Rule}
import db.{type Usage, Usage}
import gleam/dict
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import sqlight
import stats

/// How far back the times and matches go.
pub const days = 30

pub type Overview {
  Overview(
    /// In the order they were added, with the screen time of their category
    rules: List(#(Rule, Int)),
    /// Devices that sent something or are named in a rule
    devices: List(String),
    /// Top-level categories, the index picks the color like stats.color_slot
    category_order: List(String),
    uncategorized_apps: List(Usage),
    uncategorized_titles: List(Usage),
  )
}

/// What a rule matches in the last `days` days, whatever deeper rules say.
pub type Preview {
  Preview(screen_ms: Int, apps: List(Usage), titles: List(Usage))
}

pub fn overview(conn: sqlight.Connection) -> Result(Overview, sqlight.Error) {
  use rules <- result.try(db.rules(conn))
  use names <- result.try(db.device_names(conn))
  use filter <- result.try(db.filter(conn, "", days, ""))
  use totals <- result.try(db.category_totals(conn, filter.since_ms))
  use apps <- result.try(db.uncategorized_apps(conn, filter))
  use titles <- result.map(db.uncategorized_titles(conn, filter))
  let totals = dict.from_list(totals)
  Overview(
    rules: list.map(rules, fn(rule) {
      #(rule, dict.get(totals, rule.name) |> result.unwrap(0))
    }),
    devices: list.flat_map(rules, fn(rule) { rule.devices })
      |> list.append(names)
      |> list.unique
      |> list.sort(string.compare),
    category_order: stats.category_order(rules),
    uncategorized_apps: apps,
    uncategorized_titles: titles,
  )
}

/// A rule from its parts, checked: a name, at least one pattern and a regex
/// that compiles.
pub fn parse(
  id: Int,
  name: String,
  patterns: List(String),
  ignore_case: Bool,
  devices: List(String),
) -> Result(Rule, String) {
  let rule =
    Rule(
      id:,
      name: categories.normalize_name(name),
      regex: categories.join_patterns(patterns),
      ignore_case:,
      devices: list.filter(devices, fn(device) { device != "" }),
    )
  case rule.name, rule.regex {
    "", _ -> Error("The category needs a name")
    _, "" -> Error("The category needs at least one pattern")
    _, _ ->
      categories.compile(rule.regex, rule.ignore_case) |> result.replace(rule)
  }
}

pub fn preview(
  conn: sqlight.Connection,
  rule: Rule,
) -> Result(Result(Preview, String), sqlight.Error) {
  use filter <- result.try(db.filter(conn, "", days, ""))
  use rows <- result.map(db.recent_usage(conn, filter.since_ms))
  use regex <- result.map(categories.compile(rule.regex, rule.ignore_case))
  let matched =
    list.filter(rows, fn(row) {
      categories.matches(rule, regex, row.device, row.app, row.title)
    })
  let top = fn(key, detail) {
    list.group(matched, key)
    |> dict.to_list
    |> list.map(fn(group) {
      let #(name, rows) = group
      Usage(
        name,
        detail(rows),
        list.fold(rows, 0, fn(sum, row) { sum + row.ms }),
      )
    })
    |> list.sort(fn(a, b) { int.compare(b.ms, a.ms) })
    |> list.take(15)
  }
  Preview(
    // browser tabs overlap their browser's window, so only windows count
    screen_ms: list.fold(matched, 0, fn(sum, row) {
      case row.kind {
        "window" -> sum + row.ms
        _ -> sum
      }
    }),
    apps: top(fn(row: db.Recent) { row.app }, fn(rows) {
      list.map(rows, fn(row: db.Recent) { row.device })
      |> list.unique
      |> string.join(", ")
    }),
    titles: top(fn(row: db.Recent) { row.title }, fn(rows) {
      case rows {
        [first, ..] -> first.app
        [] -> ""
      }
    }),
  )
}

/// Adds `text` as a pattern of its own to a rule, so it matches exactly that.
pub fn add_pattern(rule: Rule, text: String) -> Rule {
  let pattern = categories.escape(string.trim(text))
  let patterns = categories.split_patterns(rule.regex)
  case list.contains(patterns, pattern) {
    True -> rule
    False ->
      Rule(
        ..rule,
        regex: categories.join_patterns(list.append(patterns, [pattern])),
      )
  }
}

pub fn overview_to_json(overview: Overview) -> Json {
  json.object([
    #(
      "rules",
      json.array(overview.rules, fn(entry) {
        let #(rule, ms) = entry
        json.object([
          #("id", json.int(rule.id)),
          #("name", json.string(rule.name)),
          #(
            "patterns",
            json.array(categories.split_patterns(rule.regex), json.string),
          ),
          #("ignore_case", json.bool(rule.ignore_case)),
          #("devices", json.array(rule.devices, json.string)),
          #("ms", json.int(ms)),
        ])
      }),
    ),
    #("devices", json.array(overview.devices, json.string)),
    #("category_order", json.array(overview.category_order, json.string)),
    #(
      "uncategorized_apps",
      json.array(overview.uncategorized_apps, stats.usage_to_json),
    ),
    #(
      "uncategorized_titles",
      json.array(overview.uncategorized_titles, stats.usage_to_json),
    ),
  ])
}

pub fn preview_to_json(preview: Preview) -> Json {
  json.object([
    #("screen_ms", json.int(preview.screen_ms)),
    #("apps", json.array(preview.apps, stats.usage_to_json)),
    #("titles", json.array(preview.titles, stats.usage_to_json)),
  ])
}
