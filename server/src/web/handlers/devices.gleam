import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import gleam/result
import repo/db
import repo/devices_repo
import repo/user_repo
import sqlight
import web/handlers/errors

pub fn to_api(device: devices_repo.Device) -> types.Device {
  types.Device(
    id: device.id,
    user_id: device.user_id,
    name: device.name,
    platform: device.platform,
    last_sync: device.last_sync,
  )
}

pub fn list_by_user(
  conn: sqlight.Connection,
  r: req.ListUserDevicesRequest,
) -> res.ListUserDevicesResponse {
  let devices = {
    use _ <- result.try(user_repo.get(conn, r.user_id))
    devices_repo.list_by_user(conn, r.user_id)
  }
  case devices {
    Ok(devices) -> res.ListUserDevicesResponseOk(list.map(devices, to_api))
    Error(db.ExpectedOneRow) ->
      res.ListUserDevicesResponseNotFound(errors.not_found("User"))
    Error(err) ->
      res.ListUserDevicesResponseInternalServerError(errors.internal(err))
  }
}

pub fn create(
  conn: sqlight.Connection,
  r: req.CreateDeviceRequest,
) -> res.CreateDeviceResponse {
  let device = {
    use _ <- result.try(user_repo.get(conn, r.user_id))
    devices_repo.create(conn, r.user_id, r.body.name, r.body.platform)
  }
  case device {
    Ok(device) -> res.CreateDeviceResponseCreated(to_api(device))
    Error(db.ExpectedOneRow) ->
      res.CreateDeviceResponseNotFound(errors.not_found("User"))
    Error(err) ->
      res.CreateDeviceResponseInternalServerError(errors.internal(err))
  }
}

pub fn get(
  conn: sqlight.Connection,
  r: req.GetDeviceRequest,
) -> res.GetDeviceResponse {
  case devices_repo.get(conn, r.device_id) {
    Ok(device) -> res.GetDeviceResponseOk(to_api(device))
    Error(db.ExpectedOneRow) ->
      res.GetDeviceResponseNotFound(errors.not_found("Device"))
    Error(err) -> res.GetDeviceResponseInternalServerError(errors.internal(err))
  }
}

pub fn update(
  conn: sqlight.Connection,
  r: req.UpdateDeviceRequest,
) -> res.UpdateDeviceResponse {
  case devices_repo.update(conn, r.device_id, r.body.name, r.body.platform) {
    Ok(device) -> res.UpdateDeviceResponseOk(to_api(device))
    Error(db.ExpectedOneRow) ->
      res.UpdateDeviceResponseNotFound(errors.not_found("Device"))
    Error(err) ->
      res.UpdateDeviceResponseInternalServerError(errors.internal(err))
  }
}

pub fn delete(
  conn: sqlight.Connection,
  r: req.DeleteDeviceRequest,
) -> res.DeleteDeviceResponse {
  case devices_repo.delete(conn, r.device_id) {
    Ok(Nil) -> res.DeleteDeviceResponseNoContent
    Error(db.ExpectedOneRow) ->
      res.DeleteDeviceResponseNotFound(errors.not_found("Device"))
    Error(err) ->
      res.DeleteDeviceResponseInternalServerError(errors.internal(err))
  }
}
