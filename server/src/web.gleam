import categories
import dashboard
import db
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/string
import gleam/uri
import shared
import sqlight
import stats
import wisp

pub type Context {
  Context(db: sqlight.Connection, token: String)
}

pub fn handle_request(req: wisp.Request, ctx: Context) -> wisp.Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- require_token(req, ctx.token)
  case req.method, wisp.path_segments(req) {
    http.Get, [] -> dashboard(req, ctx)
    http.Get, ["categories"] -> categories_page(req, ctx)
    http.Post, ["categories"] -> save_category(req, ctx)
    http.Post, ["categories", "defaults"] -> add_defaults(req, ctx)
    http.Post, ["categories", id, "delete"] -> delete_category(req, ctx, id)
    http.Post, ["devices", device, "delete"] ->
      delete_device(req, ctx, decode_segment(device))
    http.Get, ["api", "stats"] -> stats_json(req, ctx)
    http.Get, ["api", "devices", device, "cursor"] ->
      cursor(ctx, decode_segment(device))
    http.Post, ["api", "devices", device, "events"] ->
      ingest(req, ctx, decode_segment(device))
    _, _ -> wisp.not_found()
  }
}

/// Path segments arrive percent-encoded, "Pixel%2010" is the device "Pixel 10".
fn decode_segment(segment: String) -> String {
  uri.percent_decode(segment) |> result.unwrap(segment)
}

/// Agents send `Authorization: Bearer <token>`, browsers get a basic auth
/// prompt where the password is the token and the user name is ignored.
fn require_token(
  req: wisp.Request,
  token: String,
  next: fn() -> wisp.Response,
) -> wisp.Response {
  let given = case request.get_header(req, "authorization") {
    Ok("Bearer " <> given) -> Ok(given)
    Ok("Basic " <> encoded) ->
      bit_array.base64_decode(encoded)
      |> result.try(bit_array.to_string)
      |> result.try(string.split_once(_, ":"))
      |> result.map(fn(pair) { pair.1 })
    _ -> Error(Nil)
  }
  case given {
    Ok(given) ->
      case crypto.secure_compare(<<given:utf8>>, <<token:utf8>>) {
        True -> next()
        False -> unauthorized()
      }
    Error(Nil) -> unauthorized()
  }
}

fn unauthorized() -> wisp.Response {
  wisp.response(401)
  |> wisp.set_header("www-authenticate", "Basic realm=\"wellbeing\"")
}

fn cursor(ctx: Context, device: String) -> wisp.Response {
  case db.cursor(ctx.db, device) {
    Ok(ms) ->
      json.object([#("cursor_ms", json.int(ms))])
      |> json.to_string
      |> wisp.json_response(200)
    Error(err) -> db_error(err)
  }
}

fn ingest(req: wisp.Request, ctx: Context, device: String) -> wisp.Response {
  // the first sync of a device sends 30 days at once
  let req = wisp.set_max_body_size(req, 100_000_000)
  use body <- wisp.require_json(req)
  case decode.run(body, shared.upload_decoder()) {
    Error(_) -> wisp.unprocessable_content()
    Ok(upload) -> {
      let written = {
        use rules <- result.try(db.rules(ctx.db))
        let category = categories.categorizer(rules)
        db.replace_events(ctx.db, device, upload, category)
      }
      case written {
        Ok(Nil) -> wisp.no_content()
        Error(err) -> db_error(err)
      }
    }
  }
}

/// The report for the query `?date=2026-10-26&days=7&device=laptop`: the 7
/// days up to that date of that device. Without them it is today on all
/// devices.
fn report(
  req: wisp.Request,
  ctx: Context,
) -> Result(stats.Report, sqlight.Error) {
  let query = wisp.get_query(req)
  let days =
    list.key_find(query, "days")
    |> result.try(int.parse)
    |> result.unwrap(1)
    |> int.clamp(1, 366)
  let date = list.key_find(query, "date") |> result.unwrap("")
  let device = list.key_find(query, "device") |> result.unwrap("")
  use filter <- result.try(db.filter(ctx.db, date, days, device))
  stats.load(ctx.db, filter)
}

fn dashboard(req: wisp.Request, ctx: Context) -> wisp.Response {
  case report(req, ctx) {
    Ok(report) -> wisp.html_response(dashboard.page(report), 200)
    Error(err) -> db_error(err)
  }
}

fn stats_json(req: wisp.Request, ctx: Context) -> wisp.Response {
  case report(req, ctx) {
    Ok(report) ->
      stats.to_json(report) |> json.to_string |> wisp.json_response(200)
    Error(err) -> db_error(err)
  }
}

fn categories_page(req: wisp.Request, ctx: Context) -> wisp.Response {
  let error = wisp.get_query(req) |> list.key_find("error") |> result.unwrap("")
  let page = {
    use rules <- result.try(db.rules(ctx.db))
    use devices <- result.try(db.device_names(ctx.db))
    use last_30_days <- result.try(db.filter(ctx.db, "", 30, ""))
    use apps <- result.try(db.uncategorized_apps(ctx.db, last_30_days))
    use titles <- result.map(db.uncategorized_titles(ctx.db, last_30_days))
    dashboard.categories_page(rules, devices, error, [
      #("Uncategorized apps and domains · 30 days", apps),
      #("Uncategorized window titles · 30 days", titles),
    ])
  }
  case page {
    Ok(html) -> wisp.html_response(html, 200)
    Error(err) -> db_error(err)
  }
}

fn save_category(req: wisp.Request, ctx: Context) -> wisp.Response {
  use req <- wisp.csrf_known_header_protection(req)
  use form <- wisp.require_form(req)
  let field = fn(name) { list.key_find(form.values, name) |> result.unwrap("") }
  let rule =
    categories.Rule(
      id: 0,
      name: categories.normalize_name(field("name")),
      regex: field("regex"),
      ignore_case: field("ignore_case") == "on",
      devices: list.filter(form.values, fn(v) { v.0 == "devices" })
        |> list.map(pair.second),
    )
  let valid = case rule.name, rule.regex {
    "", _ -> Error("The category needs a name")
    _, "" -> Error("The category needs a regex")
    _, _ -> categories.compile(rule.regex, rule.ignore_case)
  }
  case valid {
    Error(message) ->
      wisp.redirect("/categories?error=" <> uri.percent_encode(message))
    Ok(_) -> {
      let id = field("id") |> int.parse |> option.from_result
      rules_changed(ctx, db.save_rule(ctx.db, id, rule))
    }
  }
}

fn delete_device(
  req: wisp.Request,
  ctx: Context,
  device: String,
) -> wisp.Response {
  use _req <- wisp.csrf_known_header_protection(req)
  case db.delete_device(ctx.db, device) {
    Ok(Nil) -> wisp.redirect("/")
    Error(err) -> db_error(err)
  }
}

fn delete_category(
  req: wisp.Request,
  ctx: Context,
  id: String,
) -> wisp.Response {
  use _req <- wisp.csrf_known_header_protection(req)
  case int.parse(id) {
    Ok(id) -> rules_changed(ctx, db.delete_rule(ctx.db, id))
    Error(Nil) -> wisp.not_found()
  }
}

fn add_defaults(req: wisp.Request, ctx: Context) -> wisp.Response {
  use _req <- wisp.csrf_known_header_protection(req)
  rules_changed(ctx, db.add_rules(ctx.db, categories.defaults))
}

/// Stored events are put into the changed categories right away.
fn rules_changed(
  ctx: Context,
  changed: Result(Nil, sqlight.Error),
) -> wisp.Response {
  let done = {
    use _ <- result.try(changed)
    use rules <- result.try(db.rules(ctx.db))
    db.recategorize(ctx.db, categories.categorizer(rules))
  }
  case done {
    Ok(Nil) -> wisp.redirect("/categories")
    Error(err) -> db_error(err)
  }
}

fn db_error(err: sqlight.Error) -> wisp.Response {
  wisp.log_error(err.message)
  wisp.internal_server_error()
}
