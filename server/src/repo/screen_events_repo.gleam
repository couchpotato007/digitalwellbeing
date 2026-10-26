import gleam/list
import gleam/result
import repo/db
import server/sql
import sqlight

pub type ScreenEventType {
  ScreenOn
  ScreenOff
  Unlock
}

pub type ScreenEvent {
  ScreenEvent(id: Int, device_id: Int, ts: Int, type_: ScreenEventType)
}

fn type_to_string(type_: ScreenEventType) -> String {
  case type_ {
    ScreenOn -> "screen_on"
    ScreenOff -> "screen_off"
    Unlock -> "unlock"
  }
}

/// The table has a CHECK constraint on `type`, so other values cannot occur.
fn type_from_string(value: String) -> ScreenEventType {
  case value {
    "screen_on" -> ScreenOn
    "screen_off" -> ScreenOff
    _ -> Unlock
  }
}

/// Events of a device with `from <= ts < to` (unix epoch milliseconds).
pub fn list_by_device(
  conn: sqlight.Connection,
  device_id: Int,
  from: Int,
  to: Int,
) -> Result(List(ScreenEvent), db.DbError) {
  sql.list_screen_events_by_device(device_id:, from_ts: from, to_ts: to)
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      ScreenEvent(
        id: row.id,
        device_id: row.device_id,
        ts: row.ts,
        type_: type_from_string(row.type_),
      )
    }),
  )
}

pub fn create(
  conn: sqlight.Connection,
  device_id: Int,
  ts: Int,
  type_: ScreenEventType,
) -> Result(ScreenEvent, db.DbError) {
  sql.create_screen_event(device_id:, ts:, type_: type_to_string(type_))
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    ScreenEvent(
      id: row.id,
      device_id: row.device_id,
      ts: row.ts,
      type_: type_from_string(row.type_),
    )
  })
}

pub fn delete(conn: sqlight.Connection, id: Int) -> Result(Nil, db.DbError) {
  sql.delete_screen_event(id)
  |> db.query_one(conn, _)
  |> result.replace(Nil)
}
