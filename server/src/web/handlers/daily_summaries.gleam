import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import gleam/option
import gleam/result
import repo/daily_summary_repo
import repo/db
import repo/devices_repo
import sqlight
import web/handlers/errors

pub fn to_api(summary: daily_summary_repo.DailySummary) -> types.DailySummary {
  types.DailySummary(
    device_id: summary.device_id,
    app_id: summary.app_id,
    day: summary.day,
    total_seconds: summary.total_seconds,
    launches: summary.launches,
  )
}

pub fn list_by_device(
  conn: sqlight.Connection,
  r: req.ListDeviceDailySummariesRequest,
) -> res.ListDeviceDailySummariesResponse {
  let summaries = {
    use _ <- result.try(devices_repo.get(conn, r.device_id))
    daily_summary_repo.list_by_device(conn, r.device_id, r.from, r.to)
  }
  case summaries {
    Ok(summaries) ->
      res.ListDeviceDailySummariesResponseOk(list.map(summaries, to_api))
    Error(db.ExpectedOneRow) ->
      res.ListDeviceDailySummariesResponseNotFound(errors.not_found("Device"))
    Error(err) ->
      res.ListDeviceDailySummariesResponseInternalServerError(errors.internal(
        err,
      ))
  }
}

/// Stores all summaries in one transaction and marks the device as synced.
pub fn upsert(
  conn: sqlight.Connection,
  r: req.UpsertDeviceDailySummariesRequest,
) -> res.UpsertDeviceDailySummariesResponse {
  let stored = {
    use _ <- result.try(devices_repo.get(conn, r.device_id))
    use <- db.transaction(conn)
    use stored <- result.try(
      list.try_map(r.body, fn(item) {
        daily_summary_repo.upsert(
          conn,
          r.device_id,
          item.app_id,
          item.day,
          item.total_seconds,
          option.unwrap(item.launches, 0),
        )
      }),
    )
    use _ <- result.try(devices_repo.touch_last_sync(conn, r.device_id))
    Ok(stored)
  }
  case stored {
    Ok(stored) ->
      res.UpsertDeviceDailySummariesResponseOk(list.map(stored, to_api))
    Error(db.ExpectedOneRow) ->
      res.UpsertDeviceDailySummariesResponseNotFound(errors.not_found("Device"))
    Error(db.ConstraintViolation(_) as err) ->
      res.UpsertDeviceDailySummariesResponseConflict(errors.conflict(err))
    Error(err) ->
      res.UpsertDeviceDailySummariesResponseInternalServerError(errors.internal(
        err,
      ))
  }
}
