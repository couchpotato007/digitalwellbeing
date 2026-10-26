-- name: ListApps :many
SELECT id, app_id, title, category_id
FROM apps
ORDER BY title;

-- name: ListAppsByCategory :many
SELECT id, app_id, title, category_id
FROM apps
WHERE category_id = sqlc.arg(category_id)
ORDER BY title;

-- name: GetApp :one
SELECT id, app_id, title, category_id
FROM apps
WHERE id = sqlc.arg(id);

-- name: GetAppByPackageName :one
SELECT id, app_id, title, category_id
FROM apps
WHERE app_id = sqlc.arg(package_name);

-- name: UpsertApp :one
INSERT INTO apps (app_id, title)
VALUES (sqlc.arg(package_name), sqlc.arg(title))
ON CONFLICT(app_id) DO UPDATE SET title = excluded.title
RETURNING id, app_id, title, category_id;

-- name: UpdateApp :one
UPDATE apps
SET title = sqlc.arg(title),
    category_id = sqlc.narg(category_id)
WHERE id = sqlc.arg(id)
RETURNING id, app_id, title, category_id;

-- name: DeleteApp :one
DELETE FROM apps
WHERE id = sqlc.arg(id)
RETURNING id;
