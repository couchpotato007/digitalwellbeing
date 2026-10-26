import categories.{Rule}
import db
import gleam/list
import gleam/option.{None, Some}
import shared.{Event}
import sqlight

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
      shared.Upload(from_ms: 0, events:),
      categories.categorizer(rules),
    )
  Nil
}

fn category_of(conn, app) {
  let assert Ok(filter) = db.filter(conn, 365, "")
  let assert Ok(apps) = db.apps(conn, filter)
  let assert Ok(categories) = db.categories(conn, filter)
  let assert Ok(_) = list.find(apps, fn(usage) { usage.name == app })
  categories
}

fn now_ms() {
  let assert Ok(filter) = with_db(db.filter(_, 1, ""))
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
  let assert Ok(today) = db.filter(conn, 1, "")
  let assert Ok(timeline) = db.timeline(conn, today)
  assert list.length(timeline) == 24
  // both devices at once count once
  assert list.fold(timeline, 0, fn(sum, hour) { sum + hour.ms }) == 90_000

  let assert Ok(week) = db.filter(conn, 7, "laptop")
  let assert Ok(days) = db.timeline(conn, week)
  assert list.length(days) == 7
  assert list.fold(days, 0, fn(sum, day) { sum + day.ms }) == 60_000

  let assert Ok([code]) = db.apps(conn, today)
  assert code.detail == "desktop, laptop" || code.detail == "laptop, desktop"
  let assert Ok([_]) = db.domains(conn, today)
  let assert Ok([_, _]) = db.titles(conn, today)
  let assert Ok([_, _]) = db.devices(conn, today)
  let assert Ok([_]) = db.uncategorized_apps(conn, today)
  let assert Ok([]) = db.uncategorized_titles(conn, today)
  let assert Ok(["desktop", "laptop"]) = db.device_names(conn)
}
