import gleam/dynamic/decode
import gleam/list
import gleam/option
import gleam/string
import parrot/dev
import sqlight

pub type DbError {
  QueryFailed(String)
  /// A UNIQUE, FOREIGN KEY or CHECK constraint rejected the write.
  ConstraintViolation(String)
  ExpectedOneRow
  ExpectedAtMostOneRow
}

pub fn to_string(err: DbError) -> String {
  case err {
    QueryFailed(msg) -> "Database error: " <> msg
    ConstraintViolation(msg) -> "Constraint violation: " <> msg
    ExpectedOneRow -> "expected one row got zero or multiple"
    ExpectedAtMostOneRow -> "expected one row"
  }
}

fn from_sqlight(err: sqlight.Error) -> DbError {
  case err.code {
    sqlight.Constraint
    | sqlight.ConstraintCheck
    | sqlight.ConstraintForeignkey
    | sqlight.ConstraintNotnull
    | sqlight.ConstraintPrimarykey
    | sqlight.ConstraintUnique -> ConstraintViolation(err.message)
    _ -> QueryFailed(string.inspect(err))
  }
}

fn param(p: dev.Param) -> sqlight.Value {
  case p {
    dev.ParamBool(x) -> sqlight.bool(x)
    dev.ParamFloat(x) -> sqlight.float(x)
    dev.ParamInt(x) -> sqlight.int(x)
    dev.ParamString(x) -> sqlight.text(x)
    dev.ParamBitArray(x) -> sqlight.blob(x)
    dev.ParamNullable(x) -> sqlight.nullable(param, x)
    dev.ParamList(_) -> panic as "sqlite does not implement lists"
    dev.ParamDate(_) -> panic as "date parameter needs to be implemented"
    dev.ParamTimestamp(_) -> panic as "sqlite does not support timestamps"
    dev.ParamDynamic(_) -> panic as "cannot process dynamic parameter"
  }
}

pub fn exec(
  conn: sqlight.Connection,
  q: #(String, List(dev.Param)),
) -> Result(Nil, DbError) {
  let #(sql, with) = q
  case
    sqlight.query(
      sql,
      on: conn,
      with: list.map(with, param),
      expecting: decode.success(Nil),
    )
  {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error(from_sqlight(err))
  }
}

pub fn query(
  conn: sqlight.Connection,
  q: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(List(a), DbError) {
  let #(sql, with, expecting) = q
  case sqlight.query(sql, on: conn, with: list.map(with, param), expecting:) {
    Ok(rows) -> Ok(rows)
    Error(err) -> Error(from_sqlight(err))
  }
}

pub fn query_one(
  conn: sqlight.Connection,
  q: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(a, DbError) {
  case query(conn, q) {
    Ok([row]) -> Ok(row)
    Ok(_) -> Error(ExpectedOneRow)
    Error(err) -> Error(err)
  }
}

pub fn query_optional(
  conn: sqlight.Connection,
  q: #(String, List(dev.Param), decode.Decoder(a)),
) -> Result(option.Option(a), DbError) {
  case query(conn, q) {
    Ok([row]) -> Ok(option.Some(row))
    Ok([]) -> Ok(option.None)
    Ok(_) -> Error(ExpectedAtMostOneRow)
    Error(err) -> Error(err)
  }
}

pub fn transaction(
  conn: sqlight.Connection,
  work: fn() -> Result(a, b),
) -> Result(a, b) {
  let assert Ok(_) = sqlight.exec("BEGIN", conn)
  case work() {
    Ok(value) -> {
      let assert Ok(_) = sqlight.exec("COMMIT", conn)
      Ok(value)
    }
    Error(err) -> {
      let assert Ok(_) = sqlight.exec("ROLLBACK", conn)
      Error(err)
    }
  }
}
