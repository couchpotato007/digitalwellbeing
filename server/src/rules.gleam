//// What the category settings show, on the web page and in the app: the
//// categories with their rating and time, the apps and websites in them
//// and why, what has no category yet, and what an advanced rule would match.

import categories.{type Category, type Rule, type Source, Rule}
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

/// An app or website and its screen time in the last `days` days, with why
/// it is in its category and the devices it was used on.
pub type Item {
  Item(name: String, ms: Int, source: Source, devices: List(String))
}

pub type Entry {
  Entry(category: Category, ms: Int, items: List(Item), rules: List(Rule))
}

pub type Overview {
  Overview(
    /// In the order of their colors
    categories: List(Entry),
    /// What has no category, the most used first
    unsorted: List(Item),
    unsorted_ms: Int,
    /// Devices that sent something or are named in a rule
    devices: List(String),
    /// Top-level categories, the index picks the color like stats.color_slot
    category_order: List(String),
  )
}

/// What a rule matches in the last `days` days, whatever else says.
pub type Preview {
  Preview(screen_ms: Int, apps: List(Usage), titles: List(Usage))
}

pub fn overview(conn: sqlight.Connection) -> Result(Overview, sqlight.Error) {
  use setup <- result.try(db.setup(conn))
  use names <- result.try(db.device_names(conn))
  use filter <- result.try(db.filter(conn, "", days, ""))
  use rows <- result.map(db.recent_usage(conn, filter.since_ms))
  let categorize = categories.categorizer(setup)
  let by_category =
    list.map(rows, fn(row) {
      #(categorize(row.device, row.app, row.title, row.site), row)
    })
    |> list.group(fn(entry) { { entry.0 }.category })
    |> dict.map_values(fn(_, entries) { items(entries) })
  let of = fn(name) { dict.get(by_category, name) |> result.unwrap([]) }
  let total = fn(items: List(Item)) {
    list.fold(items, 0, fn(sum, i) { sum + i.ms })
  }
  let unsorted = of(categories.uncategorized)
  Overview(
    categories: list.map(setup.categories, fn(category) {
      let items = of(category.name)
      Entry(
        category:,
        ms: total(items),
        items:,
        rules: list.filter(setup.rules, fn(rule) { rule.name == category.name }),
      )
    }),
    unsorted: list.take(unsorted, 50),
    unsorted_ms: total(unsorted),
    devices: list.flat_map(setup.rules, fn(rule) { rule.devices })
      |> list.append(names)
      |> list.unique
      |> list.sort(string.compare),
    category_order: setup.categories
      |> list.map(fn(c) { stats.top_level(c.name) })
      |> list.unique,
  )
}

/// The items of the matches, one per name (in any case), the most used
/// first. An item that got its category in several ways has the way of most
/// of its time.
fn items(entries: List(#(categories.Match, db.Recent))) -> List(Item) {
  list.group(entries, fn(entry) { string.lowercase({ entry.0 }.item) })
  |> dict.values
  |> list.map(fn(group) {
    let assert [#(first, _), ..] = group
    let by_source =
      list.group(group, fn(entry) { { entry.0 }.source })
      |> dict.to_list
      |> list.map(fn(entry) {
        #(entry.0, list.fold(entry.1, 0, fn(sum, e) { sum + { e.1 }.ms }))
      })
      |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
    let source = case by_source {
      [#(source, _), ..] -> source
      [] -> categories.NoSource
    }
    Item(
      name: first.item,
      ms: list.fold(group, 0, fn(sum, e) { sum + { e.1 }.ms }),
      source:,
      devices: list.map(group, fn(e) { { e.1 }.device })
        |> list.unique
        |> list.sort(string.compare),
    )
  })
  |> list.sort(fn(a, b) { int.compare(b.ms, a.ms) })
}

/// A rule from its parts, checked: a category, at least one pattern and a
/// regex that compiles.
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
    "", _ -> Error("The rule needs a category")
    _, "" -> Error("The rule needs at least one pattern")
    _, _ ->
      categories.compile(rule.regex, rule.ignore_case) |> result.replace(rule)
  }
}

/// A category name from what was entered, checked.
pub fn category_name(name: String) -> Result(String, String) {
  case categories.normalize_name(name) {
    "" -> Error("The category needs a name")
    name if name == categories.uncategorized ->
      Error("\"" <> name <> "\" is what has no category")
    name -> Ok(name)
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
      let target = case row.site {
        "" -> row.app
        site -> site
      }
      categories.matches(rule, regex, row.device, target, row.title)
    })
  let top = fn(key, detail) {
    list.group(matched, key)
    |> dict.to_list
    |> list.map(fn(group) {
      let #(name, rows) = group
      Usage(
        name,
        detail(rows),
        list.fold(rows, 0, fn(sum, row: db.Recent) { sum + row.ms }),
      )
    })
    |> list.sort(fn(a, b) { int.compare(b.ms, a.ms) })
    |> list.take(15)
  }
  Preview(
    screen_ms: list.fold(matched, 0, fn(sum, row) { sum + row.ms }),
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

fn item_to_json(item: Item) -> Json {
  json.object([
    #("name", json.string(item.name)),
    #("ms", json.int(item.ms)),
    #("source", json.string(categories.source_to_string(item.source))),
    #("devices", json.array(item.devices, json.string)),
  ])
}

pub fn rule_to_json(rule: Rule) -> Json {
  json.object([
    #("id", json.int(rule.id)),
    #("category", json.string(rule.name)),
    #(
      "patterns",
      json.array(categories.split_patterns(rule.regex), json.string),
    ),
    #("ignore_case", json.bool(rule.ignore_case)),
    #("devices", json.array(rule.devices, json.string)),
  ])
}

pub fn overview_to_json(overview: Overview) -> Json {
  json.object([
    #(
      "categories",
      json.array(overview.categories, fn(entry) {
        json.object([
          #("name", json.string(entry.category.name)),
          #(
            "rating",
            json.string(categories.rating_to_string(entry.category.rating)),
          ),
          #("builtin", json.bool(entry.category.builtin != "")),
          #("ms", json.int(entry.ms)),
          #("items", json.array(list.take(entry.items, 50), item_to_json)),
          #("rules", json.array(entry.rules, rule_to_json)),
        ])
      }),
    ),
    #("unsorted", json.array(overview.unsorted, item_to_json)),
    #("unsorted_ms", json.int(overview.unsorted_ms)),
    #("devices", json.array(overview.devices, json.string)),
    #("category_order", json.array(overview.category_order, json.string)),
  ])
}

pub fn preview_to_json(preview: Preview) -> Json {
  json.object([
    #("screen_ms", json.int(preview.screen_ms)),
    #("apps", json.array(preview.apps, stats.usage_to_json)),
    #("titles", json.array(preview.titles, stats.usage_to_json)),
  ])
}
