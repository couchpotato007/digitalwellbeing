-- name: CreateScreenEvent :one
INSERT INTO screen_events (device_id, ts, type)
VALUES (sqlc.arg(device_id), sqlc.arg(ts), sqlc.arg(type))
RETURNING id, device_id, ts, type;

-- name: ListScreenEventsByDeviceAndDay :many
SELECT id, device_id, ts, type
FROM screen_events
WHERE device_id = sqlc.arg(device_id)
  AND ts >= sqlc.arg(day_start)
  AND ts < sqlc.arg(day_end)
ORDER BY ts;
