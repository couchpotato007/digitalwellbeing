//// Implementations for the operations in `priv/openapi.yaml`.
////
//// oaspec writes this file once and never overwrites it. When an operation
//// is added to the spec, add its function here; the actual logic lives in
//// the per-resource modules in `web/handlers/`.

import api/request_types
import api/response_types
import sqlight
import web/handlers/apps
import web/handlers/categories
import web/handlers/daily_summaries
import web/handlers/devices
import web/handlers/limits
import web/handlers/screen_events
import web/handlers/usage
import web/handlers/users

/// Application state passed to every handler.
pub type State {
  State(db: sqlight.Connection)
}

pub fn list_apps(
  state: State,
  req: request_types.ListAppsRequest,
) -> response_types.ListAppsResponse {
  apps.list(state.db, req)
}

pub fn upsert_app(
  state: State,
  req: request_types.UpsertAppRequest,
) -> response_types.UpsertAppResponse {
  apps.upsert(state.db, req)
}

pub fn get_app(
  state: State,
  req: request_types.GetAppRequest,
) -> response_types.GetAppResponse {
  apps.get(state.db, req)
}

pub fn update_app(
  state: State,
  req: request_types.UpdateAppRequest,
) -> response_types.UpdateAppResponse {
  apps.update(state.db, req)
}

pub fn delete_app(
  state: State,
  req: request_types.DeleteAppRequest,
) -> response_types.DeleteAppResponse {
  apps.delete(state.db, req)
}

pub fn list_categories(state: State) -> response_types.ListCategoriesResponse {
  categories.list(state.db)
}

pub fn create_category(
  state: State,
  req: request_types.CreateCategoryRequest,
) -> response_types.CreateCategoryResponse {
  categories.create(state.db, req)
}

pub fn get_category(
  state: State,
  req: request_types.GetCategoryRequest,
) -> response_types.GetCategoryResponse {
  categories.get(state.db, req)
}

pub fn update_category(
  state: State,
  req: request_types.UpdateCategoryRequest,
) -> response_types.UpdateCategoryResponse {
  categories.update(state.db, req)
}

pub fn delete_category(
  state: State,
  req: request_types.DeleteCategoryRequest,
) -> response_types.DeleteCategoryResponse {
  categories.delete(state.db, req)
}

pub fn get_device(
  state: State,
  req: request_types.GetDeviceRequest,
) -> response_types.GetDeviceResponse {
  devices.get(state.db, req)
}

pub fn update_device(
  state: State,
  req: request_types.UpdateDeviceRequest,
) -> response_types.UpdateDeviceResponse {
  devices.update(state.db, req)
}

pub fn delete_device(
  state: State,
  req: request_types.DeleteDeviceRequest,
) -> response_types.DeleteDeviceResponse {
  devices.delete(state.db, req)
}

pub fn list_device_daily_summaries(
  state: State,
  req: request_types.ListDeviceDailySummariesRequest,
) -> response_types.ListDeviceDailySummariesResponse {
  daily_summaries.list_by_device(state.db, req)
}

pub fn upsert_device_daily_summaries(
  state: State,
  req: request_types.UpsertDeviceDailySummariesRequest,
) -> response_types.UpsertDeviceDailySummariesResponse {
  daily_summaries.upsert(state.db, req)
}

pub fn list_device_screen_events(
  state: State,
  req: request_types.ListDeviceScreenEventsRequest,
) -> response_types.ListDeviceScreenEventsResponse {
  screen_events.list_by_device(state.db, req)
}

pub fn upload_device_screen_events(
  state: State,
  req: request_types.UploadDeviceScreenEventsRequest,
) -> response_types.UploadDeviceScreenEventsResponse {
  screen_events.upload(state.db, req)
}

pub fn list_device_usage(
  state: State,
  req: request_types.ListDeviceUsageRequest,
) -> response_types.ListDeviceUsageResponse {
  usage.list_by_device(state.db, req)
}

pub fn upload_device_usage(
  state: State,
  req: request_types.UploadDeviceUsageRequest,
) -> response_types.UploadDeviceUsageResponse {
  usage.upload(state.db, req)
}

pub fn get_limit(
  state: State,
  req: request_types.GetLimitRequest,
) -> response_types.GetLimitResponse {
  limits.get(state.db, req)
}

pub fn update_limit(
  state: State,
  req: request_types.UpdateLimitRequest,
) -> response_types.UpdateLimitResponse {
  limits.update(state.db, req)
}

pub fn delete_limit(
  state: State,
  req: request_types.DeleteLimitRequest,
) -> response_types.DeleteLimitResponse {
  limits.delete(state.db, req)
}

pub fn delete_screen_event(
  state: State,
  req: request_types.DeleteScreenEventRequest,
) -> response_types.DeleteScreenEventResponse {
  screen_events.delete(state.db, req)
}

pub fn get_usage(
  state: State,
  req: request_types.GetUsageRequest,
) -> response_types.GetUsageResponse {
  usage.get(state.db, req)
}

pub fn delete_usage(
  state: State,
  req: request_types.DeleteUsageRequest,
) -> response_types.DeleteUsageResponse {
  usage.delete(state.db, req)
}

pub fn list_users(state: State) -> response_types.ListUsersResponse {
  users.list(state.db)
}

pub fn create_user(
  state: State,
  req: request_types.CreateUserRequest,
) -> response_types.CreateUserResponse {
  users.create(state.db, req)
}

pub fn get_user(
  state: State,
  req: request_types.GetUserRequest,
) -> response_types.GetUserResponse {
  users.get(state.db, req)
}

pub fn update_user(
  state: State,
  req: request_types.UpdateUserRequest,
) -> response_types.UpdateUserResponse {
  users.update(state.db, req)
}

pub fn delete_user(
  state: State,
  req: request_types.DeleteUserRequest,
) -> response_types.DeleteUserResponse {
  users.delete(state.db, req)
}

pub fn list_user_devices(
  state: State,
  req: request_types.ListUserDevicesRequest,
) -> response_types.ListUserDevicesResponse {
  devices.list_by_user(state.db, req)
}

pub fn create_device(
  state: State,
  req: request_types.CreateDeviceRequest,
) -> response_types.CreateDeviceResponse {
  devices.create(state.db, req)
}

pub fn list_user_limits(
  state: State,
  req: request_types.ListUserLimitsRequest,
) -> response_types.ListUserLimitsResponse {
  limits.list_by_user(state.db, req)
}

pub fn create_limit(
  state: State,
  req: request_types.CreateLimitRequest,
) -> response_types.CreateLimitResponse {
  limits.create(state.db, req)
}
