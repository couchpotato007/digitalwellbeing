import context
import error
import gleam/http
import gleam/int
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import repo/db
import repo/user_repo
import wisp

pub fn user_handler(
  ctx: context.Context,
  req: wisp.Request,
  id: Option(String),
) -> wisp.Response {
  case req.method {
    http.Get -> {
      case id {
        option.None -> wisp.ok() |> wisp.string_body("Get all users")
        Some(id_str) ->
          {
            use id_int <- result.try(
              int.parse(id_str)
              |> result.replace_error(error.BadRequest("Invalid user id")),
            )
            use user <- result.try(
              user_repo.get(ctx.db, id_int)
              |> result.map_error(error.from_db),
            )
            Ok(user)
          }
          |> error.respond(fn(user) {
            wisp.ok() |> wisp.string_body(string.inspect(user))
          })
      }
    }
    http.Post -> wisp.created()
    _ -> wisp.method_not_allowed([http.Delete, http.Put])
  }
}
