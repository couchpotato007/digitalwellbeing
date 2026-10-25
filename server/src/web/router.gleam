import context
import gleam/http/request
import gleam/http/response
import wisp

fn middleware(req, handler) {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use req <- wisp.csrf_known_header_protection(req)
  handler(req)
}

pub fn handle_request(
  req: request.Request(wisp.Connection),
  ctx: context.Context,
) -> response.Response(wisp.Body) {
  use req <- middleware(req)
  let cfg = ctx.cfg
  case wisp.path_segments(req) {
    [] -> wisp.ok() |> wisp.string_body("das kappt")
    ["track"] -> wisp.ok() |> wisp.string_body("Cool")
    _ -> wisp.not_found()
  }
}
