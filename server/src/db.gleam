import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import shared
import sqlight.{type Connection}

const schema =
  "
CREATE TABLE IF NOT EXISTS events (
    device      TEXT    NOT NULL,
    kind        TEXT    NOT NULL CHECK (kind IN ('window', 'web')),
    start_ms    INTEGER NOT NULL,
    duration_ms INTEGER NOT NULL CHECK (duration_ms >= 0),
    app         TEXT    NOT NULL,
    title       TEXT    NOT NULL,
    category    TEXT    NOT NULL,
    PRIMARY KEY (device, kind, start_ms)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS events_start ON events(start_ms);
"

pub fn migrate(conn: Connection) -> Result(Nil, sqlight.Error) {
  sqlight.exec(schema, conn)
}

/// End of the newest stored event of a device, 0 if there is none.
pub fn cursor(conn: Connection, device: String) -> Result(Int, sqlight.Error) {
  sqlight.query(
    "SELECT coalesce(max(start_ms + duration_ms), 0) FROM events WHERE device = ?1",
    on: conn,
    with: [sqlight.text(device)],
    expecting: decode.field(0, decode.int, decode.success),
  )
  |> result.map(fn(rows) { list.first(rows) |> result.unwrap(0) })
}

/// Replaces everything `device` did from `upload.from_ms` on. Events that
/// started before are cut off there, ActivityWatch sends their rest again.
pub fn replace_events(
  conn: Connection,
  device: String,
  upload: shared.Upload,
) -> Result(Nil, sqlight.Error) {
  let run = fn(sql, with) {
    sqlight.query(sql, on: conn, with:, expecting: decode.success(Nil))
  }
  let from = [sqlight.text(device), sqlight.int(upload.from_ms)]
  use _ <- result.try(sqlight.exec("BEGIN", conn))
  let written = {
    use _ <- result.try(run(
      "DELETE FROM events WHERE device = ?1 AND start_ms >= ?2",
      from,
    ))
    use _ <- result.try(run(
      "UPDATE events SET duration_ms = ?2 - start_ms
       WHERE device = ?1 AND start_ms + duration_ms > ?2",
      from,
    ))
    list.try_each(upload.events, fn(e) {
      run("INSERT OR REPLACE INTO events VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)", [
        sqlight.text(device),
        sqlight.text(shared.kind_to_string(e.kind)),
        sqlight.int(e.start_ms),
        sqlight.int(e.duration_ms),
        sqlight.text(e.app),
        sqlight.text(e.title),
        sqlight.text(e.category),
      ])
    })
  }
  let end = case written {
    Ok(_) -> "COMMIT"
    Error(_) -> "ROLLBACK"
  }
  use _ <- result.try(sqlight.exec(end, conn))
  written
}

/// What the dashboard shows: the last `days` days (1 is today) of one
/// device, or of all devices if `device` is "".
pub type Filter {
  Filter(days: Int, device: String)
}

/// Events in the filter. ?1 is the number of days, ?2 the device.
const filtered =
  "
  FROM events
  WHERE start_ms >= unixepoch('now', 'localtime', 'start of day', printf('-%d days', ?1 - 1), 'utc') * 1000
    AND (?2 = '' OR device = ?2)"

fn query(conn, filter: Filter, sql, decoder) {
  sqlight.query(
    sql,
    on: conn,
    with: [sqlight.int(filter.days), sqlight.text(filter.device)],
    expecting: decoder,
  )
}

pub type Usage {
  Usage(name: String, detail: String, ms: Int)
}

/// Screen time per hour for today, otherwise per day. Time spent on several
/// devices at once is counted only once.
pub fn timeline(
  conn: Connection,
  filter: Filter,
) -> Result(List(Usage), sqlight.Error) {
  let #(labels, bucket) = case filter.days {
    1 -> #(
      "WITH RECURSIVE b(x) AS (SELECT 0 UNION ALL SELECT x + 1 FROM b WHERE x < 23)
       SELECT printf('%02d', x) FROM b WHERE ?1 = ?1 AND ?2 = ?2",
      "strftime('%H', start_ms / 1000, 'unixepoch', 'localtime')",
    )
    _ -> #(
      "WITH RECURSIVE b(x) AS (
         SELECT date('now', 'localtime', printf('-%d days', ?1 - 1)) WHERE ?2 = ?2
         UNION ALL SELECT date(x, '+1 day') FROM b WHERE x < date('now', 'localtime'))
       SELECT x FROM b",
      "date(start_ms / 1000, 'unixepoch', 'localtime')",
    )
  }
  use labels <- result.try(query(
    conn,
    filter,
    labels,
    decode.field(0, decode.string, decode.success),
  ))
  use rows <- result.map(
    query(
      conn,
      filter,
      "SELECT "
        <> bucket
        <> ", start_ms, start_ms + duration_ms"
        <> filtered
        <> " AND kind = 'window' ORDER BY start_ms",
      {
        use label <- decode.field(0, decode.string)
        use start <- decode.field(1, decode.int)
        use end <- decode.field(2, decode.int)
        decode.success(#(label, #(start, end)))
      },
    ),
  )
  let totals =
    list.group(rows, fn(row) { row.0 })
    |> dict.map_values(fn(_, rows) {
      list.reverse(rows) |> list.map(fn(row) { row.1 }) |> union_ms
    })
  list.map(labels, fn(label) {
    Usage(label, "", dict.get(totals, label) |> result.unwrap(0))
  })
}

/// Length of the union of intervals sorted by start.
fn union_ms(intervals: List(#(Int, Int))) -> Int {
  let #(total, _) =
    list.fold(intervals, #(0, 0), fn(acc, interval) {
      let #(total, reach) = acc
      let start = int.max(interval.0, reach)
      case interval.1 > start {
        True -> #(total + interval.1 - start, interval.1)
        False -> acc
      }
    })
  total
}

/// Usage per device, `detail` is when it was last active (local time).
pub fn devices(
  conn: Connection,
  days: Int,
) -> Result(List(Usage), sqlight.Error) {
  top(
    conn,
    Filter(days, ""),
    "window",
    "device",
    "datetime(max(start_ms + duration_ms) / 1000, 'unixepoch', 'localtime')",
  )
}

pub fn categories(conn, filter) {
  top(conn, filter, "window", "category", "''")
}

pub fn apps(conn, filter) {
  top(conn, filter, "window", "app", "group_concat(DISTINCT device)")
}

pub fn titles(conn, filter) {
  top(conn, filter, "window", "title", "app")
}

pub fn domains(conn, filter) {
  top(conn, filter, "web", "app", "group_concat(DISTINCT device)")
}

/// The things that took the most time, `column` and `detail` are SQL.
fn top(
  conn: Connection,
  filter: Filter,
  kind: String,
  column: String,
  detail: String,
) -> Result(List(Usage), sqlight.Error) {
  query(
    conn,
    filter,
    "SELECT "
      <> column
      <> ", "
      <> detail
      <> ", sum(duration_ms)"
      <> filtered
      <> " AND kind = '"
      <> kind
      <> "' GROUP BY 1 ORDER BY 3 DESC LIMIT 15",
    {
      use name <- decode.field(0, decode.string)
      use detail <- decode.field(1, decode.string)
      use ms <- decode.field(2, decode.int)
      decode.success(Usage(
        name:,
        detail: string.replace(detail, ",", ", "),
        ms:,
      ))
    },
  )
}
