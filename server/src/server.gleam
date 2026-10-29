import config
import db
import gleam/erlang/process
import mist
import simplifile
import sqlight
import web
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  let assert Ok(cfg) = config.load()
  let assert Ok(Nil) = simplifile.create_directory_all(cfg.config_dir)
  let assert Ok(conn) = sqlight.open("file:" <> cfg.config_dir <> "/db.sqlite3")
    as { "Cannot open the database, is " <> cfg.config_dir <> " writable?" }
  let assert Ok(Nil) = db.migrate(conn)
  // the catalog of known apps may have changed with an update
  let assert Ok(Nil) = db.recategorize(conn)

  let ctx = web.Context(db: conn, token: cfg.admin_token)
  let assert Ok(_) =
    wisp_mist.handler(web.handle_request(_, ctx), cfg.secret_base_key)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(cfg.port)
    |> mist.start

  process.sleep_forever()
}
