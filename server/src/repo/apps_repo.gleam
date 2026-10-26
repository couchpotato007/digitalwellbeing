import gleam/list
import gleam/option.{type Option}
import gleam/result
import repo/db
import server/sql
import sqlight

/// `package_name` is stored in the `apps.app_id` column.
pub type App {
  App(id: Int, package_name: String, title: String, category_id: Option(Int))
}

pub fn list(conn: sqlight.Connection) -> Result(List(App), db.DbError) {
  sql.list_apps()
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      App(
        id: row.id,
        package_name: row.app_id,
        title: row.title,
        category_id: row.category_id,
      )
    }),
  )
}

pub fn list_by_category(
  conn: sqlight.Connection,
  category_id: Int,
) -> Result(List(App), db.DbError) {
  sql.list_apps_by_category(option.Some(category_id))
  |> db.query(conn, _)
  |> result.map(
    list.map(_, fn(row) {
      App(
        id: row.id,
        package_name: row.app_id,
        title: row.title,
        category_id: row.category_id,
      )
    }),
  )
}

pub fn get(conn: sqlight.Connection, id: Int) -> Result(App, db.DbError) {
  sql.get_app(id)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    App(
      id: row.id,
      package_name: row.app_id,
      title: row.title,
      category_id: row.category_id,
    )
  })
}

pub fn get_by_package_name(
  conn: sqlight.Connection,
  package_name: String,
) -> Result(Option(App), db.DbError) {
  sql.get_app_by_package_name(package_name)
  |> db.query_optional(conn, _)
  |> result.map(
    option.map(_, fn(row) {
      App(
        id: row.id,
        package_name: row.app_id,
        title: row.title,
        category_id: row.category_id,
      )
    }),
  )
}

pub fn upsert(
  conn: sqlight.Connection,
  package_name: String,
  title: String,
) -> Result(App, db.DbError) {
  sql.upsert_app(package_name:, title:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    App(
      id: row.id,
      package_name: row.app_id,
      title: row.title,
      category_id: row.category_id,
    )
  })
}

pub fn update(
  conn: sqlight.Connection,
  id: Int,
  title: String,
  category_id: Option(Int),
) -> Result(App, db.DbError) {
  sql.update_app(title:, category_id:, id:)
  |> db.query_one(conn, _)
  |> result.map(fn(row) {
    App(
      id: row.id,
      package_name: row.app_id,
      title: row.title,
      category_id: row.category_id,
    )
  })
}

pub fn delete(conn: sqlight.Connection, id: Int) -> Result(Nil, db.DbError) {
  sql.delete_app(id)
  |> db.query_one(conn, _)
  |> result.replace(Nil)
}
