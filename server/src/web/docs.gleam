import gleam/erlang/application
import simplifile
import wisp

const scalar_html =
  "<!doctype html>
<html>
  <head>
    <meta charset=\"utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
    <title>Digital Wellbeing API</title>
  </head>
  <body>
    <div id=\"app\"></div>
    <script src=\"https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.73.1\"></script>
    <script>
      Scalar.createApiReference('#app', { url: '/api/openapi.yaml' })
    </script>
  </body>
</html>
"

/// Scalar API reference rendering `openapi.yaml`.
pub fn page() -> wisp.Response {
  wisp.html_response(scalar_html, 200)
}

/// The spec is read on every request so edits show up without a restart.
pub fn spec() -> wisp.Response {
  let assert Ok(priv) = application.priv_directory("server")
  case simplifile.read(priv <> "/openapi.yaml") {
    Ok(yaml) ->
      wisp.ok()
      |> wisp.set_header("content-type", "application/yaml")
      |> wisp.string_body(yaml)
    Error(err) -> {
      wisp.log_error(
        "Cannot read openapi.yaml: " <> simplifile.describe_error(err),
      )
      wisp.internal_server_error()
    }
  }
}
