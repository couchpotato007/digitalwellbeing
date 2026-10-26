-- name: Cursor :one
SELECT CAST(coalesce(max(start_ms + duration_ms), 0) AS INTEGER) AS cursor_ms
FROM events
WHERE device = sqlc.arg(device);

-- name: DeleteEventsFrom :exec
DELETE FROM events
WHERE device = sqlc.arg(device) AND start_ms >= sqlc.arg(from_ms);

-- name: CutEventsAt :exec
UPDATE events SET duration_ms = sqlc.arg(from_ms) - start_ms
WHERE device = sqlc.arg(device) AND start_ms + duration_ms > sqlc.arg(from_ms);

-- name: InsertEvent :exec
INSERT OR REPLACE INTO events (device, kind, start_ms, duration_ms, app, title, category)
VALUES (?, ?, ?, ?, ?, ?, ?);

-- name: EventCategories :many
SELECT DISTINCT device, app, title, category
FROM events;

-- name: SetCategory :exec
UPDATE events SET category = sqlc.arg(category)
WHERE device = sqlc.arg(device) AND app = sqlc.arg(app) AND title = sqlc.arg(title);

-- name: DeviceNames :many
SELECT DISTINCT device
FROM events
ORDER BY device;
