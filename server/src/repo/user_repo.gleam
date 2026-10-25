import gleam/result
import repo/db
import server/sql
import sqlight

pub type User {
  User(id: Int, name: String, created_at: String, updated_at: String)
}

pub fn create(
  conn: sqlight.Connection,
  name: String,
) -> Result(User, db.DbError) {
  sql.create_user(name)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    User(
      id: row.id,
      name: row.name,
      created_at: row.created_at,
      updated_at: row.updated_at,
    )
  })
}

pub fn get(conn: sqlight.Connection, id: Int) -> Result(User, db.DbError) {
  sql.get_user(id)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    User(
      id: row.id,
      name: row.name,
      created_at: row.created_at,
      updated_at: row.updated_at,
    )
  })
}
