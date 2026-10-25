-- name: CreateAppUsage :one
INSERT INTO app_usage (device_id, app_id, started_at, ended_at)
VALUES (
  sqlc.arg(device_id),
  sqlc.arg(app_id),
  sqlc.arg(started_at),
  sqlc.arg(ended_at)
)
RETURNING id, device_id, app_id, started_at, ended_at;

-- name: ListAppUsageByDeviceAndDay :many
SELECT
  u.id,
  u.device_id,
  u.app_id,
  a.app_id AS package_name,
  a.title AS app_title,
  u.started_at,
  u.ended_at
FROM app_usage AS u
JOIN apps AS a ON a.id = u.app_id
WHERE u.device_id = sqlc.arg(device_id)
  AND u.started_at >= sqlc.arg(day_start)
  AND u.started_at < sqlc.arg(day_end)
ORDER BY u.started_at;
