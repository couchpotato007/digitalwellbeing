import gleam/list
import gleam/result
import repo/db
import server/sql
import sqlight

pub type User {
  User(id: Int, name: String, created_at: String, updated_at: String)
}

pub fn list(conn: sqlight.Connection) -> Result(List(User), db.DbError) {
  sql.list_users()
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      User(
        id: row.id,
        name: row.name,
        created_at: row.created_at,
        updated_at: row.updated_at,
      )
    }),
  )
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

pub fn update(
  conn: sqlight.Connection,
  id: Int,
  name: String,
) -> Result(User, db.DbError) {
  sql.update_user(name:, id:)
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

pub fn delete(conn: sqlight.Connection, id: Int) -> Result(Nil, db.DbError) {
  sql.delete_user(id)
  |> db.query_one(conn, _)
  |> result.replace(Nil)
}
