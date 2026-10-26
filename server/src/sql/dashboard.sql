-- The dashboard shows the last `days` days (1 is today) of one device, or of
-- all devices if `device` is ''. Days are in the server's local time.

-- name: Since :one
SELECT CAST(unixepoch('now', 'localtime', 'start of day', printf('-%d days', CAST(sqlc.arg(days) AS INTEGER) - 1), 'utc') * 1000 AS INTEGER) AS since_ms;

-- name: Days :many
WITH RECURSIVE day(date) AS (
  SELECT date('now', 'localtime', printf('-%d days', CAST(sqlc.arg(days) AS INTEGER) - 1))
  UNION ALL
  SELECT date(date, '+1 day') FROM day WHERE date < date('now', 'localtime')
)
SELECT CAST(date AS TEXT) AS date FROM day;

-- Screen time, `bucket` is the local hour "07" for today, otherwise the date.
-- name: ScreenTime :many
SELECT
  CAST(CASE WHEN CAST(sqlc.arg(days) AS INTEGER) = 1
    THEN strftime('%H', start_ms / 1000, 'unixepoch', 'localtime')
    ELSE date(start_ms / 1000, 'unixepoch', 'localtime')
  END AS TEXT) AS bucket,
  start_ms,
  CAST(start_ms + duration_ms AS INTEGER) AS end_ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
ORDER BY start_ms;

-- Usage per device, `detail` is when it was last active (local time).
-- name: TopDevices :many
SELECT device AS name,
  CAST(datetime(max(start_ms + duration_ms) / 1000, 'unixepoch', 'localtime') AS TEXT) AS detail,
  CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms)
GROUP BY device ORDER BY ms DESC LIMIT 15;

-- name: TopCategories :many
SELECT category AS name, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY category ORDER BY ms DESC LIMIT 15;

-- name: TopApps :many
SELECT app AS name,
  CAST(group_concat(DISTINCT device) AS TEXT) AS detail,
  CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = sqlc.arg(kind) AND start_ms >= sqlc.arg(since_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY app ORDER BY ms DESC LIMIT 15;

-- name: TopTitles :many
SELECT title AS name, app AS detail, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY title ORDER BY ms DESC LIMIT 15;

-- What took the most time without a category, to write rules for.
-- name: UncategorizedApps :many
SELECT app AS name,
  CAST(group_concat(DISTINCT device) AS TEXT) AS detail,
  CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE category = 'Uncategorized' AND start_ms >= sqlc.arg(since_ms)
GROUP BY app ORDER BY ms DESC LIMIT 15;

-- name: UncategorizedTitles :many
SELECT title AS name, app AS detail, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE category = 'Uncategorized' AND kind = 'window' AND start_ms >= sqlc.arg(since_ms)
GROUP BY title ORDER BY ms DESC LIMIT 15;
