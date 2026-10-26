import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import repo/db
import repo/user_repo
import sqlight
import web/handlers/errors

pub fn to_api(user: user_repo.User) -> types.User {
  types.User(
    id: user.id,
    name: user.name,
    created_at: user.created_at,
    updated_at: user.updated_at,
  )
}

pub fn list(conn: sqlight.Connection) -> res.ListUsersResponse {
  case user_repo.list(conn) {
    Ok(users) -> res.ListUsersResponseOk(list.map(users, to_api))
    Error(err) -> res.ListUsersResponseInternalServerError(errors.internal(err))
  }
}

pub fn create(
  conn: sqlight.Connection,
  r: req.CreateUserRequest,
) -> res.CreateUserResponse {
  case user_repo.create(conn, r.body.name) {
    Ok(user) -> res.CreateUserResponseCreated(to_api(user))
    Error(err) ->
      res.CreateUserResponseInternalServerError(errors.internal(err))
  }
}

pub fn get(
  conn: sqlight.Connection,
  r: req.GetUserRequest,
) -> res.GetUserResponse {
  case user_repo.get(conn, r.user_id) {
    Ok(user) -> res.GetUserResponseOk(to_api(user))
    Error(db.ExpectedOneRow) ->
      res.GetUserResponseNotFound(errors.not_found("User"))
    Error(err) -> res.GetUserResponseInternalServerError(errors.internal(err))
  }
}

pub fn update(
  conn: sqlight.Connection,
  r: req.UpdateUserRequest,
) -> res.UpdateUserResponse {
  case user_repo.update(conn, r.user_id, r.body.name) {
    Ok(user) -> res.UpdateUserResponseOk(to_api(user))
    Error(db.ExpectedOneRow) ->
      res.UpdateUserResponseNotFound(errors.not_found("User"))
    Error(err) ->
      res.UpdateUserResponseInternalServerError(errors.internal(err))
  }
}

pub fn delete(
  conn: sqlight.Connection,
  r: req.DeleteUserRequest,
) -> res.DeleteUserResponse {
  case user_repo.delete(conn, r.user_id) {
    Ok(Nil) -> res.DeleteUserResponseNoContent
    Error(db.ExpectedOneRow) ->
      res.DeleteUserResponseNotFound(errors.not_found("User"))
    Error(err) ->
      res.DeleteUserResponseInternalServerError(errors.internal(err))
  }
}
