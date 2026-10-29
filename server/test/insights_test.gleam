import db
import gleam/list
import gleam/option.{None}
import insights
import shared.{Event}
import sqlight
import stats

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

fn event(kind, start, length, app) {
  Event(kind, start, length, app, app, None)
}

fn load(conn, date, days, device) {
  let assert Ok(filter) = db.filter(conn, date, days, device)
  let assert Ok(report) = stats.load(conn, filter)
  let assert Ok(insights) = insights.load(conn, filter, report.days)
  #(report, insights)
}

fn today_start(conn) {
  let assert Ok(today) = db.filter(conn, "", 1, "")
  today.since_ms
}

pub fn hours_are_split_test() {
  use conn <- with_db
  let start = today_start(conn)
  // 10:30 to 12:15
  upload(conn, "laptop", [
    event(shared.Window, start + 10 * hour + 30 * minute, 105 * minute, "Code"),
  ])
  let #(report, _) = load(conn, "", 1, "")
  let assert Ok(ten) = list.find(report.timeline, fn(u) { u.name == "10" })
  let assert Ok(eleven) = list.find(report.timeline, fn(u) { u.name == "11" })
  let assert Ok(twelve) = list.find(report.timeline, fn(u) { u.name == "12" })
  assert ten.ms == 30 * minute
  assert eleven.ms == 60 * minute
  assert twelve.ms == 15 * minute
}

pub fn midnight_is_split_test() {
  use conn <- with_db
  let start = today_start(conn)
  // 23:00 yesterday to 01:00 today
  upload(conn, "laptop", [event(shared.Window, start - hour, 2 * hour, "Code")])
  let #(report, _) = load(conn, "", 2, "")
  let assert [yesterday, today] = report.timeline
  assert yesterday.ms == hour
  assert today.ms == hour
  assert report.total_ms == 2 * hour
  // a day only has its part
  let #(report, _) = load(conn, "", 1, "")
  assert report.total_ms == hour
  assert report.first_active == "00:00"
}

pub fn phone_habits_test() {
  use conn <- with_db
  let start = today_start(conn) + 8 * hour
  upload(conn, "phone", [
    event(shared.Notification, start - 30_000, 0, "Signal"),
    event(shared.Screen, start - 1000, 5 * minute, ""),
    event(shared.Unlock, start, 0, ""),
    event(shared.Window, start, 4 * minute, "Signal"),
    // a glance at the clock
    event(shared.Screen, start + hour, 10_000, ""),
    event(shared.Screen, start + 2 * hour, 3 * minute, ""),
    event(shared.Unlock, start + 2 * hour, 0, ""),
    event(shared.Window, start + 2 * hour + 1000, 2 * minute, "Firefox"),
    event(shared.Notification, start + 3 * hour, 0, "Signal"),
    event(shared.Audio, start, 30 * minute, "Spotify"),
    event(shared.Audio, start + 10 * minute, 30 * minute, "Spotify"),
  ])
  let #(report, i) = load(conn, "", 1, "")
  assert report.total_ms == 6 * minute
  assert i.pickups == 2
  assert i.first_pickup == "08:00"
  let assert Ok(eight) = list.drop(i.pickup_hours, 8) |> list.first
  assert eight == 1
  assert i.notification_pickups == 1
  assert i.notifications == 2
  assert i.notification_apps == [insights.Count("Signal", 2)]
  assert i.pickup_apps
    == [insights.Count("Firefox", 1), insights.Count("Signal", 1)]
  assert i.screen_ons == 3
  assert i.short_screen_ons == 1
  assert i.median_screen_on_ms == 3 * minute
  // the two overlap
  assert i.audio_ms == 40 * minute
}

pub fn focus_test() {
  use conn <- with_db
  let start = today_start(conn) + 9 * hour
  upload(conn, "laptop", [
    event(shared.Window, start, 20 * minute, "Code"),
    // a short look at chat doesn't end it
    event(shared.Window, start + 20 * minute, 30_000, "Signal"),
    event(shared.Window, start + 20 * minute + 30_000, 15 * minute, "Code"),
    event(shared.Window, start + 2 * hour, 10 * minute, "Code"),
  ])
  let #(_, i) = load(conn, "", 1, "")
  assert i.long_stretches == 1
  assert i.long_stretch_ms == 35 * minute + 30_000
  // Code is productive, Signal (chat) neutral
  assert i.productive_ms == 45 * minute
  assert i.neutral_ms == 30_000
  assert i.distracting_ms == 0
  assert i.longest_stretch.name == "Work"
  assert i.longest_stretch.detail == "09:00–09:35"
  assert i.app_switches == 2
}

pub fn only_productive_stretches_test() {
  use conn <- with_db
  let start = today_start(conn) + 20 * hour
  upload(conn, "laptop", [event(shared.Window, start, hour, "mpv")])
  let #(_, i) = load(conn, "", 1, "")
  // an hour of video is no focus
  assert i.long_stretches == 0
  assert i.distracting_ms == hour
}

pub fn phone_during_computer_test() {
  use conn <- with_db
  let start = today_start(conn) + 9 * hour
  upload(conn, "laptop", [event(shared.Window, start, hour, "Code")])
  upload(conn, "phone", [
    event(shared.Unlock, start + 10 * minute, 0, ""),
    event(shared.Window, start + 10 * minute, 5 * minute, "Signal"),
    event(shared.Unlock, start + 3 * hour, 0, ""),
    event(shared.Window, start + 3 * hour, 5 * minute, "Signal"),
  ])
  let #(_, i) = load(conn, "", 1, "")
  assert i.phone_during_computer_ms == 5 * minute
  assert i.pickups_during_computer == 1
  // not for one device
  let #(_, i) = load(conn, "", 1, "phone")
  assert i.phone_during_computer_ms == 0
}

pub fn usual_test() {
  use conn <- with_db
  let assert Ok(today) = db.filter(conn, "", 1, "")
  let yesterday = today.previous_date
  let start = today.since_ms - 24 * hour + 9 * hour
  let day = 24 * hour
  // an hour on the same weekday for 8 weeks, then 4 hours
  let weeks =
    list.map([1, 2, 3, 4, 5, 6, 7, 8], fn(week) {
      event(shared.Window, start - week * 7 * day, hour, "Code")
    })
  upload(conn, "laptop", [
    event(shared.Window, start, 4 * hour, "Code"),
    ..weeks
  ])
  let #(_, i) = load(conn, yesterday, 1, "")
  assert !i.until_now
  assert i.total.usual_ms == hour
  assert i.total.periods == 8
  assert i.total.ms == 4 * hour
  // 3 hours more, at least 10 minutes and a tenth of usual as the scale
  assert i.total.score == 18.0
  let assert [work] = i.categories
  assert work.name == "Work"
  assert list.length(i.week_hours) == 7
  let assert Ok(sunday) = list.first(i.week_hours)
  assert list.length(sunday) == 24
}

/// Today is compared with earlier days up to the same time.
pub fn usual_until_now_test() {
  use conn <- with_db
  let assert Ok(today) = db.filter(conn, "", 1, "")
  let day = 24 * hour
  let weeks =
    list.flat_map([1, 2, 3], fn(week) {
      let start = today.since_ms - week * 7 * day
      [
        event(shared.Window, start, 30 * minute, "Code"),
        event(shared.Window, start + 23 * hour, 50 * minute, "Code"),
      ]
    })
  upload(conn, "laptop", [
    event(shared.Window, today.since_ms, 30 * minute, "Code"),
    ..weeks
  ])
  let #(_, i) = load(conn, "", 1, "")
  assert i.until_now
  let elapsed = today.now_ms - today.since_ms
  // between 01:00 and 23:00 only the first half hour of each day has passed
  case elapsed > hour && elapsed < 23 * hour {
    True -> {
      assert i.total.usual_ms == 30 * minute
      assert i.total.score == 0.0
    }
    False -> Nil
  }
}

pub fn no_history_test() {
  use conn <- with_db
  let start = today_start(conn) + 9 * hour
  upload(conn, "laptop", [event(shared.Window, start, hour, "Code")])
  let #(_, i) = load(conn, "", 7, "")
  // nothing before, so nothing to compare with
  assert i.total.periods == 0
  let assert Ok(last) = list.last(i.trend)
  assert last.ms == hour
}

pub fn median_test() {
  assert insights.median([]) == 0
  assert insights.median([3, 1, 2]) == 2
  assert insights.median([4, 1, 3, 2]) == 2
}
