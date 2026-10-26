import api/types
import repo/db
import wisp

pub fn not_found(resource: String) -> types.Error {
  types.Error(message: resource <> " not found")
}

pub fn bad_request(message: String) -> types.Error {
  types.Error(message:)
}

/// For `db.ConstraintViolation`, e.g. a duplicate name or a reference to a
/// row that does not exist.
pub fn conflict(err: db.DbError) -> types.Error {
  types.Error(message: db.to_string(err))
}

/// Logs the error and hides the details from the client.
pub fn internal(err: db.DbError) -> types.Error {
  wisp.log_error(db.to_string(err))
  types.Error(message: "Internal server error")
}
