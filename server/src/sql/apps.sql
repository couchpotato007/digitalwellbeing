-- name: UpsertApp :one
INSERT INTO apps (app_id, title)
VALUES (sqlc.arg(app_id), sqlc.arg(title))
ON CONFLICT(app_id) DO UPDATE SET title = excluded.title
RETURNING id, app_id, title, category_id;

-- name: GetAppByAppId :one
SELECT id, app_id, title, category_id
FROM apps
WHERE app_id = sqlc.arg(app_id);

-- name: ListApps :many
SELECT id, app_id, title, category_id
FROM apps
ORDER BY title;

-- name: SetAppCategory :exec
UPDATE apps
SET category_id = sqlc.narg(category_id)
WHERE id = sqlc.arg(id);
