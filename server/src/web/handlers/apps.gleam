import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import gleam/option.{None, Some}
import repo/apps_repo
import repo/db
import sqlight
import web/handlers/errors

pub fn to_api(app: apps_repo.App) -> types.App {
  types.App(
    id: app.id,
    package_name: app.package_name,
    title: app.title,
    category_id: app.category_id,
  )
}

pub fn list(
  conn: sqlight.Connection,
  r: req.ListAppsRequest,
) -> res.ListAppsResponse {
  let apps = case r.category_id {
    Some(category_id) -> apps_repo.list_by_category(conn, category_id)
    None -> apps_repo.list(conn)
  }
  case apps {
    Ok(apps) -> res.ListAppsResponseOk(list.map(apps, to_api))
    Error(err) -> res.ListAppsResponseInternalServerError(errors.internal(err))
  }
}

pub fn upsert(
  conn: sqlight.Connection,
  r: req.UpsertAppRequest,
) -> res.UpsertAppResponse {
  case apps_repo.upsert(conn, r.body.package_name, r.body.title) {
    Ok(app) -> res.UpsertAppResponseOk(to_api(app))
    Error(err) -> res.UpsertAppResponseInternalServerError(errors.internal(err))
  }
}

pub fn get(
  conn: sqlight.Connection,
  r: req.GetAppRequest,
) -> res.GetAppResponse {
  case apps_repo.get(conn, r.app_id) {
    Ok(app) -> res.GetAppResponseOk(to_api(app))
    Error(db.ExpectedOneRow) ->
      res.GetAppResponseNotFound(errors.not_found("App"))
    Error(err) -> res.GetAppResponseInternalServerError(errors.internal(err))
  }
}

pub fn update(
  conn: sqlight.Connection,
  r: req.UpdateAppRequest,
) -> res.UpdateAppResponse {
  case apps_repo.update(conn, r.app_id, r.body.title, r.body.category_id) {
    Ok(app) -> res.UpdateAppResponseOk(to_api(app))
    Error(db.ExpectedOneRow) ->
      res.UpdateAppResponseNotFound(errors.not_found("App"))
    Error(db.ConstraintViolation(_) as err) ->
      res.UpdateAppResponseConflict(errors.conflict(err))
    Error(err) -> res.UpdateAppResponseInternalServerError(errors.internal(err))
  }
}

pub fn delete(
  conn: sqlight.Connection,
  r: req.DeleteAppRequest,
) -> res.DeleteAppResponse {
  case apps_repo.delete(conn, r.app_id) {
    Ok(Nil) -> res.DeleteAppResponseNoContent
    Error(db.ExpectedOneRow) ->
      res.DeleteAppResponseNotFound(errors.not_found("App"))
    Error(err) -> res.DeleteAppResponseInternalServerError(errors.internal(err))
  }
}
