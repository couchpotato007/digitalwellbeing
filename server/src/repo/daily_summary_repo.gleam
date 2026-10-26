import gleam/list
import gleam/result
import repo/db
import server/sql
import sqlight

pub type DailySummary {
  DailySummary(
    device_id: Int,
    app_id: Int,
    day: String,
    total_seconds: Int,
    launches: Int,
  )
}

/// Summaries of a device for days in `[from, to]` (`YYYY-MM-DD`).
pub fn list_by_device(
  conn: sqlight.Connection,
  device_id: Int,
  from: String,
  to: String,
) -> Result(List(DailySummary), db.DbError) {
  sql.list_daily_summaries_by_device(device_id:, from_day: from, to_day: to)
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      DailySummary(
        device_id: row.device_id,
        app_id: row.app_id,
        day: row.day,
        total_seconds: row.total_seconds,
        launches: row.launches,
      )
    }),
  )
}

pub fn upsert(
  conn: sqlight.Connection,
  device_id: Int,
  app_id: Int,
  day: String,
  total_seconds: Int,
  launches: Int,
) -> Result(DailySummary, db.DbError) {
  sql.upsert_daily_summary(device_id:, app_id:, day:, total_seconds:, launches:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    DailySummary(
      device_id: row.device_id,
      app_id: row.app_id,
      day: row.day,
      total_seconds: row.total_seconds,
      launches: row.launches,
    )
  })
}
