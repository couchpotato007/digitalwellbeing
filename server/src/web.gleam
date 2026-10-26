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
import gleam/result
import gleam/string
import shared
import sqlight
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
    http.Get, ["api", "devices", device, "cursor"] -> cursor(ctx, device)
    http.Post, ["api", "devices", device, "events"] -> ingest(req, ctx, device)
    _, _ -> wisp.not_found()
  }
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
    Ok(upload) ->
      case db.replace_events(ctx.db, device, upload) {
        Ok(Nil) -> wisp.no_content()
        Error(err) -> db_error(err)
      }
  }
}

fn dashboard(req: wisp.Request, ctx: Context) -> wisp.Response {
  let query = wisp.get_query(req)
  let days =
    list.key_find(query, "days")
    |> result.try(int.parse)
    |> result.unwrap(1)
    |> int.clamp(1, 365)
  let filter =
    db.Filter(
      days:,
      device: list.key_find(query, "device") |> result.unwrap(""),
    )
  let data = {
    use devices <- result.try(db.devices(ctx.db, days))
    use timeline <- result.try(db.timeline(ctx.db, filter))
    use categories <- result.try(db.categories(ctx.db, filter))
    use apps <- result.try(db.apps(ctx.db, filter))
    use titles <- result.try(db.titles(ctx.db, filter))
    use domains <- result.map(db.domains(ctx.db, filter))
    let sections = [
      #("Categories", categories),
      #("Apps", apps),
      #("Window titles", titles),
      #("Browser domains", domains),
    ]
    let sections = case filter.device {
      "" -> [#("Devices · last active", devices), ..sections]
      _ -> sections
    }
    dashboard.page(filter, devices, timeline, sections)
  }
  case data {
    Ok(html) -> wisp.html_response(html, 200)
    Error(err) -> db_error(err)
  }
}

fn db_error(err: sqlight.Error) -> wisp.Response {
  wisp.log_error(err.message)
  wisp.internal_server_error()
}
