import categories
import db
import gleam/list
import gleam/option.{None}
import rules
import shared.{Event}
import sqlight

fn with_events(run: fn(sqlight.Connection) -> a) -> a {
  use conn <- sqlight.with_connection(":memory:")
  let assert Ok(Nil) = db.migrate(conn)
  let assert Ok(filter) = db.filter(conn, "", 1, "")
  let start = filter.since_ms + 3_600_000
  let assert Ok(Nil) =
    db.replace_events(
      conn,
      "laptop",
      shared.Upload(from_ms: 0, os: "", app_types: [], events: [
        Event(shared.Window, start, 600_000, "Code", "db.gleam", None),
        Event(shared.Window, start + 600_000, 300_000, "Dropbox", "Files", None),
        Event(
          shared.Web,
          start + 600_000,
          300_000,
          "dropbox.com",
          "Files",
          None,
        ),
      ]),
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

pub fn preview_test() {
  use conn <- with_events
  let assert Ok(rule) = rules.parse(0, "Sync", ["dropbox"], True, [])
  let assert Ok(Ok(preview)) = rules.preview(conn, rule)
  // the window, with the tab's website
  assert preview.screen_ms == 300_000
  assert list.map(preview.apps, fn(app) { app.name }) == ["Dropbox"]
  let assert Ok(Ok(none)) =
    rules.preview(conn, categories.Rule(..rule, devices: ["phone"]))
  assert none.apps == []
}

pub fn overview_test() {
  use conn <- with_events
  let assert Ok(overview) = rules.overview(conn)
  let assert Ok(programming) =
    list.find(overview.categories, fn(entry) {
      entry.category.name == "Work > Programming"
    })
  assert programming.ms == 600_000
  assert programming.category.rating == categories.Productive
  let assert [code] = programming.items
  assert code.name == "Code" && code.source == categories.Known
  assert overview.devices == ["laptop"]
  // the window showed dropbox.com, which is unknown
  let assert [dropbox] = overview.unsorted
  assert dropbox.name == "dropbox.com" && dropbox.ms == 300_000
}

pub fn assign_test() {
  use conn <- with_events
  let assert Ok(Nil) = db.save_category(conn, "Storage", categories.Neutral)
  let assert Ok(Nil) = db.assign(conn, "Dropbox.com", "Storage")
  let assert Ok(Nil) = db.recategorize(conn)
  let assert Ok(overview) = rules.overview(conn)
  assert overview.unsorted == []
  let assert Ok(storage) =
    list.find(overview.categories, fn(e) { e.category.name == "Storage" })
  let assert [item] = storage.items
  assert item.source == categories.Assigned

  // renamed, it stays assigned
  let assert Ok(Nil) = db.rename_category(conn, "Storage", "Cloud")
  let assert Ok(Nil) = db.recategorize(conn)
  let assert Ok(overview) = rules.overview(conn)
  let assert Ok(cloud) =
    list.find(overview.categories, fn(e) { e.category.name == "Cloud" })
  assert cloud.ms == 300_000

  // deleted, back to unsorted
  let assert Ok(Nil) = db.delete_category(conn, "Cloud")
  let assert Ok(Nil) = db.recategorize(conn)
  let assert Ok(overview) = rules.overview(conn)
  let assert [_] = overview.unsorted
}
