//// The queries are in src/sql/*.sql, parrot turns them into src/server/sql.gleam
//// (see README.md). This module runs them with sqlight.

import categories.{type Rule, Rule}
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
  // the default categories are added once, so deleted ones stay deleted
  case version {
    [0] -> {
      use _ <- result.try(add_rules(conn, categories.defaults))
      sqlight.exec("PRAGMA user_version = 1", conn)
    }
    _ -> Ok(Nil)
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
/// `category` gets the device, app and title of an event. The device's OS is
/// kept unless the upload has none.
pub fn replace_events(
  conn: Connection,
  device: String,
  upload: shared.Upload,
  category: fn(String, String, String) -> String,
) -> Result(Nil, sqlight.Error) {
  use <- transaction(conn)
  use _ <- result.try(exec(
    conn,
    sql.delete_events_from(device:, from_ms: upload.from_ms),
  ))
  use _ <- result.try(exec(
    conn,
    sql.cut_events_at(device:, from_ms: upload.from_ms),
  ))
  use _ <- result.try(case upload.os {
    "" -> Ok(Nil)
    os -> exec(conn, sql.set_device_os(device:, os:))
  })
  list.try_each(upload.events, fn(e) {
    exec(
      conn,
      sql.insert_event(
        device:,
        kind: shared.kind_to_string(e.kind),
        start_ms: e.start_ms,
        duration_ms: e.duration_ms,
        app: e.app,
        title: e.title,
        category: category(device, e.app, e.title),
      ),
    )
  })
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

/// Adds the rules whose category doesn't exist yet.
pub fn add_rules(
  conn: Connection,
  new: List(Rule),
) -> Result(Nil, sqlight.Error) {
  use existing <- result.try(rules(conn))
  let names = list.map(existing, fn(rule) { rule.name })
  list.filter(new, fn(rule) { !list.contains(names, rule.name) })
  |> list.try_each(save_rule(conn, option.None, _))
}

pub fn delete_rule(conn: Connection, id: Int) -> Result(Nil, sqlight.Error) {
  exec(conn, sql.delete_rule(id:))
}

/// Puts all stored events into categories again, after the rules changed.
pub fn recategorize(
  conn: Connection,
  category: fn(String, String, String) -> String,
) -> Result(Nil, sqlight.Error) {
  use rows <- result.try(query(conn, sql.event_categories()))
  use <- transaction(conn)
  use row <- list.try_each(rows)
  case category(row.device, row.app, row.title) {
    same if same == row.category -> Ok(Nil)
    category ->
      exec(
        conn,
        sql.set_category(
          category:,
          device: row.device,
          app: row.app,
          title: row.title,
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
  list.map(rows, fn(row) { #(row.name, row.os) }) |> dict.from_list
}

/// What the dashboard shows: the `days` days up to and including `date`
/// (local dates like "2026-10-26") of one device, or of all devices if
/// `device` is "". They are the time from `since_ms` to `until_ms`. The
/// period of the same length before starts at `previous_since_ms` and ends on
/// `previous_date`, the one after ends on `next_date`.
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
