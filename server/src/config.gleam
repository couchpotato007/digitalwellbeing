import envoy
import gleam/int
import gleam/result

pub type Config {
  Config(config_dir: String, secret_base_key: String, port: Int)
}

fn required(name) {
  envoy.get(name) |> result.replace_error("Missing env var: " <> name)
}

pub fn load() -> Result(Config, String) {
  use config_dir <- result.try(required("CONFIG_DIR"))
  use secret_base_key <- result.try(required("SECRET_BASE_KEY"))
  let port = envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8080)

  Ok(Config(config_dir:, secret_base_key:, port:))
}
