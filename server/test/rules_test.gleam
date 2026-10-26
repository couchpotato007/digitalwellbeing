import categories.{Rule}
import db
import gleam/list
import gleam/string
import rules
import shared.{Event}
import sqlight

fn with_events(run: fn(sqlight.Connection) -> a) -> a {
  use conn <- sqlight.with_connection(":memory:")
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(filter) = db.filter(conn, "", 1, "")
  let start = filter.since_ms + 3_600_000
  let assert Ok(rules) = db.rules(conn)
  let assert Ok(Nil) =
    db.replace_events(
      conn,
      "laptop",
      shared.Upload(from_ms: 0, os: "", events: [
        Event(shared.Window, start, 600_000, "Code", "db.gleam"),
        Event(shared.Window, start + 600_000, 300_000, "Dropbox", "Files"),
        Event(shared.Web, start + 600_000, 300_000, "dropbox.com", "Files"),
      ]),
      categories.categorizer(rules),
    )
  run(conn)
}

pub fn parse_test() {
  let assert Ok(rule) =
    rules.parse(0, " Work>Sync ", ["dropbox", " ", "box\\.com"], False, [""])
  assert rule.name == "Work > Sync"
  assert rule.regex == "dropbox|box\\.com"
  assert rule.devices == []
  let assert Error(_) = rules.parse(0, "", ["x"], False, [])
  let assert Error(_) = rules.parse(0, "Work", [" "], False, [])
  let assert Error(_) = rules.parse(0, "Work", ["("], False, [])
}

pub fn add_pattern_test() {
  let rule = Rule(1, "Work", "code", True, [])
  let added = rules.add_pattern(rule, "x.com")
  assert added.regex == "code|x\\.com"
  // already there
  assert rules.add_pattern(added, "x.com") == added
}

pub fn preview_test() {
  use conn <- with_events
  let assert Ok(rule) = rules.parse(0, "Sync", ["dropbox"], True, [])
  let assert Ok(Ok(preview)) = rules.preview(conn, rule)
  // only the window counts as screen time, the tab is part of it
  assert preview.screen_ms == 300_000
  assert list.map(preview.apps, fn(app) { app.name })
    |> list.sort(string.compare)
    == ["Dropbox", "dropbox.com"]
  let assert Ok(Ok(none)) =
    rules.preview(conn, Rule(..rule, devices: ["phone"]))
  assert none.apps == []
}

pub fn overview_test() {
  use conn <- with_events
  let assert Ok(overview) = rules.overview(conn)
  let assert Ok(#(_, ms)) =
    list.find(overview.rules, fn(entry) {
      { entry.0 }.name == "Work > Programming"
    })
  assert ms == 600_000
  assert overview.devices == ["laptop"]
  let assert [_, _] = overview.uncategorized_apps
}
