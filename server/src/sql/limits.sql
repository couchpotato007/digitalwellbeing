-- name: CreateLimit :one
INSERT INTO limits (user_id, app_id, category_id, daily_seconds)
VALUES (
  sqlc.arg(user_id),
  sqlc.narg(app_id),
  sqlc.narg(category_id),
  sqlc.arg(daily_seconds)
)
RETURNING id, user_id, app_id, category_id, daily_seconds;

-- name: ListLimitsByUser :many
SELECT id, user_id, app_id, category_id, daily_seconds
FROM limits
WHERE user_id = sqlc.arg(user_id);

-- name: DeleteLimit :exec
DELETE FROM limits
WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id);
