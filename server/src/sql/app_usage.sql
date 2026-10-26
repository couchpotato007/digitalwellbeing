-- name: ListAppUsageByDevice :many
SELECT id, device_id, app_id, started_at, ended_at
FROM app_usage
WHERE device_id = sqlc.arg(device_id)
  AND started_at >= sqlc.arg(from_ts)
  AND started_at < sqlc.arg(to_ts)
ORDER BY started_at;

-- name: GetAppUsage :one
SELECT id, device_id, app_id, started_at, ended_at
FROM app_usage
WHERE id = sqlc.arg(id);

-- name: UpsertAppUsage :one
INSERT INTO app_usage (device_id, app_id, started_at, ended_at)
VALUES (
  sqlc.arg(device_id),
  sqlc.arg(app_id),
  sqlc.arg(started_at),
  sqlc.arg(ended_at)
)
ON CONFLICT(device_id, app_id, started_at) DO UPDATE SET ended_at = excluded.ended_at
RETURNING id, device_id, app_id, started_at, ended_at;

-- name: DeleteAppUsage :one
DELETE FROM app_usage
WHERE id = sqlc.arg(id)
RETURNING id;
