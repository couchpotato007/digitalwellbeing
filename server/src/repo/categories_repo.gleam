import gleam/list
import gleam/result
import repo/db
import server/sql
import sqlight

pub type Category {
  Category(id: Int, name: String)
}

pub fn list(conn: sqlight.Connection) -> Result(List(Category), db.DbError) {
  sql.list_categories()
  |> db.query(conn, _)
  |> result.map(list.map(_, fn(row) { Category(id: row.id, name: row.name) }))
}

pub fn get(conn: sqlight.Connection, id: Int) -> Result(Category, db.DbError) {
  sql.get_category(id)
  |> db.query_one(conn, _)
  |> result.map(fn(row) { Category(id: row.id, name: row.name) })
}

pub fn create(
  conn: sqlight.Connection,
  name: String,
) -> Result(Category, db.DbError) {
  sql.create_category(name)
  |> db.query_one(conn, _)
  |> result.map(fn(row) { Category(id: row.id, name: row.name) })
}

pub fn update(
  conn: sqlight.Connection,
  id: Int,
  name: String,
) -> Result(Category, db.DbError) {
  sql.update_category(name:, id:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) { Category(id: row.id, name: row.name) })
}

pub fn delete(conn: sqlight.Connection, id: Int) -> Result(Nil, db.DbError) {
  sql.delete_category(id)
  |> db.query_one(conn, _)
  |> result.replace(Nil)
}
