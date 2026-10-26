import gleam/list
import gleam/result
import repo/db
import server/sql
import sqlight

pub type AppUsage {
  AppUsage(
    id: Int,
    device_id: Int,
    app_id: Int,
    started_at: String,
    ended_at: String,
  )
}

/// Sessions of a device that started in `[from, to)`.
pub fn list_by_device(
  conn: sqlight.Connection,
  device_id: Int,
  from: String,
  to: String,
) -> Result(List(AppUsage), db.DbError) {
  sql.list_app_usage_by_device(device_id:, from_ts: from, to_ts: to)
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      AppUsage(
        id: row.id,
        device_id: row.device_id,
        app_id: row.app_id,
        started_at: row.started_at,
        ended_at: row.ended_at,
      )
    }),
  )
}

pub fn get(conn: sqlight.Connection, id: Int) -> Result(AppUsage, db.DbError) {
  sql.get_app_usage(id)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    AppUsage(
      id: row.id,
      device_id: row.device_id,
      app_id: row.app_id,
      started_at: row.started_at,
      ended_at: row.ended_at,
    )
  })
}

/// Inserts a session or, if one with the same device, app and start
/// already exists, updates its end.
pub fn upsert(
  conn: sqlight.Connection,
  device_id: Int,
  app_id: Int,
  started_at: String,
  ended_at: String,
) -> Result(AppUsage, db.DbError) {
  sql.upsert_app_usage(device_id:, app_id:, started_at:, ended_at:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    AppUsage(
      id: row.id,
      device_id: row.device_id,
      app_id: row.app_id,
      started_at: row.started_at,
      ended_at: row.ended_at,
    )
  })
}

pub fn delete(conn: sqlight.Connection, id: Int) -> Result(Nil, db.DbError) {
  sql.delete_app_usage(id)
  |> db.query_one(conn, _)
  |> result.replace(Nil)
}
