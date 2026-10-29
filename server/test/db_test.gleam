import categories.{Rule}
import db
import gleam/dict
import gleam/dynamic/decode
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
  let assert Ok(Nil) =
    db.replace_events(
      conn,
      device,
      shared.Upload(from_ms: 0, os: "", events:, app_types: []),
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

pub fn migrate_adds_builtins_once_test() {
  use conn <- with_db
  let assert Ok(defined) = db.category_list(conn)
  assert list.length(defined) == list.length(categories.builtins)
  let assert Ok(rules) = db.rules(conn)
  assert rules == []

  let assert Ok(Nil) = db.delete_category(conn, "Shopping")
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(defined) = db.category_list(conn)
  assert list.length(defined) == list.length(categories.builtins) - 1

  let assert Ok(Nil) = db.add_builtin_categories(conn)
  let assert Ok(defined) = db.category_list(conn)
  assert list.length(defined) == list.length(categories.builtins)
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
    Event(shared.Window, start, 600_000, "Code", "db.gleam", None),
    Event(shared.Window, start + 600_000, 300_000, "firefox", "Some page", None),
    Event(
      shared.Web,
      start + 600_000,
      300_000,
      "example.org",
      "Some page",
      None,
    ),
  ])
  let assert Ok(cursor) = db.cursor(conn, "laptop")
  assert cursor == start + 900_000

  // an unknown website in a known browser
  assert category_of(conn, "Code")
    == [
      db.Usage("Work > Programming", "", 600_000),
      db.Usage("Browsing", "", 300_000),
    ]

  let assert Ok(Nil) = db.assign(conn, "example.org", "Work > Office")
  let assert Ok(Nil) = db.recategorize(conn)
  assert category_of(conn, "firefox")
    == [
      db.Usage("Work > Programming", "", 600_000),
      db.Usage("Work > Office", "", 300_000),
    ]
}

pub fn dashboard_queries_test() {
  use conn <- with_db
  let start = now_ms()
  upload(conn, "laptop", [
    Event(shared.Window, start, 60_000, "Code", "a", None),
  ])
  upload(conn, "desktop", [
    Event(shared.Window, start + 30_000, 60_000, "Code", "b", None),
    Event(shared.Web, start + 30_000, 60_000, "example.org", "c", None),
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
  let event = Event(shared.Window, now_ms(), 60_000, "Code", "a", None)
  let send = fn(os) {
    let assert Ok(Nil) =
      db.replace_events(
        conn,
        "laptop",
        shared.Upload(from_ms: 0, os:, events: [event], app_types: []),
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
    Event(shared.Window, start, 600_000, "Code", "db.gleam", None),
    Event(shared.Window, start + 600_000, 300_000, "Code", "web.gleam", None),
    Event(shared.Window, start + 900_000, 300_000, "Unknown thing", "x", None),
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

pub fn migrate_from_version_1_test() {
  use conn <- sqlight.with_connection(":memory:")
  let assert Ok(Nil) =
    sqlight.exec(
      "CREATE TABLE events (
        device TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('window', 'web')),
        start_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL CHECK (duration_ms >= 0),
        app TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        PRIMARY KEY (device, kind, start_ms)
      ) WITHOUT ROWID;
      CREATE INDEX events_start ON events(start_ms);
      CREATE INDEX events_app ON events(device, app, title);
      CREATE TABLE devices (name TEXT PRIMARY KEY, os TEXT NOT NULL) WITHOUT ROWID;
      CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, regex TEXT NOT NULL,
        ignore_case BOOLEAN NOT NULL, devices TEXT NOT NULL);
      INSERT INTO categories VALUES (1, 'Shopping', 'amazon|ebay|etsy|aliexpress|\\btemu\\b', 1, '[]');
      INSERT INTO categories VALUES (2, 'Studying', 'anki', 1, '[]');
      INSERT INTO events VALUES ('laptop', 'window', 1000, 60000, 'Code', 'a', 'Work');
      INSERT INTO events VALUES ('laptop', 'window', 100000, 60000, 'firefox', 'b', 'Work');
      INSERT INTO events VALUES ('laptop', 'web', 120000, 10000, 'github.com', 'b', 'Work');
      INSERT INTO devices VALUES ('laptop', 'NixOS');
      PRAGMA user_version = 1;",
      conn,
    )
  let assert Ok(Nil) = db.migrate(conn)
  // the unchanged old default went, the catalog does it now, the own rule
  // stays and its category exists
  let assert Ok([studying]) = db.rules(conn)
  assert studying.name == "Studying"
  let assert Ok(defined) = db.category_list(conn)
  assert list.length(defined) == list.length(categories.builtins) + 1
  // the browser window was split by its tab
  let assert Ok(rows) =
    sqlight.query(
      "SELECT start_ms, site, category FROM events WHERE kind = 'window' AND app = 'firefox' ORDER BY start_ms",
      on: conn,
      with: [],
      expecting: {
        use start <- decode.field(0, decode.int)
        use site <- decode.field(1, decode.string)
        use category <- decode.field(2, decode.string)
        decode.success(#(start, site, category))
      },
    )
  assert rows
    == [
      #(100_000, "", "Browsing"),
      #(120_000, "github.com", "Work > Programming"),
      #(130_000, "", "Browsing"),
    ]
  let assert Ok(160_000) = db.cursor(conn, "laptop")
  let assert Ok(systems) = db.device_systems(conn)
  assert dict.to_list(systems) == [#("laptop", "NixOS")]
  // the new kinds fit
  upload(conn, "phone", [
    Event(shared.Unlock, now_ms(), 0, "", "", Some(60)),
  ])
  let assert Ok(["laptop", "phone"]) = db.device_names(conn)
  // and migrating again changes nothing
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(["laptop", "phone"]) = db.device_names(conn)
}

pub fn phone_kinds_are_not_screen_time_test() {
  use conn <- with_db
  let start = now_ms()
  upload(conn, "phone", [
    Event(
      shared.Window,
      start,
      60_000,
      "Signal",
      "org.thoughtcrime.securesms",
      Some(60),
    ),
    Event(shared.Screen, start - 5000, 70_000, "", "", Some(60)),
    Event(shared.Unlock, start - 1000, 0, "", "", Some(60)),
    Event(
      shared.Notification,
      start - 2000,
      0,
      "Signal",
      "org.thoughtcrime.securesms",
      Some(60),
    ),
    Event(
      shared.Audio,
      start,
      600_000,
      "Spotify",
      "com.spotify.music",
      Some(60),
    ),
  ])
  let assert Ok(today) = db.filter(conn, "", 1, "")
  let assert Ok(report) = stats.load(conn, today)
  assert report.total_ms == 60_000
  let assert Ok([signal]) = db.apps(conn, today)
  assert signal.name == "Signal"
  let assert Ok(uploads) = db.last_uploads(conn)
  let assert Ok(last) = dict.get(uploads, "phone")
  assert last > 0
}
