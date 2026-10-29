-- What the insights are computed from, see insights.gleam. Like the
-- dashboard, local times are the server's.

-- Everything that happened from `since_ms` to `until_ms`, of one device or
-- all devices if `device` is '', by start.
-- name: Activity :many
SELECT device, kind, app, category, start_ms,
  CAST(start_ms + duration_ms AS INTEGER) AS end_ms,
  CAST(date(start_ms / 1000, 'unixepoch', 'localtime') AS TEXT) AS date,
  CAST(strftime('%H', start_ms / 1000, 'unixepoch', 'localtime') AS INTEGER) AS hour,
  CAST(strftime('%H:%M', start_ms / 1000, 'unixepoch', 'localtime') AS TEXT) AS time
FROM events
WHERE start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
ORDER BY start_ms;

-- Screen time from `since_ms` to `until_ms`, to compare with what is usual.
-- name: ScreenIntervals :many
SELECT start_ms, CAST(start_ms + duration_ms AS INTEGER) AS end_ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
ORDER BY start_ms;

-- Screen time per local date, hour (when it started) and category.
-- name: DailyCategories :many
SELECT CAST(date(start_ms / 1000, 'unixepoch', 'localtime') AS TEXT) AS date,
  CAST(strftime('%H', start_ms / 1000, 'unixepoch', 'localtime') AS INTEGER) AS hour,
  category, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY 1, 2, 3;

-- Screen time per local date, hour (when it started) and app.
-- name: DailyApps :many
SELECT CAST(date(start_ms / 1000, 'unixepoch', 'localtime') AS TEXT) AS date,
  CAST(strftime('%H', start_ms / 1000, 'unixepoch', 'localtime') AS INTEGER) AS hour,
  app, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY 1, 2, 3;
