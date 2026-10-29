//// The queries are in src/sql/*.sql, parrot turns them into src/server/sql.gleam
//// (see README.md). This module runs them with sqlight.

import browsing
import categories.{type Rule, Rule}
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import parrot/dev
import server/sql
import shared
import simplifile
import sqlight.{type Connection}
import wisp

pub fn migrate(conn: Connection) -> Result(Nil, sqlight.Error) {
  let assert Ok(priv) = wisp.priv_directory("server")
  let assert Ok(schema) = simplifile.read(priv <> "/schema.sql")
  use _ <- result.try(sqlight.exec(schema, conn))
  use version <- result.try(sqlight.query(
    "PRAGMA user_version",
    on: conn,
    with: [],
    expecting: decode.field(0, decode.int, decode.success),
  ))
  use _ <- result.try(case version {
    [version] if version < 2 -> more_kinds(conn, schema)
    _ -> Ok(Nil)
  })
  use _ <- result.try(case version {
    [version] if version < 3 -> categories_v3(conn, version == 0)
    _ -> Ok(Nil)
  })
  sqlight.exec("PRAGMA user_version = 3", conn)
}

/// Version 3: categories with ratings, assigned apps, app types from phones
/// and browser windows split by website. The built-in categories are added
/// once, so deleted ones stay deleted. Rules that are unchanged copies of
/// the old defaults go, the catalog of known apps does that now.
fn categories_v3(conn: Connection, new: Bool) -> Result(Nil, sqlight.Error) {
  use columns <- result.try(sqlight.query(
    "SELECT name FROM pragma_table_info('events')",
    on: conn,
    with: [],
    expecting: decode.field(0, decode.string, decode.success),
  ))
  use _ <- result.try(case list.contains(columns, "site") {
    True -> Ok(Nil)
    False ->
      sqlight.exec(
        "ALTER TABLE events ADD COLUMN site TEXT NOT NULL DEFAULT ''",
        conn,
      )
  })
  use _ <- result.try(add_builtin_categories(conn))
  use <- bool.guard(new, Ok(Nil))
  use rules <- result.try(rules(conn))
  use _ <- result.try(
    list.try_each(rules, fn(rule) {
      let old_default =
        rule.ignore_case
        && rule.devices == []
        && list.contains(categories.old_defaults, #(rule.name, rule.regex))
      case old_default {
        True -> delete_rule(conn, rule.id)
        False -> Ok(Nil)
      }
    }),
  )
  // categories that only existed as rule names
  use defined <- result.try(category_list(conn))
  use _ <- result.try(
    list.map(rules, fn(rule) { rule.name })
    |> list.unique
    |> list.filter(fn(name) { !list.any(defined, fn(c) { c.name == name }) })
    |> list.try_each(save_category(conn, _, categories.Neutral)),
  )
  use devices <- result.try(device_names(conn))
  list.try_each(devices, split_stored(conn, _, 0))
}

/// Adds the built-in categories that don't exist (by name).
pub fn add_builtin_categories(conn: Connection) -> Result(Nil, sqlight.Error) {
  use defined <- result.try(category_list(conn))
  list.filter(categories.builtins, fn(builtin) {
    !list.any(defined, fn(c) { c.builtin == builtin.0 || c.name == builtin.0 })
  })
  |> list.try_each(fn(builtin) {
    exec(
      conn,
      sql.save_category_def(
        name: builtin.0,
        rating: categories.rating_to_string(builtin.1),
        builtin: builtin.0,
      ),
    )
  })
}

/// Splits the stored browser windows of `device` from `since_ms` on by
/// their tabs, see browsing.split.
fn split_stored(
  conn: Connection,
  device: String,
  since_ms: Int,
) -> Result(Nil, sqlight.Error) {
  let load = fn(kind) {
    query(conn, sql.device_events(device:, kind:, since_ms:))
    |> result.map(
      list.filter_map(_, fn(row) {
        use kind <- result.map(shared.kind_from_string(row.kind))
        shared.Event(
          kind:,
          start_ms: row.start_ms,
          duration_ms: row.duration_ms,
          app: row.app,
          title: row.title,
          tz_offset_min: row.tz_offset_min,
        )
      }),
    )
  }
  use windows <- result.try(load("window"))
  use tabs <- result.try(load("web"))
  use <- bool.guard(tabs == [], Ok(Nil))
  use categorize <- result.try(categorizer(conn))
  use <- transaction(conn)
  use _ <- result.try(exec(
    conn,
    sql.delete_device_windows_from(device:, since_ms:),
  ))
  browsing.split(list.append(windows, tabs))
  |> list.filter(fn(entry) { { entry.0 }.kind == shared.Window })
  |> list.try_each(insert(conn, device, categorize, _))
}

/// What categories come from now.
pub fn setup(conn: Connection) -> Result(categories.Setup, sqlight.Error) {
  use defined <- result.try(category_list(conn))
  use rules <- result.try(rules(conn))
  use assigned <- result.try(query(conn, sql.list_assigned()))
  use types <- result.map(query(conn, sql.list_app_types()))
  categories.Setup(
    categories: defined,
    rules:,
    assigned: list.map(assigned, fn(row) {
      #(string.lowercase(row.app), row.category)
    })
      |> dict.from_list,
    types: list.map(types, fn(row) { #(string.lowercase(row.app), row.type_) })
      |> dict.from_list,
  )
}

pub fn categorizer(
  conn: Connection,
) -> Result(
  fn(String, String, String, String) -> categories.Match,
  sqlight.Error,
) {
  setup(conn) |> result.map(categories.categorizer)
}

fn insert(
  conn: Connection,
  device: String,
  categorize: fn(String, String, String, String) -> categories.Match,
  entry: #(shared.Event, String),
) -> Result(Nil, sqlight.Error) {
  let #(e, site) = entry
  exec(
    conn,
    sql.insert_event(
      device:,
      kind: shared.kind_to_string(e.kind),
      start_ms: e.start_ms,
      duration_ms: e.duration_ms,
      app: e.app,
      title: e.title,
      category: categorize(device, e.app, e.title, site).category,
      tz_offset_min: e.tz_offset_min,
      site:,
    ),
  )
}

/// The categories in the order of their colors.
pub fn category_list(
  conn: Connection,
) -> Result(List(categories.Category), sqlight.Error) {
  use rows <- result.map(query(conn, sql.list_category_defs()))
  use row <- list.map(rows)
  categories.Category(
    row.name,
    categories.rating_from_string(row.rating)
      |> result.unwrap(categories.Neutral),
    row.builtin,
  )
}

/// Adds a category, or changes its rating.
pub fn save_category(
  conn: Connection,
  name: String,
  rating: categories.Rating,
) -> Result(Nil, sqlight.Error) {
  exec(
    conn,
    sql.save_category_def(
      name:,
      rating: categories.rating_to_string(rating),
      builtin: "",
    ),
  )
}

/// Renames a category with its rules and assigned apps.
pub fn rename_category(
  conn: Connection,
  old_name: String,
  new_name: String,
) -> Result(Nil, sqlight.Error) {
  use <- transaction(conn)
  use _ <- result.try(exec(conn, sql.rename_category_def(old_name:, new_name:)))
  use _ <- result.try(exec(
    conn,
    sql.rename_category_rules(old_name:, new_name:),
  ))
  exec(conn, sql.rename_category_assigned(old_name:, new_name:))
}

/// Deletes a category with its rules, its apps go back to automatic.
pub fn delete_category(
  conn: Connection,
  name: String,
) -> Result(Nil, sqlight.Error) {
  use <- transaction(conn)
  use _ <- result.try(exec(conn, sql.delete_category_def(name:)))
  use _ <- result.try(exec(conn, sql.delete_category_rules(name:)))
  exec(conn, sql.delete_category_assigned(name:))
}

/// Puts an app or website into a category by hand, "" goes back to
/// automatic.
pub fn assign(
  conn: Connection,
  app: String,
  category: String,
) -> Result(Nil, sqlight.Error) {
  case category {
    "" -> exec(conn, sql.unassign(app:))
    category -> exec(conn, sql.assign(app:, category:))
  }
}

/// Version 2: events of phones (screen, unlock, notification, audio) with
/// their UTC offset, and when devices last uploaded. SQLite can't change a
/// CHECK, so the events table is copied into a new one.
fn more_kinds(conn: Connection, schema: String) -> Result(Nil, sqlight.Error) {
  use events <- result.try(sqlight.query(
    "SELECT sql FROM sqlite_schema WHERE name = 'events'",
    on: conn,
    with: [],
    expecting: decode.field(0, decode.string, decode.success),
  ))
  use _ <- result.try(case events {
    [sql] ->
      case string.contains(sql, "'unlock'") {
        True -> Ok(Nil)
        False -> {
          use <- transaction(conn)
          sqlight.exec("ALTER TABLE events RENAME TO events_v1;
            DROP INDEX events_start;
            DROP INDEX events_app;" <> schema <> "INSERT INTO events (device, kind, start_ms, duration_ms, app, title, category)
            SELECT device, kind, start_ms, duration_ms, app, title, category FROM events_v1;
            DROP TABLE events_v1;", conn)
        }
      }
    _ -> Ok(Nil)
  })
  use columns <- result.try(sqlight.query(
    "SELECT name FROM pragma_table_info('devices')",
    on: conn,
    with: [],
    expecting: decode.field(0, decode.string, decode.success),
  ))
  case list.contains(columns, "last_upload_ms") {
    True -> Ok(Nil)
    False ->
      sqlight.exec(
        "ALTER TABLE devices ADD COLUMN last_upload_ms INTEGER NOT NULL DEFAULT 0",
        conn,
      )
  }
}

fn param(p: dev.Param) -> sqlight.Value {
  case p {
    dev.ParamBool(x) -> sqlight.bool(x)
    dev.ParamFloat(x) -> sqlight.float(x)
    dev.ParamInt(x) -> sqlight.int(x)
    dev.ParamString(x) -> sqlight.text(x)
    dev.ParamBitArray(x) -> sqlight.blob(x)
    dev.ParamNullable(x) -> sqlight.nullable(param, x)
    dev.ParamList(_) -> panic as "sqlite does not implement lists"
    dev.ParamDate(_) -> panic as "date parameter needs to be implemented"
    dev.ParamTimestamp(_) -> panic as "sqlite does not support timestamps"
    dev.ParamDynamic(_) -> panic as "cannot process dynamic parameter"
  }
}

fn query(
  conn: Connection,
  q: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(List(a), sqlight.Error) {
  let #(sql, with, expecting) = q
  sqlight.query(sql, on: conn, with: list.map(with, param), expecting:)
}

fn query_one(
  conn: Connection,
  q: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(a, sqlight.Error) {
  case query(conn, q) {
    Ok([row]) -> Ok(row)
    Ok(_) ->
      Error(sqlight.SqlightError(sqlight.GenericError, "expected one row", -1))
    Error(err) -> Error(err)
  }
}

fn exec(
  conn: Connection,
  q: #(String, List(dev.Param)),
) -> Result(Nil, sqlight.Error) {
  let #(sql, with) = q
  sqlight.query(
    sql,
    on: conn,
    with: list.map(with, param),
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
}

fn transaction(
  conn: Connection,
  body: fn() -> Result(a, sqlight.Error),
) -> Result(a, sqlight.Error) {
  use _ <- result.try(sqlight.exec("BEGIN", conn))
  let written = body()
  let end = case written {
    Ok(_) -> "COMMIT"
    Error(_) -> "ROLLBACK"
  }
  use _ <- result.try(sqlight.exec(end, conn))
  written
}

/// End of the newest stored event of a device, 0 if there is none.
pub fn cursor(conn: Connection, device: String) -> Result(Int, sqlight.Error) {
  query_one(conn, sql.cursor(device:))
  |> result.map(fn(row) { row.cursor_ms })
}

/// Replaces everything `device` did from `upload.from_ms` on. Events that
/// started before are cut off there, ActivityWatch sends their rest again.
/// Browser windows are split by their tabs (browsing.split) and every event
/// gets its category, with the app types of the upload. The device's OS is
/// kept unless the upload has none, and the time of the upload is noted.
pub fn replace_events(
  conn: Connection,
  device: String,
  upload: shared.Upload,
) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(
    list.try_each(upload.app_types, fn(entry) {
      exec(conn, sql.set_app_type(app: entry.0, type_: entry.1))
    }),
  )
  use categorize <- result.try(categorizer(conn))
  use <- transaction(conn)
  use _ <- result.try(exec(
    conn,
    sql.delete_events_from(device:, from_ms: upload.from_ms),
  ))
  use _ <- result.try(exec(
    conn,
    sql.cut_events_at(device:, from_ms: upload.from_ms),
  ))
  use _ <- result.try(exec(conn, sql.device_uploaded(device:, os: upload.os)))
  browsing.split(upload.events)
  |> list.try_each(insert(conn, device, categorize, _))
}

pub fn rules(conn: Connection) -> Result(List(Rule), sqlight.Error) {
  use rows <- result.map(query(conn, sql.list_rules()))
  use row <- list.map(rows)
  Rule(
    id: row.id,
    name: row.name,
    regex: row.regex,
    ignore_case: row.ignore_case,
    devices: json.parse(row.devices, decode.list(decode.string))
      |> result.unwrap([]),
  )
}

/// Adds a rule, or changes the one with the id.
pub fn save_rule(
  conn: Connection,
  id: Option(Int),
  rule: Rule,
) -> Result(Nil, sqlight.Error) {
  exec(
    conn,
    sql.save_rule(
      id:,
      name: rule.name,
      regex: rule.regex,
      ignore_case: rule.ignore_case,
      devices: json.array(rule.devices, json.string) |> json.to_string,
    ),
  )
}

pub fn delete_rule(conn: Connection, id: Int) -> Result(Nil, sqlight.Error) {
  exec(conn, sql.delete_rule(id:))
}

/// Puts all stored events into categories again, after the rules changed.
pub fn recategorize(conn: Connection) -> Result(Nil, sqlight.Error) {
  use categorize <- result.try(categorizer(conn))
  use rows <- result.try(query(conn, sql.event_categories()))
  use <- transaction(conn)
  use row <- list.try_each(rows)
  case categorize(row.device, row.app, row.title, row.site).category {
    same if same == row.category -> Ok(Nil)
    category ->
      exec(
        conn,
        sql.set_category(
          category:,
          device: row.device,
          app: row.app,
          title: row.title,
          site: row.site,
        ),
      )
  }
}

/// Deletes everything `device` sent.
pub fn delete_device(
  conn: Connection,
  device: String,
) -> Result(Nil, sqlight.Error) {
  use <- transaction(conn)
  use _ <- result.try(exec(conn, sql.delete_device(device:)))
  exec(conn, sql.delete_device_info(device:))
}

/// All devices that ever sent something.
pub fn device_names(conn: Connection) -> Result(List(String), sqlight.Error) {
  query(conn, sql.device_names())
  |> result.map(list.map(_, fn(row) { row.device }))
}

/// The operating system of each device that sent one.
pub fn device_systems(
  conn: Connection,
) -> Result(dict.Dict(String, String), sqlight.Error) {
  use rows <- result.map(query(conn, sql.device_systems()))
  list.filter(rows, fn(row) { row.os != "" })
  |> list.map(fn(row) { #(row.name, row.os) })
  |> dict.from_list
}

/// When each device last uploaded (Unix ms), 0 for before the server
/// noted it.
pub fn last_uploads(
  conn: Connection,
) -> Result(dict.Dict(String, Int), sqlight.Error) {
  use rows <- result.map(query(conn, sql.device_systems()))
  list.map(rows, fn(row) { #(row.name, row.last_upload_ms) }) |> dict.from_list
}

/// What the dashboard shows: the `days` days up to and including `date`
/// (local dates like "2026-10-26") of one device, or of all devices if
/// `device` is "". They are the time from `since_ms` to `until_ms`. The
/// period of the same length before starts at `previous_since_ms` and ends on
/// `previous_date`, the one after ends on `next_date`. `now_ms` is when the
/// filter was made.
pub type Filter {
  Filter(
    date: String,
    first_date: String,
    days: Int,
    device: String,
    since_ms: Int,
    until_ms: Int,
    previous_since_ms: Int,
    previous_date: String,
    next_date: String,
    today: String,
    now_ms: Int,
  )
}

/// An invalid `date`, like "", is today.
pub fn filter(
  conn: Connection,
  date: String,
  days: Int,
  device: String,
) -> Result(Filter, sqlight.Error) {
  use row <- result.map(query_one(conn, sql.range(date:, days:)))
  Filter(
    date: row.date,
    first_date: row.first_date,
    days:,
    device:,
    since_ms: row.since_ms,
    until_ms: row.until_ms,
    previous_since_ms: row.previous_since_ms,
    previous_date: row.previous_date,
    next_date: row.next_date,
    today: row.today,
    now_ms: row.now_ms,
  )
}

/// The same filter for the period before.
pub fn previous(filter: Filter) -> Filter {
  Filter(
    ..filter,
    since_ms: filter.previous_since_ms,
    until_ms: filter.since_ms,
    date: filter.previous_date,
  )
}

/// A local day, `weekday` is 0 for Sunday to 6 for Saturday.
pub type Day {
  Day(date: String, weekday: Int, start_ms: Int, end_ms: Int)
}

/// The days of the filter, oldest first.
pub fn days(
  conn: Connection,
  filter: Filter,
) -> Result(List(Day), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.days(first_date: filter.first_date, last_date: filter.date),
  ))
  use row <- list.map(rows)
  Day(row.date, row.weekday, row.start_ms, row.end_ms)
}

/// A stretch of screen time, with the local date, hour ("07") and times
/// ("07:45") it started and ended.
pub type Stretch {
  Stretch(
    device: String,
    category: String,
    date: String,
    hour: String,
    start_time: String,
    end_time: String,
    start_ms: Int,
    end_ms: Int,
  )
}

/// All screen time of the filter, sorted by start.
pub fn screen_time(
  conn: Connection,
  filter: Filter,
) -> Result(List(Stretch), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.screen_time(
      since_ms: filter.since_ms,
      until_ms: filter.until_ms,
      device: filter.device,
    ),
  ))
  use row <- list.map(rows)
  Stretch(
    device: row.device,
    category: row.category,
    date: row.date,
    hour: row.hour,
    start_time: row.start_time,
    end_time: row.end_time,
    start_ms: row.start_ms,
    end_ms: row.end_ms,
  )
}

pub type Usage {
  Usage(name: String, detail: String, ms: Int)
}

/// "laptop,phone" -> "laptop, phone"
fn device_list(devices: String) -> String {
  string.replace(devices, ",", ", ")
}

/// Usage per device, `detail` is when it was last active (local time).
pub fn devices(
  conn: Connection,
  filter: Filter,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.top_devices(since_ms: filter.since_ms, until_ms: filter.until_ms),
  ))
  use row <- list.map(rows)
  Usage(row.name, row.detail, row.ms)
}

pub fn categories(
  conn: Connection,
  filter: Filter,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.top_categories(
      since_ms: filter.since_ms,
      until_ms: filter.until_ms,
      device: filter.device,
    ),
  ))
  use row <- list.map(rows)
  Usage(row.name, "", row.ms)
}

pub fn apps(conn: Connection, filter: Filter) {
  top_apps(conn, filter, "window")
}

pub fn domains(conn: Connection, filter: Filter) {
  top_apps(conn, filter, "web")
}

fn top_apps(
  conn: Connection,
  filter: Filter,
  kind: String,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.top_apps(
      kind:,
      since_ms: filter.since_ms,
      until_ms: filter.until_ms,
      device: filter.device,
    ),
  ))
  use row <- list.map(rows)
  Usage(row.name, device_list(row.detail), row.ms)
}

pub fn titles(
  conn: Connection,
  filter: Filter,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.top_titles(
      since_ms: filter.since_ms,
      until_ms: filter.until_ms,
      device: filter.device,
    ),
  ))
  use row <- list.map(rows)
  Usage(row.name, row.detail, row.ms)
}

/// A block of the activity view: the screen time of `category` from
/// `since_ms` to `until_ms` on `device`, or on all devices if it is "".
pub type Block {
  Block(device: String, category: String, since_ms: Int, until_ms: Int)
}

/// The apps of a block, with the time cut to it.
pub fn block_apps(
  conn: Connection,
  block: Block,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.block_apps(
      until_ms: block.until_ms,
      since_ms: block.since_ms,
      category: block.category,
      device: block.device,
    ),
  ))
  use row <- list.map(rows)
  Usage(row.name, device_list(row.detail), row.ms)
}

/// The window titles of a block, the detail is the app.
pub fn block_titles(
  conn: Connection,
  block: Block,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.block_titles(
      until_ms: block.until_ms,
      since_ms: block.since_ms,
      category: block.category,
      device: block.device,
    ),
  ))
  use row <- list.map(rows)
  Usage(row.name, row.detail, row.ms)
}

/// Screen time per category name since `since_ms`.
pub fn category_totals(
  conn: Connection,
  since_ms: Int,
) -> Result(List(#(String, Int)), sqlight.Error) {
  use rows <- result.map(query(conn, sql.category_totals(since_ms:)))
  list.map(rows, fn(row) { #(row.name, row.ms) })
}

/// Usage of an app and title on a device, `kind` is "window" or "web".
/// Screen time of an app, title and site (the website of a browser window,
/// "" if none) on a device.
pub type Recent {
  Recent(device: String, app: String, title: String, site: String, ms: Int)
}

/// Screen time since `since_ms`, summed per device, app, title and site.
pub fn recent_usage(
  conn: Connection,
  since_ms: Int,
) -> Result(List(Recent), sqlight.Error) {
  use rows <- result.map(query(conn, sql.recent_usage(since_ms:)))
  use row <- list.map(rows)
  Recent(row.device, row.app, row.title, row.site, row.ms)
}

/// Apps and domains that took the most time without a category.
pub fn uncategorized_apps(
  conn: Connection,
  filter: Filter,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.uncategorized_apps(since_ms: filter.since_ms),
  ))
  use row <- list.map(rows)
  Usage(row.name, device_list(row.detail), row.ms)
}

/// Window titles that took the most time without a category.
pub fn uncategorized_titles(
  conn: Connection,
  filter: Filter,
) -> Result(List(Usage), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.uncategorized_titles(since_ms: filter.since_ms),
  ))
  use row <- list.map(rows)
  Usage(row.name, row.detail, row.ms)
}

/// Everything that happened from `since_ms` to `until_ms` on `device`, or on
/// all devices if it is "", sorted by start.
pub fn activity(
  conn: Connection,
  since_ms: Int,
  until_ms: Int,
  device: String,
) -> Result(List(sql.Activity), sqlight.Error) {
  query(conn, sql.activity(since_ms:, until_ms:, device:))
}

/// Screen time from `since_ms` to `until_ms` as intervals sorted by start.
pub fn screen_intervals(
  conn: Connection,
  since_ms: Int,
  until_ms: Int,
  device: String,
) -> Result(List(#(Int, Int)), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.screen_intervals(since_ms:, until_ms:, device:),
  ))
  list.map(rows, fn(row) { #(row.start_ms, row.end_ms) })
}

/// Screen time of a local date and hour (when it started) and a category
/// or app, summed over the devices.
pub type Daily {
  Daily(date: String, hour: Int, name: String, ms: Int)
}

/// Per local date, hour and category.
pub fn daily_categories(
  conn: Connection,
  since_ms: Int,
  until_ms: Int,
  device: String,
) -> Result(List(Daily), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.daily_categories(since_ms:, until_ms:, device:),
  ))
  list.map(rows, fn(row) { Daily(row.date, row.hour, row.category, row.ms) })
}

/// Per local date, hour and app.
pub fn daily_apps(
  conn: Connection,
  since_ms: Int,
  until_ms: Int,
  device: String,
) -> Result(List(Daily), sqlight.Error) {
  use rows <- result.map(query(
    conn,
    sql.daily_apps(since_ms:, until_ms:, device:),
  ))
  list.map(rows, fn(row) { Daily(row.date, row.hour, row.app, row.ms) })
}
