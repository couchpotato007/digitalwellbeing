import gleam/list
import gleam/option.{type Option}
import gleam/result
import repo/db
import server/sql
import sqlight

/// Exactly one of `app_id` and `category_id` is set.
pub type Limit {
  Limit(
    id: Int,
    user_id: Int,
    app_id: Option(Int),
    category_id: Option(Int),
    daily_seconds: Int,
  )
}

pub fn list_by_user(
  conn: sqlight.Connection,
  user_id: Int,
) -> Result(List(Limit), db.DbError) {
  sql.list_limits_by_user(user_id)
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      Limit(
        id: row.id,
        user_id: row.user_id,
        app_id: row.app_id,
        category_id: row.category_id,
        daily_seconds: row.daily_seconds,
      )
    }),
  )
}

pub fn get(conn: sqlight.Connection, id: Int) -> Result(Limit, db.DbError) {
  sql.get_limit(id)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    Limit(
      id: row.id,
      user_id: row.user_id,
      app_id: row.app_id,
      category_id: row.category_id,
      daily_seconds: row.daily_seconds,
    )
  })
}

pub fn create(
  conn: sqlight.Connection,
  user_id: Int,
  app_id: Option(Int),
  category_id: Option(Int),
  daily_seconds: Int,
) -> Result(Limit, db.DbError) {
  sql.create_limit(user_id:, app_id:, category_id:, daily_seconds:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    Limit(
      id: row.id,
      user_id: row.user_id,
      app_id: row.app_id,
      category_id: row.category_id,
      daily_seconds: row.daily_seconds,
    )
  })
}

pub fn update(
  conn: sqlight.Connection,
  id: Int,
  daily_seconds: Int,
) -> Result(Limit, db.DbError) {
  sql.update_limit(daily_seconds:, id:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    Limit(
      id: row.id,
      user_id: row.user_id,
      app_id: row.app_id,
      category_id: row.category_id,
      daily_seconds: row.daily_seconds,
    )
  })
}

pub fn delete(conn: sqlight.Connection, id: Int) -> Result(Nil, db.DbError) {
  sql.delete_limit(id)
  |> db.query_one(conn, _)
  |> result.replace(Nil)
}
