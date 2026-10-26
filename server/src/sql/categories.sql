-- name: ListRules :many
SELECT id, name, regex, ignore_case, devices
FROM categories
ORDER BY id;

-- name: SaveRule :exec
INSERT OR REPLACE INTO categories (id, name, regex, ignore_case, devices)
VALUES (sqlc.narg(id), sqlc.arg(name), sqlc.arg(regex), sqlc.arg(ignore_case), sqlc.arg(devices));

-- name: DeleteRule :exec
DELETE FROM categories
WHERE id = sqlc.arg(id);
