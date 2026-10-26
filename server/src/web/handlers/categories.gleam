import api/request_types as req
import api/response_types as res
import api/types
import gleam/list
import repo/categories_repo
import repo/db
import sqlight
import web/handlers/errors

pub fn to_api(category: categories_repo.Category) -> types.Category {
  types.Category(id: category.id, name: category.name)
}

pub fn list(conn: sqlight.Connection) -> res.ListCategoriesResponse {
  case categories_repo.list(conn) {
    Ok(categories) -> res.ListCategoriesResponseOk(list.map(categories, to_api))
    Error(err) ->
      res.ListCategoriesResponseInternalServerError(errors.internal(err))
  }
}

pub fn create(
  conn: sqlight.Connection,
  r: req.CreateCategoryRequest,
) -> res.CreateCategoryResponse {
  case categories_repo.create(conn, r.body.name) {
    Ok(category) -> res.CreateCategoryResponseCreated(to_api(category))
    Error(db.ConstraintViolation(_) as err) ->
      res.CreateCategoryResponseConflict(errors.conflict(err))
    Error(err) ->
      res.CreateCategoryResponseInternalServerError(errors.internal(err))
  }
}

pub fn get(
  conn: sqlight.Connection,
  r: req.GetCategoryRequest,
) -> res.GetCategoryResponse {
  case categories_repo.get(conn, r.category_id) {
    Ok(category) -> res.GetCategoryResponseOk(to_api(category))
    Error(db.ExpectedOneRow) ->
      res.GetCategoryResponseNotFound(errors.not_found("Category"))
    Error(err) ->
      res.GetCategoryResponseInternalServerError(errors.internal(err))
  }
}

pub fn update(
  conn: sqlight.Connection,
  r: req.UpdateCategoryRequest,
) -> res.UpdateCategoryResponse {
  case categories_repo.update(conn, r.category_id, r.body.name) {
    Ok(category) -> res.UpdateCategoryResponseOk(to_api(category))
    Error(db.ExpectedOneRow) ->
      res.UpdateCategoryResponseNotFound(errors.not_found("Category"))
    Error(db.ConstraintViolation(_) as err) ->
      res.UpdateCategoryResponseConflict(errors.conflict(err))
    Error(err) ->
      res.UpdateCategoryResponseInternalServerError(errors.internal(err))
  }
}

pub fn delete(
  conn: sqlight.Connection,
  r: req.DeleteCategoryRequest,
) -> res.DeleteCategoryResponse {
  case categories_repo.delete(conn, r.category_id) {
    Ok(Nil) -> res.DeleteCategoryResponseNoContent
    Error(db.ExpectedOneRow) ->
      res.DeleteCategoryResponseNotFound(errors.not_found("Category"))
    Error(err) ->
      res.DeleteCategoryResponseInternalServerError(errors.internal(err))
  }
}
