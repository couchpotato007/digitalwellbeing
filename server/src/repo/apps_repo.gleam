import gleam/list
import gleam/option.{type Option}
import gleam/result
import repo/db
import server/sql
import sqlight

pub type App {
  App(id: Int, app_id: String, title: String, category_id: Option(Int))
}

pub fn upsert(
  conn: sqlight.Connection,
  app_id: String,
  title: String,
) -> Result(App, db.DbError) {
  sql.upsert_app(app_id, title)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    App(
      id: row.id,
      app_id: row.app_id,
      title: row.title,
      category_id: row.category_id,
    )
  })
}

pub fn get(
  conn: sqlight.Connection,
  id: String,
) -> Result(option.Option(App), db.DbError) {
  sql.get_app_by_app_id(id)
  |> db.query_optional(conn, _)
  |> result.map(
    option.map(_, fn(row) {
      App(
        id: row.id,
        app_id: row.app_id,
        title: row.title,
        category_id: row.category_id,
      )
    }),
  )
}

pub fn list_apps(conn: sqlight.Connection) -> Result(List(App), db.DbError) {
  sql.list_apps()
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      App(
        id: row.id,
        app_id: row.app_id,
        title: row.title,
        category_id: row.category_id,
      )
    }),
  )
}

pub fn set_category(
  conn: sqlight.Connection,
  id: Int,
  category_id: Option(Int),
) -> Result(Nil, db.DbError) {
  sql.set_app_category(category_id, id)
  |> db.exec(conn, _)
}
