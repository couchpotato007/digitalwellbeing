-- name: CreateDevice :one
INSERT INTO devices (user_id, name, platform)
VALUES (sqlc.arg(user_id), sqlc.arg(name), sqlc.arg(platform))
RETURNING id, user_id, name, platform, last_sync;

-- name: GetDevice :one
SELECT id, user_id, name, platform, last_sync
FROM devices
WHERE id = sqlc.arg(id);

-- name: ListDevicesByUser :many
SELECT id, user_id, name, platform, last_sync
FROM devices
WHERE user_id = sqlc.arg(user_id)
ORDER BY name;

-- name: UpdateDeviceLastSync :exec
UPDATE devices
SET last_sync = sqlc.arg(last_sync)
WHERE id = sqlc.arg(id);
