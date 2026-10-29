import categories
import dashboard
import db
import gleam/bit_array
import gleam/crypto
import gleam/dict
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
import insights
import rules
import shared
import sqlight
import stats
import timeline
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
    http.Post, ["categories", "save"] -> form_change(req, ctx, save_category)
    http.Post, ["categories", "delete"] ->
      form_change(req, ctx, delete_category)
    http.Post, ["categories", "assign"] -> form_change(req, ctx, assign)
    http.Post, ["categories", "builtins"] ->
      form_change(req, ctx, fn(ctx, _) {
        db.add_builtin_categories(ctx.db) |> result.map(Ok)
      })
    http.Get, ["rules", "new"] -> new_rule(req, ctx)
    http.Get, ["rules", id] -> edit_rule(ctx, id)
    http.Post, ["rules"] -> save_rule(req, ctx)
    http.Post, ["rules", id, "delete"] -> delete_rule(req, ctx, id)
    http.Get, ["api", "categories"] -> categories_json(ctx)
    http.Post, ["api", "categories", "save"] ->
      json_change(req, ctx, save_category)
    http.Post, ["api", "categories", "delete"] ->
      json_change(req, ctx, delete_category)
    http.Post, ["api", "categories", "assign"] -> json_change(req, ctx, assign)
    http.Post, ["api", "categories", "builtins"] ->
      api_changed(ctx, db.add_builtin_categories(ctx.db) |> result.map(Ok))
    http.Post, ["api", "rules"] -> save_rule_json(req, ctx)
    http.Post, ["api", "rules", "preview"] -> preview_json(req, ctx)
    http.Delete, ["api", "rules", id] -> delete_rule_json(ctx, id)
    http.Post, ["devices", device, "delete"] ->
      delete_device(req, ctx, decode_segment(device))
    http.Get, ["api", "stats"] -> stats_json(req, ctx)
    http.Get, ["api", "insights"] -> insights_json(req, ctx)
    http.Get, ["api", "timeline"] -> timeline_json(req, ctx)
    http.Get, ["api", "block"] -> block_json(req, ctx)
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
      case db.replace_events(ctx.db, device, upload) {
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
  let loaded = {
    use report <- result.try(report(req, ctx))
    use insights <- result.map(insights.load(ctx.db, report.filter, report.days))
    dashboard.page(report, insights)
  }
  case loaded {
    Ok(page) -> wisp.html_response(page, 200)
    Error(err) -> db_error(err)
  }
}

/// Screen time per app over time and the sessions, for the same query as
/// `/api/stats`.
fn timeline_json(req: wisp.Request, ctx: Context) -> wisp.Response {
  let loaded = {
    use report <- result.try(report(req, ctx))
    timeline.load(ctx.db, report.filter, report.days)
  }
  case loaded {
    Ok(timeline) ->
      timeline.to_json(timeline) |> json.to_string |> wisp.json_response(200)
    Error(err) -> db_error(err)
  }
}

/// The insights for the same query as `/api/stats`.
fn insights_json(req: wisp.Request, ctx: Context) -> wisp.Response {
  let loaded = {
    use report <- result.try(report(req, ctx))
    insights.load(ctx.db, report.filter, report.days)
  }
  case loaded {
    Ok(insights) ->
      insights.to_json(insights) |> json.to_string |> wisp.json_response(200)
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

/// What a block of the activity view was made of, for the query
/// `?device=laptop&category=Work&since_ms=…&until_ms=…`. Without `device` it
/// is all devices.
fn block_json(req: wisp.Request, ctx: Context) -> wisp.Response {
  let query = wisp.get_query(req)
  let field = fn(name) { list.key_find(query, name) |> result.unwrap("") }
  let block = {
    use since_ms <- result.try(int.parse(field("since_ms")))
    use until_ms <- result.map(int.parse(field("until_ms")))
    db.Block(field("device"), field("category"), since_ms, until_ms)
  }
  case block {
    Error(Nil) -> wisp.bad_request("since_ms and until_ms are needed")
    Ok(block) -> {
      let lists = {
        use apps <- result.try(db.block_apps(ctx.db, block))
        use titles <- result.map(db.block_titles(ctx.db, block))
        json.object([
          #("apps", json.array(apps, stats.usage_to_json)),
          #("titles", json.array(titles, stats.usage_to_json)),
        ])
      }
      case lists {
        Ok(body) -> json.to_string(body) |> wisp.json_response(200)
        Error(err) -> db_error(err)
      }
    }
  }
}

fn categories_page(req: wisp.Request, ctx: Context) -> wisp.Response {
  let query = wisp.get_query(req)
  let field = fn(name) { list.key_find(query, name) |> result.unwrap("") }
  case rules.overview(ctx.db) {
    Ok(overview) ->
      wisp.html_response(
        dashboard.categories_page(overview, field("open"), field("error")),
        200,
      )
    Error(err) -> db_error(err)
  }
}

/// A change to the categories from a form or JSON body's fields: Ok(Ok)
/// when done, Ok(Error(message)) for what was wrong with them.
type Change =
  fn(Context, fn(String) -> String) ->
    Result(Result(Nil, String), sqlight.Error)

/// `name`, `rating` and `old_name` (to rename, "" for a new one).
fn save_category(
  ctx: Context,
  field: fn(String) -> String,
) -> Result(Result(Nil, String), sqlight.Error) {
  let rating =
    categories.rating_from_string(field("rating"))
    |> result.unwrap(categories.Neutral)
  case rules.category_name(field("name")) {
    Error(message) -> Ok(Error(message))
    Ok(name) -> {
      use existing <- result.try(db.category_list(ctx.db))
      let taken = list.any(existing, fn(c) { c.name == name })
      case field("old_name") {
        old if old == name || old == "" -> {
          use _ <- result.map(db.save_category(ctx.db, name, rating))
          Ok(Nil)
        }
        _ if taken -> Ok(Error("There already is a category \"" <> name <> "\""))
        old -> {
          use _ <- result.try(db.rename_category(ctx.db, old, name))
          use _ <- result.map(db.save_category(ctx.db, name, rating))
          Ok(Nil)
        }
      }
    }
  }
}

/// `name`
fn delete_category(
  ctx: Context,
  field: fn(String) -> String,
) -> Result(Result(Nil, String), sqlight.Error) {
  db.delete_category(ctx.db, field("name")) |> result.map(Ok)
}

/// `app` (an app or website) into `category`, "" back to automatic.
fn assign(
  ctx: Context,
  field: fn(String) -> String,
) -> Result(Result(Nil, String), sqlight.Error) {
  case string.trim(field("app")) {
    "" -> Ok(Error("Which app?"))
    app -> db.assign(ctx.db, app, field("category")) |> result.map(Ok)
  }
}

/// Runs a change with a form's fields, stored events are put into the
/// changed categories right away. Back to the categories page, the category
/// `open` (a field of the form) open.
fn form_change(
  req: wisp.Request,
  ctx: Context,
  change: Change,
) -> wisp.Response {
  use req <- wisp.csrf_known_header_protection(req)
  use form <- wisp.require_form(req)
  let field = fn(name) { list.key_find(form.values, name) |> result.unwrap("") }
  let back = "/categories?open=" <> uri.percent_encode(field("open"))
  let done = {
    use changed <- result.try(change(ctx, field))
    case changed {
      Ok(Nil) -> db.recategorize(ctx.db) |> result.map(Ok)
      Error(message) -> Ok(Error(message))
    }
  }
  case done {
    Ok(Ok(Nil)) -> wisp.redirect(back)
    Ok(Error(message)) ->
      wisp.redirect(back <> "&error=" <> uri.percent_encode(message))
    Error(err) -> db_error(err)
  }
}

/// Runs a change with a JSON object's string fields.
fn json_change(
  req: wisp.Request,
  ctx: Context,
  change: Change,
) -> wisp.Response {
  use body <- wisp.require_json(req)
  case decode.run(body, decode.dict(decode.string, decode.string)) {
    Error(_) -> wisp.unprocessable_content()
    Ok(fields) ->
      api_changed(
        ctx,
        change(ctx, fn(name) { dict.get(fields, name) |> result.unwrap("") }),
      )
  }
}

/// Puts stored events into the changed categories, 204 when done, 422 with
/// `{"error"}` for a message.
fn api_changed(
  ctx: Context,
  changed: Result(Result(Nil, String), sqlight.Error),
) -> wisp.Response {
  let done = {
    use changed <- result.try(changed)
    case changed {
      Ok(Nil) -> db.recategorize(ctx.db) |> result.map(Ok)
      Error(message) -> Ok(Error(message))
    }
  }
  case done {
    Ok(Ok(Nil)) -> wisp.no_content()
    Ok(Error(message)) -> error_json(message)
    Error(err) -> db_error(err)
  }
}

/// `?category=` starts it for that category, `?pattern=` with that pattern.
fn new_rule(req: wisp.Request, ctx: Context) -> wisp.Response {
  let query = wisp.get_query(req)
  let field = fn(name) { list.key_find(query, name) |> result.unwrap("") }
  editor(
    ctx,
    categories.Rule(0, field("category"), field("pattern"), True, []),
    "",
    False,
  )
}

fn edit_rule(ctx: Context, id: String) -> wisp.Response {
  let rule = {
    use id <- result.try(int.parse(id) |> result.replace_error(Nil))
    use rules <- result.try(db.rules(ctx.db) |> result.replace_error(Nil))
    list.find(rules, fn(rule) { rule.id == id })
  }
  case rule {
    Ok(rule) -> editor(ctx, rule, "", True)
    Error(Nil) -> wisp.not_found()
  }
}

/// The rule editor page, with what the rule matches if `preview` is set and
/// it is valid.
fn editor(
  ctx: Context,
  rule: categories.Rule,
  error: String,
  preview: Bool,
) -> wisp.Response {
  let page = {
    use overview <- result.try(rules.overview(ctx.db))
    use matches <- result.map(case preview {
      True -> rules.preview(ctx.db, rule)
      False -> Ok(Error(""))
    })
    let #(error, matches) = case error, matches {
      "", Error("") -> #("", option.None)
      "", Error(message) -> #(message, option.None)
      _, Ok(preview) -> #(error, option.Some(preview))
      _, Error(_) -> #(error, option.None)
    }
    dashboard.rule_editor(rule, overview, error, matches)
  }
  case page {
    Ok(html) -> wisp.html_response(html, 200)
    Error(err) -> db_error(err)
  }
}

/// Saves the editor's form, or shows what it would match with
/// `action=preview`. Errors show the form again with what was entered.
fn save_rule(req: wisp.Request, ctx: Context) -> wisp.Response {
  use req <- wisp.csrf_known_header_protection(req)
  use form <- wisp.require_form(req)
  let field = fn(name) { list.key_find(form.values, name) |> result.unwrap("") }
  let id = field("id") |> int.parse |> result.unwrap(0)
  let patterns = string.split(field("patterns"), "\n")
  let ignore_case = field("ignore_case") == "on"
  let devices =
    list.filter(form.values, fn(v) { v.0 == "devices" })
    |> list.map(pair.second)
  // what was entered, to show it again
  let entered =
    categories.Rule(
      id,
      categories.normalize_name(field("category")),
      categories.join_patterns(patterns),
      ignore_case,
      devices,
    )
  case rules.parse(id, field("category"), patterns, ignore_case, devices) {
    Error(message) -> editor(ctx, entered, message, False)
    Ok(rule) ->
      case field("action") {
        "preview" -> editor(ctx, rule, "", True)
        _ ->
          case store_rule(ctx, rule) {
            Ok(Nil) ->
              wisp.redirect(
                "/categories?open=" <> uri.percent_encode(rule.name),
              )
            Error(err) -> db_error(err)
          }
      }
  }
}

/// Saves a rule, its category is added if it doesn't exist, and puts the
/// stored events into categories again.
fn store_rule(
  ctx: Context,
  rule: categories.Rule,
) -> Result(Nil, sqlight.Error) {
  use existing <- result.try(db.category_list(ctx.db))
  use _ <- result.try(case list.any(existing, fn(c) { c.name == rule.name }) {
    True -> Ok(Nil)
    False -> db.save_category(ctx.db, rule.name, categories.Neutral)
  })
  use _ <- result.try(db.save_rule(ctx.db, id_option(rule.id), rule))
  db.recategorize(ctx.db)
}

fn id_option(id: Int) -> option.Option(Int) {
  case id {
    0 -> option.None
    id -> option.Some(id)
  }
}

fn delete_rule(req: wisp.Request, ctx: Context, id: String) -> wisp.Response {
  use _req <- wisp.csrf_known_header_protection(req)
  let done = {
    use id <- result.try(int.parse(id) |> result.replace_error(Nil))
    use rules <- result.try(db.rules(ctx.db) |> result.replace_error(Nil))
    use rule <- result.try(list.find(rules, fn(rule) { rule.id == id }))
    use _ <- result.try(db.delete_rule(ctx.db, id) |> result.replace_error(Nil))
    use _ <- result.map(db.recategorize(ctx.db) |> result.replace_error(Nil))
    rule.name
  }
  case done {
    Ok(name) -> wisp.redirect("/categories?open=" <> uri.percent_encode(name))
    Error(Nil) -> wisp.not_found()
  }
}

fn categories_json(ctx: Context) -> wisp.Response {
  case rules.overview(ctx.db) {
    Ok(overview) ->
      rules.overview_to_json(overview)
      |> json.to_string
      |> wisp.json_response(200)
    Error(err) -> db_error(err)
  }
}

/// `{"id"?, "category", "patterns": [...], "ignore_case", "devices": [...]}`
fn rule_decoder() -> decode.Decoder(
  #(Int, String, List(String), Bool, List(String)),
) {
  use id <- decode.optional_field("id", 0, decode.int)
  use name <- decode.field("category", decode.string)
  use patterns <- decode.field("patterns", decode.list(decode.string))
  use ignore_case <- decode.optional_field("ignore_case", True, decode.bool)
  use devices <- decode.optional_field(
    "devices",
    [],
    decode.list(decode.string),
  )
  decode.success(#(id, name, patterns, ignore_case, devices))
}

/// The rule of a JSON body, or the response for why there is none.
fn require_rule(
  req: wisp.Request,
  next: fn(categories.Rule) -> wisp.Response,
) -> wisp.Response {
  use body <- wisp.require_json(req)
  case decode.run(body, rule_decoder()) {
    Error(_) -> wisp.unprocessable_content()
    Ok(#(id, name, patterns, ignore_case, devices)) ->
      case rules.parse(id, name, patterns, ignore_case, devices) {
        Error(message) -> error_json(message)
        Ok(rule) -> next(rule)
      }
  }
}

fn error_json(message: String) -> wisp.Response {
  json.object([#("error", json.string(message))])
  |> json.to_string
  |> wisp.json_response(422)
}

fn save_rule_json(req: wisp.Request, ctx: Context) -> wisp.Response {
  use rule <- require_rule(req)
  case store_rule(ctx, rule) {
    Ok(Nil) -> wisp.no_content()
    Error(err) -> db_error(err)
  }
}

fn preview_json(req: wisp.Request, ctx: Context) -> wisp.Response {
  use rule <- require_rule(req)
  case rules.preview(ctx.db, rule) {
    Ok(Ok(preview)) ->
      rules.preview_to_json(preview)
      |> json.to_string
      |> wisp.json_response(200)
    Ok(Error(message)) -> error_json(message)
    Error(err) -> db_error(err)
  }
}

fn delete_rule_json(ctx: Context, id: String) -> wisp.Response {
  case int.parse(id) {
    Ok(id) -> api_changed(ctx, db.delete_rule(ctx.db, id) |> result.map(Ok))
    Error(Nil) -> wisp.not_found()
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

fn db_error(err: sqlight.Error) -> wisp.Response {
  wisp.log_error(err.message)
  wisp.internal_server_error()
}
