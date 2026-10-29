-- The dashboard shows the `days` days up to and including `date` of one
-- device, or of all devices if `device` is ''. Days are in the server's local
-- time. An invalid `date` is today.

-- name: Range :one
SELECT
  CAST(date AS TEXT) AS date,
  CAST(date(date, printf('-%d days', n - 1)) AS TEXT) AS first_date,
  CAST(unixepoch(date, printf('-%d days', n - 1), 'utc') * 1000 AS INTEGER) AS since_ms,
  CAST(unixepoch(date, '+1 day', 'utc') * 1000 AS INTEGER) AS until_ms,
  CAST(unixepoch(date, printf('-%d days', 2 * n - 1), 'utc') * 1000 AS INTEGER) AS previous_since_ms,
  CAST(date(date, printf('-%d days', n)) AS TEXT) AS previous_date,
  CAST(date(date, printf('+%d days', n)) AS TEXT) AS next_date,
  CAST(date('now', 'localtime') AS TEXT) AS today,
  CAST(unixepoch('subsec') * 1000 AS INTEGER) AS now_ms
FROM (
  SELECT coalesce(date(CAST(sqlc.arg(date) AS TEXT)), date('now', 'localtime')) AS date,
    CAST(sqlc.arg(days) AS INTEGER) AS n
);

-- `weekday` is 0 for Sunday to 6 for Saturday.
-- name: Days :many
WITH RECURSIVE day(date) AS (
  SELECT date(CAST(sqlc.arg(first_date) AS TEXT))
  UNION ALL
  SELECT date(date, '+1 day') FROM day WHERE date < CAST(sqlc.arg(last_date) AS TEXT)
)
SELECT CAST(date AS TEXT) AS date,
  CAST(strftime('%w', date) AS INTEGER) AS weekday,
  CAST(unixepoch(date, 'utc') * 1000 AS INTEGER) AS start_ms,
  CAST(unixepoch(date, '+1 day', 'utc') * 1000 AS INTEGER) AS end_ms
FROM day;

-- Every stretch of screen time in the range, also those that started up to a
-- day before and go into it, with its local date and hour.
-- name: ScreenTime :many
SELECT device, category,
  CAST(date(start_ms / 1000, 'unixepoch', 'localtime') AS TEXT) AS date,
  CAST(strftime('%H', start_ms / 1000, 'unixepoch', 'localtime') AS TEXT) AS hour,
  CAST(strftime('%H:%M', start_ms / 1000, 'unixepoch', 'localtime') AS TEXT) AS start_time,
  CAST(strftime('%H:%M', (start_ms + duration_ms) / 1000, 'unixepoch', 'localtime') AS TEXT) AS end_time,
  start_ms,
  CAST(start_ms + duration_ms AS INTEGER) AS end_ms
FROM events
WHERE kind = 'window' AND start_ms >= CAST(sqlc.arg(since_ms) AS INTEGER) - 86400000 AND start_ms < sqlc.arg(until_ms)
  AND start_ms + duration_ms > CAST(sqlc.arg(since_ms) AS INTEGER)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
ORDER BY start_ms;

-- Usage per device, `detail` is when it was last active (local time).
-- name: TopDevices :many
SELECT device AS name,
  CAST(datetime(max(start_ms + duration_ms) / 1000, 'unixepoch', 'localtime') AS TEXT) AS detail,
  CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
GROUP BY device ORDER BY ms DESC LIMIT 15;

-- name: TopCategories :many
SELECT category AS name, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY category ORDER BY ms DESC LIMIT 15;

-- name: TopApps :many
SELECT app AS name,
  CAST(group_concat(DISTINCT device) AS TEXT) AS detail,
  CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = sqlc.arg(kind) AND start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY app ORDER BY ms DESC LIMIT 15;

-- name: TopTitles :many
SELECT title AS name, app AS detail, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms) AND start_ms < sqlc.arg(until_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY title ORDER BY ms DESC LIMIT 15;

-- What took the most time without a category, to write rules for.
-- name: UncategorizedApps :many
SELECT app AS name,
  CAST(group_concat(DISTINCT device) AS TEXT) AS detail,
  CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE category = 'Uncategorized' AND kind IN ('window', 'web') AND start_ms >= sqlc.arg(since_ms)
GROUP BY app ORDER BY ms DESC LIMIT 15;

-- name: UncategorizedTitles :many
SELECT title AS name, app AS detail, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE category = 'Uncategorized' AND kind = 'window' AND start_ms >= sqlc.arg(since_ms)
GROUP BY title ORDER BY ms DESC LIMIT 15;

-- What made up a block of the activity view: the screen time of a category
-- from `since_ms` to `until_ms`, cut to that time.
-- name: BlockApps :many
SELECT app AS name,
  CAST(group_concat(DISTINCT device) AS TEXT) AS detail,
  CAST(sum(min(start_ms + duration_ms, CAST(sqlc.arg(until_ms) AS INTEGER)) - max(start_ms, CAST(sqlc.arg(since_ms) AS INTEGER))) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND category = sqlc.arg(category)
  AND start_ms < sqlc.arg(until_ms) AND start_ms + duration_ms > sqlc.arg(since_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY app ORDER BY ms DESC LIMIT 15;

-- name: BlockTitles :many
SELECT title AS name, app AS detail,
  CAST(sum(min(start_ms + duration_ms, CAST(sqlc.arg(until_ms) AS INTEGER)) - max(start_ms, CAST(sqlc.arg(since_ms) AS INTEGER))) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND category = sqlc.arg(category)
  AND start_ms < sqlc.arg(until_ms) AND start_ms + duration_ms > sqlc.arg(since_ms)
  AND (CAST(sqlc.arg(device) AS TEXT) = '' OR device = sqlc.arg(device))
GROUP BY title ORDER BY ms DESC LIMIT 15;
