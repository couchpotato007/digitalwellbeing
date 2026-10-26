import categories.{Rule}
import db
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import shared.{Event}
import sqlight
import stats

fn with_db(run: fn(sqlight.Connection) -> a) -> a {
  use conn <- sqlight.with_connection(":memory:")
  let assert Ok(Nil) = db.migrate(conn)
  run(conn)
}

fn upload(conn, device, events) {
  let assert Ok(rules) = db.rules(conn)
  let assert Ok(Nil) =
    db.replace_events(
      conn,
      device,
      shared.Upload(from_ms: 0, os: "", events:),
      categories.categorizer(rules),
    )
  Nil
}

fn category_of(conn, app) {
  let assert Ok(filter) = db.filter(conn, "", 365, "")
  let assert Ok(apps) = db.apps(conn, filter)
  let assert Ok(categories) = db.categories(conn, filter)
  let assert Ok(_) = list.find(apps, fn(usage) { usage.name == app })
  categories
}

fn now_ms() {
  let assert Ok(filter) = with_db(db.filter(_, "", 1, ""))
  // start of today, plus an hour
  filter.since_ms + 3_600_000
}

pub fn migrate_adds_defaults_once_test() {
  use conn <- with_db
  let assert Ok(rules) = db.rules(conn)
  assert list.length(rules) == list.length(categories.defaults)

  let assert [first, ..] = rules
  let assert Ok(Nil) = db.delete_rule(conn, first.id)
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(rules) = db.rules(conn)
  assert list.length(rules) == list.length(categories.defaults) - 1

  let assert Ok(Nil) = db.add_rules(conn, categories.defaults)
  let assert Ok(rules) = db.rules(conn)
  assert list.length(rules) == list.length(categories.defaults)
}

pub fn save_rule_test() {
  use conn <- with_db
  let rule = Rule(0, "Work > Wellbeing", "wellbeing", False, ["laptop"])
  let assert Ok(Nil) = db.save_rule(conn, None, rule)
  let assert Ok(rules) = db.rules(conn)
  let assert Ok(saved) = list.find(rules, fn(r) { r.name == rule.name })
  assert saved.devices == ["laptop"]
  assert saved.ignore_case == False

  let assert Ok(Nil) =
    db.save_rule(conn, Some(saved.id), Rule(..rule, ignore_case: True))
  let assert Ok(rules) = db.rules(conn)
  let assert Ok(saved) = list.find(rules, fn(r) { r.id == saved.id })
  assert saved.ignore_case == True
}

pub fn ingest_and_recategorize_test() {
  use conn <- with_db
  let start = now_ms()
  upload(conn, "laptop", [
    Event(shared.Window, start, 600_000, "Code", "db.gleam"),
    Event(shared.Window, start + 600_000, 300_000, "firefox", "Some page"),
    Event(shared.Web, start + 600_000, 300_000, "example.org", "Some page"),
  ])
  let assert Ok(cursor) = db.cursor(conn, "laptop")
  assert cursor == start + 900_000

  assert category_of(conn, "Code")
    == [
      db.Usage("Work > Programming", "", 600_000),
      db.Usage("Uncategorized", "", 300_000),
    ]

  let assert Ok(Nil) =
    db.save_rule(conn, None, Rule(0, "Browsing", "firefox", True, []))
  let assert Ok(rules) = db.rules(conn)
  let assert Ok(Nil) = db.recategorize(conn, categories.categorizer(rules))
  assert category_of(conn, "firefox")
    == [
      db.Usage("Work > Programming", "", 600_000),
      db.Usage("Browsing", "", 300_000),
    ]
}

pub fn dashboard_queries_test() {
  use conn <- with_db
  let start = now_ms()
  upload(conn, "laptop", [Event(shared.Window, start, 60_000, "Code", "a")])
  upload(conn, "desktop", [
    Event(shared.Window, start + 30_000, 60_000, "Code", "b"),
    Event(shared.Web, start + 30_000, 60_000, "example.org", "c"),
  ])
  let assert Ok(today) = db.filter(conn, "", 1, "")
  let assert Ok(report) = stats.load(conn, today)
  assert list.length(report.timeline) == 24
  // both devices at once count once
  assert report.total_ms == 90_000
  assert list.fold(report.timeline, 0, fn(sum, hour) { sum + hour.ms })
    == 90_000
  assert report.sessions == 1
  assert report.longest_session_ms == 90_000
  assert report.first_active == "01:00"
  assert report.previous_ms == 0
  // one strip per device
  let assert [desktop, laptop] = report.strips
  assert desktop.label == "desktop" && laptop.label == "laptop"
  let assert [stats.Segment(_, _, "laptop", "Work > Programming")] =
    laptop.segments

  let assert Ok(week) = db.filter(conn, today.date, 7, "laptop")
  let assert Ok(report) = stats.load(conn, week)
  assert list.length(report.timeline) == 7
  assert report.total_ms == 60_000
  // one strip per day
  assert list.length(report.strips) == 7

  // a day of all devices keeps the devices apart, even in one category
  let assert Ok(week) = db.filter(conn, today.date, 7, "")
  let assert Ok(report) = stats.load(conn, week)
  let assert Ok(last) = list.last(report.strips)
  let assert [first, second] = last.segments
  assert first.device == "laptop" && second.device == "desktop"

  // the day before has nothing, the week before neither
  let assert Ok(yesterday) = db.filter(conn, today.previous_date, 1, "")
  let assert Ok(report) = stats.load(conn, yesterday)
  assert report.total_ms == 0
  assert yesterday.next_date == today.date

  // tomorrow compares with today
  let assert Ok(tomorrow) = db.filter(conn, today.next_date, 1, "")
  let assert Ok(report) = stats.load(conn, tomorrow)
  assert report.previous_ms == 90_000

  let assert Ok([code]) = db.apps(conn, today)
  assert code.detail == "desktop, laptop" || code.detail == "laptop, desktop"
  let assert Ok([_]) = db.domains(conn, today)
  let assert Ok([_, _]) = db.titles(conn, today)
  let assert Ok([_, _]) = db.devices(conn, today)
  let assert Ok([_]) = db.uncategorized_apps(conn, today)
  let assert Ok([]) = db.uncategorized_titles(conn, today)
  let assert Ok(["desktop", "laptop"]) = db.device_names(conn)
}

pub fn device_os_test() {
  use conn <- with_db
  let assert Ok(rules) = db.rules(conn)
  let category = categories.categorizer(rules)
  let event = Event(shared.Window, now_ms(), 60_000, "Code", "a")
  let send = fn(os) {
    let assert Ok(Nil) =
      db.replace_events(
        conn,
        "laptop",
        shared.Upload(from_ms: 0, os:, events: [event]),
        category,
      )
    Nil
  }
  send("NixOS 25.05 (Warbler)")
  // an agent without OS keeps the known one
  send("")
  let assert Ok(systems) = db.device_systems(conn)
  assert dict.to_list(systems) == [#("laptop", "NixOS 25.05 (Warbler)")]

  let assert Ok(today) = db.filter(conn, "", 1, "")
  let assert Ok(report) = stats.load(conn, today)
  let assert [laptop] = report.devices
  assert string.starts_with(laptop.detail, "NixOS 25.05 (Warbler) · ")

  let assert Ok(Nil) = db.delete_device(conn, "laptop")
  let assert Ok(systems) = db.device_systems(conn)
  assert dict.is_empty(systems)
}

pub fn block_test() {
  use conn <- with_db
  let start = now_ms()
  upload(conn, "laptop", [
    Event(shared.Window, start, 600_000, "Code", "db.gleam"),
    Event(shared.Window, start + 600_000, 300_000, "Code", "web.gleam"),
    Event(shared.Window, start + 900_000, 300_000, "Unknown thing", "x"),
  ])
  let assert Ok(category) = category_of(conn, "Code") |> list.first
  // the block starts in the middle of the first event
  let block =
    db.Block("laptop", category.name, start + 300_000, start + 1_200_000)
  let assert Ok([code]) = db.block_apps(conn, block)
  assert code.name == "Code"
  assert code.ms == 600_000
  assert code.detail == "laptop"
  let assert Ok([first, second]) = db.block_titles(conn, block)
  assert first.ms == 300_000 && second.ms == 300_000
  let assert Ok([]) = db.block_apps(conn, db.Block(..block, device: "phone"))
}

pub fn invalid_date_is_today_test() {
  use conn <- with_db
  let assert Ok(today) = db.filter(conn, "", 1, "")
  let assert Ok(invalid) = db.filter(conn, "yesterday", 1, "")
  assert invalid.date == today.date
  let assert Ok(week) = db.filter(conn, "2026-03-31", 7, "")
  assert week.first_date == "2026-03-25"
  assert week.previous_date == "2026-03-24"
  assert week.next_date == "2026-04-07"
}
