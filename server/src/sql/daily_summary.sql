-- name: ListDailySummariesByDevice :many
SELECT device_id, app_id, day, total_seconds, launches
FROM daily_summary
WHERE device_id = sqlc.arg(device_id)
  AND day >= sqlc.arg(from_day)
  AND day <= sqlc.arg(to_day)
ORDER BY day, app_id;

-- name: UpsertDailySummary :one
INSERT INTO daily_summary (device_id, app_id, day, total_seconds, launches)
VALUES (
  sqlc.arg(device_id),
  sqlc.arg(app_id),
  sqlc.arg(day),
  sqlc.arg(total_seconds),
  sqlc.arg(launches)
)
ON CONFLICT(device_id, app_id, day)
DO UPDATE SET
  total_seconds = excluded.total_seconds,
  launches = excluded.launches
RETURNING device_id, app_id, day, total_seconds, launches;
