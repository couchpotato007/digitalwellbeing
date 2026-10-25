import config
import sqlight

pub type Context {
  Context(cfg: config.Config, db: sqlight.Connection)
  // Context(cfg: config.Config)
}
