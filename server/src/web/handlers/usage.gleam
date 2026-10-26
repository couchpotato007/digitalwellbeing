import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import gleam/result
import repo/app_usage_repo
import repo/db
import repo/devices_repo
import sqlight
import web/handlers/errors

pub fn to_api(usage: app_usage_repo.AppUsage) -> types.AppUsage {
  types.AppUsage(
    id: usage.id,
    device_id: usage.device_id,
    app_id: usage.app_id,
    started_at: usage.started_at,
    ended_at: usage.ended_at,
  )
}

pub fn list_by_device(
  conn: sqlight.Connection,
  r: req.ListDeviceUsageRequest,
) -> res.ListDeviceUsageResponse {
  let usage = {
    use _ <- result.try(devices_repo.get(conn, r.device_id))
    app_usage_repo.list_by_device(conn, r.device_id, r.from, r.to)
  }
  case usage {
    Ok(usage) -> res.ListDeviceUsageResponseOk(list.map(usage, to_api))
    Error(db.ExpectedOneRow) ->
      res.ListDeviceUsageResponseNotFound(errors.not_found("Device"))
    Error(err) ->
      res.ListDeviceUsageResponseInternalServerError(errors.internal(err))
  }
}

/// Stores all sessions in one transaction and marks the device as synced.
pub fn upload(
  conn: sqlight.Connection,
  r: req.UploadDeviceUsageRequest,
) -> res.UploadDeviceUsageResponse {
  let stored = {
    use _ <- result.try(devices_repo.get(conn, r.device_id))
    use <- db.transaction(conn)
    use stored <- result.try(
      list.try_map(r.body, fn(item) {
        app_usage_repo.upsert(
          conn,
          r.device_id,
          item.app_id,
          item.started_at,
          item.ended_at,
        )
      }),
    )
    use _ <- result.try(devices_repo.touch_last_sync(conn, r.device_id))
    Ok(stored)
  }
  case stored {
    Ok(stored) -> res.UploadDeviceUsageResponseCreated(list.map(stored, to_api))
    Error(db.ExpectedOneRow) ->
      res.UploadDeviceUsageResponseNotFound(errors.not_found("Device"))
    Error(db.ConstraintViolation(_) as err) ->
      res.UploadDeviceUsageResponseConflict(errors.conflict(err))
    Error(err) ->
      res.UploadDeviceUsageResponseInternalServerError(errors.internal(err))
  }
}

pub fn get(
  conn: sqlight.Connection,
  r: req.GetUsageRequest,
) -> res.GetUsageResponse {
  case app_usage_repo.get(conn, r.usage_id) {
    Ok(usage) -> res.GetUsageResponseOk(to_api(usage))
    Error(db.ExpectedOneRow) ->
      res.GetUsageResponseNotFound(errors.not_found("Usage"))
    Error(err) -> res.GetUsageResponseInternalServerError(errors.internal(err))
  }
}

pub fn delete(
  conn: sqlight.Connection,
  r: req.DeleteUsageRequest,
) -> res.DeleteUsageResponse {
  case app_usage_repo.delete(conn, r.usage_id) {
    Ok(Nil) -> res.DeleteUsageResponseNoContent
    Error(db.ExpectedOneRow) ->
      res.DeleteUsageResponseNotFound(errors.not_found("Usage"))
    Error(err) ->
      res.DeleteUsageResponseInternalServerError(errors.internal(err))
  }
}
