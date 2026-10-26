import gleam/list
import gleam/result
import repo/db
import server/sql
import sqlight

pub type Device {
  Device(
    id: Int,
    user_id: Int,
    name: String,
    platform: String,
    last_sync: String,
  )
}

pub fn list_by_user(
  conn: sqlight.Connection,
  user_id: Int,
) -> Result(List(Device), db.DbError) {
  sql.list_devices_by_user(user_id)
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      Device(
        id: row.id,
        user_id: row.user_id,
        name: row.name,
        platform: row.platform,
        last_sync: row.last_sync,
      )
    }),
  )
}

pub fn get(conn: sqlight.Connection, id: Int) -> Result(Device, db.DbError) {
  sql.get_device(id)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    Device(
      id: row.id,
      user_id: row.user_id,
      name: row.name,
      platform: row.platform,
      last_sync: row.last_sync,
    )
  })
}

pub fn create(
  conn: sqlight.Connection,
  user_id: Int,
  name: String,
  platform: String,
) -> Result(Device, db.DbError) {
  sql.create_device(user_id:, name:, platform:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    Device(
      id: row.id,
      user_id: row.user_id,
      name: row.name,
      platform: row.platform,
      last_sync: row.last_sync,
    )
  })
}

pub fn update(
  conn: sqlight.Connection,
  id: Int,
  name: String,
  platform: String,
) -> Result(Device, db.DbError) {
  sql.update_device(name:, platform:, id:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    Device(
      id: row.id,
      user_id: row.user_id,
      name: row.name,
      platform: row.platform,
      last_sync: row.last_sync,
    )
  })
}

/// Sets `last_sync` to the current time.
pub fn touch_last_sync(
  conn: sqlight.Connection,
  id: Int,
) -> Result(Nil, db.DbError) {
  sql.touch_device_last_sync(id)
  |> db.exec(conn, _)
}

pub fn delete(conn: sqlight.Connection, id: Int) -> Result(Nil, db.DbError) {
  sql.delete_device(id)
  |> db.query_one(conn, _)
  |> result.replace(Nil)
}
