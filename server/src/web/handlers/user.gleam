import context
import error
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import repo/db
import repo/user_repo
import wisp

pub type CreateUserInput {
  CreateUserInput(name: String)
}

fn create_user_input_decoder() -> decode.Decoder(CreateUserInput) {
  use name <- decode.field("name", decode.string)
  decode.success(CreateUserInput(name:))
}

pub fn user_handler(
  ctx: context.Context,
  req: wisp.Request,
  id: Option(String),
) -> wisp.Response {
  case req.method {
    http.Get -> {
      case id {
        option.None -> {
          let assert Ok(_) = user_repo.create(ctx.db, "Test")
          wisp.ok() |> wisp.string_body("Get all users")
        }
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
    http.Post -> {
      use body <- wisp.require_bit_array_body(req)
      {
        use body_str <- result.try(
          bit_array.to_string(body)
          |> result.replace_error(error.BadRequest("No UTF8")),
        )
        use input <- result.try(
          json.parse(body_str, create_user_input_decoder())
          |> result.replace_error(error.BadRequest(
            "Invalid JSON Format or missing field 'name'",
          )),
        )
        use _ <- result.try(
          user_repo.create(ctx.db, input.name)
          |> result.map_error(error.from_db),
        )
        Ok(wisp.created() |> wisp.string_body("User created: " <> input.name))
      }
      |> error.respond(fn(response) { response })
    }
    _ -> wisp.method_not_allowed([http.Delete, http.Put])
  }
}
