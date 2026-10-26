-- name: ListRules :many
SELECT id, name, regex, ignore_case, devices
FROM categories
ORDER BY id;

-- name: SaveRule :exec
INSERT OR REPLACE INTO categories (id, name, regex, ignore_case, devices)
VALUES (sqlc.narg(id), sqlc.arg(name), sqlc.arg(regex), sqlc.arg(ignore_case), sqlc.arg(devices));

-- name: DeleteRule :exec
DELETE FROM categories
WHERE id = sqlc.arg(id);

-- Screen time per category since `since_ms`, for the categories list.
-- name: CategoryTotals :many
SELECT category AS name, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms)
GROUP BY category;

-- Everything used since `since_ms`, to show what a pattern would match.
-- name: RecentUsage :many
SELECT device, kind, app, title, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE start_ms >= sqlc.arg(since_ms)
GROUP BY device, kind, app, title;
