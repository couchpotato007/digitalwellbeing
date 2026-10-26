import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import gleam/result
import repo/db
import repo/devices_repo
import repo/screen_events_repo
import sqlight
import web/handlers/errors

fn type_to_api(
  type_: screen_events_repo.ScreenEventType,
) -> types.ScreenEventType {
  case type_ {
    screen_events_repo.ScreenOn -> types.ScreenEventTypeScreenOn
    screen_events_repo.ScreenOff -> types.ScreenEventTypeScreenOff
    screen_events_repo.Unlock -> types.ScreenEventTypeUnlock
  }
}

fn type_from_api(
  type_: types.ScreenEventType,
) -> screen_events_repo.ScreenEventType {
  case type_ {
    types.ScreenEventTypeScreenOn -> screen_events_repo.ScreenOn
    types.ScreenEventTypeScreenOff -> screen_events_repo.ScreenOff
    types.ScreenEventTypeUnlock -> screen_events_repo.Unlock
  }
}

pub fn to_api(event: screen_events_repo.ScreenEvent) -> types.ScreenEvent {
  types.ScreenEvent(
    id: event.id,
    device_id: event.device_id,
    ts: event.ts,
    type_: type_to_api(event.type_),
  )
}

pub fn list_by_device(
  conn: sqlight.Connection,
  r: req.ListDeviceScreenEventsRequest,
) -> res.ListDeviceScreenEventsResponse {
  let events = {
    use _ <- result.try(devices_repo.get(conn, r.device_id))
    screen_events_repo.list_by_device(conn, r.device_id, r.from, r.to)
  }
  case events {
    Ok(events) -> res.ListDeviceScreenEventsResponseOk(list.map(events, to_api))
    Error(db.ExpectedOneRow) ->
      res.ListDeviceScreenEventsResponseNotFound(errors.not_found("Device"))
    Error(err) ->
      res.ListDeviceScreenEventsResponseInternalServerError(errors.internal(err))
  }
}

/// Stores all events in one transaction and marks the device as synced.
pub fn upload(
  conn: sqlight.Connection,
  r: req.UploadDeviceScreenEventsRequest,
) -> res.UploadDeviceScreenEventsResponse {
  let stored = {
    use _ <- result.try(devices_repo.get(conn, r.device_id))
    use <- db.transaction(conn)
    use stored <- result.try(
      list.try_map(r.body, fn(item) {
        screen_events_repo.create(
          conn,
          r.device_id,
          item.ts,
          type_from_api(item.type_),
        )
      }),
    )
    use _ <- result.try(devices_repo.touch_last_sync(conn, r.device_id))
    Ok(stored)
  }
  case stored {
    Ok(stored) ->
      res.UploadDeviceScreenEventsResponseCreated(list.map(stored, to_api))
    Error(db.ExpectedOneRow) ->
      res.UploadDeviceScreenEventsResponseNotFound(errors.not_found("Device"))
    Error(err) ->
      res.UploadDeviceScreenEventsResponseInternalServerError(errors.internal(
        err,
      ))
  }
}

pub fn delete(
  conn: sqlight.Connection,
  r: req.DeleteScreenEventRequest,
) -> res.DeleteScreenEventResponse {
  case screen_events_repo.delete(conn, r.event_id) {
    Ok(Nil) -> res.DeleteScreenEventResponseNoContent
    Error(db.ExpectedOneRow) ->
      res.DeleteScreenEventResponseNotFound(errors.not_found("Screen event"))
    Error(err) ->
      res.DeleteScreenEventResponseInternalServerError(errors.internal(err))
  }
}
