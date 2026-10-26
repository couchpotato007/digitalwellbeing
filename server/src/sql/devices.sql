-- name: ListDevicesByUser :many
SELECT id, user_id, name, platform, last_sync
FROM devices
WHERE user_id = sqlc.arg(user_id)
ORDER BY name;

-- name: GetDevice :one
SELECT id, user_id, name, platform, last_sync
FROM devices
WHERE id = sqlc.arg(id);

-- name: CreateDevice :one
INSERT INTO devices (user_id, name, platform)
VALUES (sqlc.arg(user_id), sqlc.arg(name), sqlc.arg(platform))
RETURNING id, user_id, name, platform, last_sync;

-- name: UpdateDevice :one
UPDATE devices
SET name = sqlc.arg(name),
    platform = sqlc.arg(platform)
WHERE id = sqlc.arg(id)
RETURNING id, user_id, name, platform, last_sync;

-- name: TouchDeviceLastSync :exec
UPDATE devices
SET last_sync = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(id);

-- name: DeleteDevice :one
DELETE FROM devices
WHERE id = sqlc.arg(id)
RETURNING id;
