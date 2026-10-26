-- name: ListScreenEventsByDevice :many
SELECT id, device_id, ts, type
FROM screen_events
WHERE device_id = sqlc.arg(device_id)
  AND ts >= sqlc.arg(from_ts)
  AND ts < sqlc.arg(to_ts)
ORDER BY ts;

-- name: CreateScreenEvent :one
INSERT INTO screen_events (device_id, ts, type)
VALUES (sqlc.arg(device_id), sqlc.arg(ts), sqlc.arg(type))
RETURNING id, device_id, ts, type;

-- name: DeleteScreenEvent :one
DELETE FROM screen_events
WHERE id = sqlc.arg(id)
RETURNING id;
