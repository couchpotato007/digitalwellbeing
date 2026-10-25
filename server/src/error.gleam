import gleam/io
import repo/db
import wisp

pub type Error {
  BadRequest(String)
  NotFound(String)
  Internal(db.DbError)
}

pub fn from_db(err: db.DbError) -> Error {
  case err {
    db.ExpectedOneRow -> NotFound("Not found")
    _ -> Internal(err)
  }
}

pub fn respond(
  result: Result(a, Error),
  render: fn(a) -> wisp.Response,
) -> wisp.Response {
  case result {
    Ok(value) -> render(value)
    Error(BadRequest(msg)) -> wisp.bad_request(msg)
    Error(NotFound(msg)) -> wisp.not_found() |> wisp.string_body(msg)
    Error(Internal(err)) -> {
      io.println_error(db.to_string(err))
      wisp.internal_server_error() |> wisp.string_body("Internal server error")
    }
  }
}
