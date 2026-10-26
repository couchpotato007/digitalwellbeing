//// Runs on every device next to ActivityWatch. Every few minutes it asks the
//// server how far it already has this device's data, queries ActivityWatch
//// for everything since then and uploads it.

import envoy
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import gleam/uri
import shared.{type Event, Event}

type Config {
  Config(
    server: String,
    token: String,
    device: String,
    activitywatch: String,
    interval_seconds: Int,
  )
}

/// How far back to go when the server has nothing for this device yet.
const first_sync_days = 30

/// How much of the already synced time is synced again.
const resync_ms = 600_000

pub fn main() -> Nil {
  case load_config() {
    Ok(cfg) -> {
      io.println("Syncing " <> cfg.device <> " to " <> cfg.server)
      loop(cfg)
    }
    Error(err) -> {
      io.println_error(err)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

fn loop(cfg: Config) -> Nil {
  case sync(cfg) {
    Ok(count) -> io.println("Uploaded " <> int.to_string(count) <> " events")
    Error(err) -> io.println_error("Sync failed: " <> err)
  }
  // 0 syncs once, for running from cron or a systemd timer
  case cfg.interval_seconds {
    0 -> Nil
    seconds -> {
      process.sleep(seconds * 1000)
      loop(cfg)
    }
  }
}

fn load_config() -> Result(Config, String) {
  let env = fn(name) {
    envoy.get(name) |> result.replace_error("Missing env var: " <> name)
  }
  use server <- result.try(env("SERVER_URL"))
  use token <- result.try(env("TOKEN"))
  use device <- result.try(env("DEVICE"))
  let activitywatch =
    envoy.get("ACTIVITYWATCH_URL") |> result.unwrap("http://localhost:5600")
  let interval_seconds =
    envoy.get("INTERVAL_SECONDS")
    |> result.try(int.parse)
    |> result.unwrap(300)
  Ok(Config(server:, token:, device:, activitywatch:, interval_seconds:))
}

fn sync(cfg: Config) -> Result(Int, String) {
  let device_url =
    cfg.server <> "/api/devices/" <> uri.percent_encode(cfg.device)
  use cursor <- result.try(
    get(device_url <> "/cursor", cfg.token, {
      use ms <- decode.field("cursor_ms", decode.int)
      decode.success(ms)
    }),
  )
  let now = timestamp.system_time()
  // ActivityWatch still changes the last minutes afterwards, e.g. when it
  // notices that you went AFK, so those are synced again.
  let from_ms = case cursor {
    0 -> to_ms(timestamp.add(now, duration.hours(-24 * first_sync_days)))
    ms -> ms - resync_ms
  }
  use events <- result.try(query_activitywatch(
    cfg.activitywatch,
    from_unix_ms(from_ms),
    now,
  ))
  let body =
    shared.upload_to_json(shared.Upload(from_ms:, events:)) |> json.to_string
  use _ <- result.map(send(http.Post, device_url <> "/events", cfg.token, body))
  list.length(events)
}

/// Matches the app names of browsers, so tabs only count while the browser
/// window is active.
const browsers =
  "(?i)firefox|zen|chrom|brave|edge|vivaldi|opera|safari|browser|librewolf|floorp|waterfox"

/// Window and browser tab events from ActivityWatch, without the time the
/// user was away (AFK). The server puts them into categories.
fn query_activitywatch(
  base: String,
  from: Timestamp,
  to: Timestamp,
) -> Result(List(Event), String) {
  use buckets <- result.try(get(
    base <> "/api/0/buckets/",
    "",
    decode.dict(decode.string, decode.at(["type"], decode.string)),
  ))
  // aw-sync mirrors other hosts' buckets, those are synced by their own agent
  let find = fn(kind) {
    dict.to_list(buckets)
    |> list.filter(fn(bucket) {
      bucket.1 == kind && !string.contains(bucket.0, "synced-from")
    })
    |> list.map(fn(bucket) { "query_bucket(" <> quote(bucket.0) <> ")" })
  }
  use window <- result.try(
    list.first(find("currentwindow"))
    |> result.replace_error("ActivityWatch has no window/app bucket"),
  )
  let active = case find("afkstatus") {
    [afk, ..] ->
      "window = filter_period_intersect(flood("
      <> window
      <> "), filter_keyvals(flood("
      <> afk
      <> "), \"status\", [\"not-afk\"]));"
    [] -> "window = flood(" <> window <> ");"
  }
  let run = fn(kind, query) {
    let body =
      json.object([
        #("timeperiods", json.array([iso(from) <> "/" <> iso(to)], json.string)),
        #("query", json.array([active <> query], json.string)),
      ])
      |> json.to_string
    use response <- result.try(send(
      http.Post,
      base <> "/api/0/query/",
      "",
      body,
    ))
    json.parse(response, decode.list(decode.list(aw_event_decoder(kind))))
    |> result.map(list.flatten)
    |> result.map_error(fn(err) {
      "Unexpected ActivityWatch response: " <> string.inspect(err)
    })
  }
  use windows <- result.try(run(shared.Window, "RETURN = window;"))
  use tabs <- result.map(
    list.try_map(find("web.tab.current"), fn(web) {
      run(
        shared.Web,
        "browser = filter_keyvals_regex(window, \"app\", "
          <> quote(browsers)
          <> "); RETURN = filter_period_intersect(flood("
          <> web
          <> "), browser);",
      )
    }),
  )
  list.flatten([windows, ..tabs])
  |> list.filter(fn(e) { e.duration_ms > 0 })
}

fn aw_event_decoder(kind: shared.Kind) -> decode.Decoder(Event) {
  use start <- decode.field("timestamp", decode.string)
  use seconds <- decode.field(
    "duration",
    decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)]),
  )
  use app <- decode.then(case kind {
    shared.Window ->
      decode.optionally_at(["data", "app"], "unknown", decode.string)
    shared.Web ->
      decode.optionally_at(["data", "url"], "", decode.string)
      |> decode.map(domain)
  })
  use title <- decode.then(decode.optionally_at(
    ["data", "title"],
    "",
    decode.string,
  ))
  case timestamp.parse_rfc3339(start) {
    Ok(start) ->
      decode.success(Event(
        kind:,
        start_ms: to_ms(start),
        duration_ms: float.round(seconds *. 1000.0),
        app:,
        title:,
      ))
    Error(Nil) ->
      decode.failure(Event(kind, 0, 0, "", ""), "RFC 3339 timestamp")
  }
}

/// "https://www.example.org/path" -> "example.org"
fn domain(url: String) -> String {
  case uri.parse(url) {
    Ok(uri.Uri(host: Some("www." <> host), ..))
    | Ok(uri.Uri(host: Some(host), ..)) -> host
    _ -> url
  }
}

/// A string literal for the ActivityWatch query language, which takes JSON.
fn quote(s: String) -> String {
  json.to_string(json.string(s))
}

fn get(
  url: String,
  token: String,
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  use body <- result.try(send(http.Get, url, token, ""))
  json.parse(body, decoder)
  |> result.map_error(fn(err) { url <> ": " <> string.inspect(err) })
}

fn send(
  method: http.Method,
  url: String,
  token: String,
  body: String,
) -> Result(String, String) {
  use req <- result.try(
    request.to(url) |> result.replace_error("Invalid URL: " <> url),
  )
  let req =
    req
    |> request.set_method(method)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("authorization", "Bearer " <> token)
    |> request.set_body(body)
  case httpc.send(req) {
    Ok(res) if res.status < 300 -> Ok(res.body)
    Ok(res) -> Error(url <> ": HTTP " <> int.to_string(res.status))
    Error(err) -> Error(url <> ": " <> string.inspect(err))
  }
}

fn iso(t: Timestamp) -> String {
  timestamp.to_rfc3339(t, calendar.utc_offset)
}

fn to_ms(t: Timestamp) -> Int {
  let #(seconds, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(t)
  seconds * 1000 + nanoseconds / 1_000_000
}

fn from_unix_ms(ms: Int) -> Timestamp {
  timestamp.from_unix_seconds_and_nanoseconds(ms / 1000, ms % 1000 * 1_000_000)
}
