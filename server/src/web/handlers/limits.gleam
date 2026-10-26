import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import repo/db
import repo/limits_repo
import repo/user_repo
import sqlight
import web/handlers/errors

pub fn to_api(limit: limits_repo.Limit) -> types.Limit {
  types.Limit(
    id: limit.id,
    user_id: limit.user_id,
    app_id: limit.app_id,
    category_id: limit.category_id,
    daily_seconds: limit.daily_seconds,
  )
}

pub fn list_by_user(
  conn: sqlight.Connection,
  r: req.ListUserLimitsRequest,
) -> res.ListUserLimitsResponse {
  let limits = {
    use _ <- result.try(user_repo.get(conn, r.user_id))
    limits_repo.list_by_user(conn, r.user_id)
  }
  case limits {
    Ok(limits) -> res.ListUserLimitsResponseOk(list.map(limits, to_api))
    Error(db.ExpectedOneRow) ->
      res.ListUserLimitsResponseNotFound(errors.not_found("User"))
    Error(err) ->
      res.ListUserLimitsResponseInternalServerError(errors.internal(err))
  }
}

pub fn create(
  conn: sqlight.Connection,
  r: req.CreateLimitRequest,
) -> res.CreateLimitResponse {
  let types.LimitInput(app_id:, category_id:, daily_seconds:) = r.body
  case app_id, category_id {
    Some(_), Some(_) | None, None ->
      res.CreateLimitResponseBadRequest(errors.bad_request(
        "Exactly one of app_id and category_id must be set",
      ))
    _, _ -> {
      let limit = {
        use _ <- result.try(user_repo.get(conn, r.user_id))
        limits_repo.create(conn, r.user_id, app_id, category_id, daily_seconds)
      }
      case limit {
        Ok(limit) -> res.CreateLimitResponseCreated(to_api(limit))
        Error(db.ExpectedOneRow) ->
          res.CreateLimitResponseNotFound(errors.not_found("User"))
        Error(db.ConstraintViolation(_) as err) ->
          res.CreateLimitResponseConflict(errors.conflict(err))
        Error(err) ->
          res.CreateLimitResponseInternalServerError(errors.internal(err))
      }
    }
  }
}

pub fn get(
  conn: sqlight.Connection,
  r: req.GetLimitRequest,
) -> res.GetLimitResponse {
  case limits_repo.get(conn, r.limit_id) {
    Ok(limit) -> res.GetLimitResponseOk(to_api(limit))
    Error(db.ExpectedOneRow) ->
      res.GetLimitResponseNotFound(errors.not_found("Limit"))
    Error(err) -> res.GetLimitResponseInternalServerError(errors.internal(err))
  }
}

pub fn update(
  conn: sqlight.Connection,
  r: req.UpdateLimitRequest,
) -> res.UpdateLimitResponse {
  case limits_repo.update(conn, r.limit_id, r.body.daily_seconds) {
    Ok(limit) -> res.UpdateLimitResponseOk(to_api(limit))
    Error(db.ExpectedOneRow) ->
      res.UpdateLimitResponseNotFound(errors.not_found("Limit"))
    Error(err) ->
      res.UpdateLimitResponseInternalServerError(errors.internal(err))
  }
}

pub fn delete(
  conn: sqlight.Connection,
  r: req.DeleteLimitRequest,
) -> res.DeleteLimitResponse {
  case limits_repo.delete(conn, r.limit_id) {
    Ok(Nil) -> res.DeleteLimitResponseNoContent
    Error(db.ExpectedOneRow) ->
      res.DeleteLimitResponseNotFound(errors.not_found("Limit"))
    Error(err) ->
      res.DeleteLimitResponseInternalServerError(errors.internal(err))
  }
}
