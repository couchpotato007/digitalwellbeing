import config
import context
import gleam/erlang/process
import gleam/io
import migrations
import mist
import simplifile
import sqlight
import web/router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let cfg = case config.load() {
    Ok(cfg) -> cfg
    Error(msg) -> {
      io.print_error(msg)
      panic
    }
  }

  case simplifile.create_directory_all(cfg.config_dir) {
    Ok(Nil) -> Nil
    Error(err) -> {
      io.print_error(
        "Cant create directory: "
        <> cfg.config_dir
        <> " ("
        <> simplifile.describe_error(err)
        <> ")",
      )
    }
  }

  let db_path = cfg.config_dir <> "/db.sqlite3"

  let conn = case sqlight.open("file:" <> db_path) {
    Ok(conn) -> conn
    Error(err) -> {
      io.print_error("Cant open SQLite db: " <> db_path)
      panic as sqlight_error_message(err)
    }
  }

  case migrations.migrate(conn) {
    Ok(Nil) -> Nil
    Error(err) -> {
      io.print_error("DB migration failed")
      panic as sqlight_error_message(err)
    }
  }

  let ctx = context.Context(cfg: cfg, db: conn)

  let secret_base_key = cfg.secret_base_key
  let handler = fn(req) { router.handle_request(req, ctx) }

  let assert Ok(_) =
    wisp_mist.handler(handler, secret_base_key)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(cfg.port)
    |> mist.start

  process.sleep_forever()
}

fn sqlight_error_message(err: sqlight.Error) -> String {
  let sqlight.SqlightError(_, message, _) = err
  message
}
