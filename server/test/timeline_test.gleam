import db
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import shared.{Event}
import sqlight
import stats
import timeline

const minute = 60_000

const hour = 3_600_000

fn with_db(run: fn(sqlight.Connection) -> a) -> a {
  use conn <- sqlight.with_connection(":memory:")
  let assert Ok(Nil) = db.migrate(conn)
  run(conn)
}

fn upload(conn, device, events) {
  let assert Ok(Nil) =
    db.replace_events(
      conn,
      device,
      shared.Upload(from_ms: 0, os: "", events:, app_types: []),
    )
  Nil
}

fn window(start, length, app) {
  Event(shared.Window, start, length, app, app, None)
}

fn load(conn, date, days) {
  let assert Ok(filter) = db.filter(conn, date, days, "")
  let assert Ok(report) = stats.load(conn, filter)
  let assert Ok(t) = timeline.load(conn, filter, report.days)
  #(report, t)
}

pub fn day_test() {
  use conn <- with_db
  let assert Ok(today) = db.filter(conn, "", 1, "")
  let yesterday = today.previous_date
  let start = today.since_ms - 24 * hour + 9 * hour
  upload(conn, "laptop", [
    // 09:00 to 09:20, over two buckets
    window(start, 20 * minute, "Code"),
    window(start + 20 * minute, 10 * minute, "Firefox"),
    // a new session
    window(start + hour, 5 * minute, "Code"),
  ])
  // at the same time on the phone
  upload(conn, "phone", [window(start, 10 * minute, "Signal")])
  let #(report, t) = load(conn, yesterday, 1)
  assert list.length(t.buckets) == 96
  let assert Ok(nine) = list.drop(t.buckets, 36) |> list.first
  assert nine.label == "09:00"
  assert nine.ms == 15 * minute
  // the stack is as high as the screen time
  assert list.fold(t.buckets, 0, fn(sum, b) { sum + b.ms }) == report.total_ms
  let stacked = list.fold(t.series, 0, fn(sum, s) { sum + int.sum(s.values) })
  assert stacked == report.total_ms
  let assert [first, ..] = t.series
  assert first.name == "Code"

  let assert [morning, later] = t.sessions
  assert morning.start == "09:00" && morning.end == "09:30"
  assert morning.active_ms == 30 * minute
  assert list.sort(morning.devices, string.compare) == ["laptop", "phone"]
  let assert [code, ..] = morning.apps
  assert code.name == "Code" && code.ms == 20 * minute
  assert later.start == "10:00"
}

pub fn other_and_week_test() {
  use conn <- with_db
  let assert Ok(today) = db.filter(conn, "", 1, "")
  let start = today.since_ms - 24 * hour + 9 * hour
  let apps = ["A", "B", "C", "D", "E", "F", "G", "H"]
  upload(
    conn,
    "laptop",
    list.index_map(apps, fn(app, i) {
      window(start + i * 10 * minute, { 8 - i } * minute, app)
    }),
  )
  let #(_, t) = load(conn, today.previous_date, 7)
  assert list.length(t.buckets) == 7 * 24
  let names = list.map(t.series, fn(s) { s.name })
  assert names == ["A", "B", "C", "D", "E", "F", "Other"]
  let assert Ok(other) = list.last(t.series)
  assert other.total_ms == 3 * minute
  let #(_, t) = load(conn, today.previous_date, 30)
  assert list.length(t.buckets) == 30
  assert t.sessions == []
}
