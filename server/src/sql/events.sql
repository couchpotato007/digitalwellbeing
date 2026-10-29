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
INSERT OR REPLACE INTO events (device, kind, start_ms, duration_ms, app, title, category, tz_offset_min, site)
VALUES (?, ?, ?, ?, ?, ?, ?, sqlc.narg(tz_offset_min), sqlc.arg(site));

-- name: EventCategories :many
SELECT DISTINCT device, app, title, site, category
FROM events;

-- name: SetCategory :exec
UPDATE events SET category = sqlc.arg(category)
WHERE device = sqlc.arg(device) AND app = sqlc.arg(app) AND title = sqlc.arg(title)
  AND site = sqlc.arg(site);

-- A device's events of `kind` from `since_ms` on, to split browser windows.
-- name: DeviceEvents :many
SELECT kind, start_ms, duration_ms, app, title, tz_offset_min
FROM events
WHERE device = sqlc.arg(device) AND kind = sqlc.arg(kind) AND start_ms >= sqlc.arg(since_ms)
ORDER BY start_ms;

-- name: DeleteDeviceWindowsFrom :exec
DELETE FROM events
WHERE device = sqlc.arg(device) AND kind = 'window' AND start_ms >= sqlc.arg(since_ms);

-- name: DeviceNames :many
SELECT DISTINCT device
FROM events
ORDER BY device;

-- name: DeleteDevice :exec
DELETE FROM events
WHERE device = sqlc.arg(device);

-- name: DeleteDeviceInfo :exec
DELETE FROM devices
WHERE name = sqlc.arg(device);

-- An empty `os` keeps the one the device sent before.
-- name: DeviceUploaded :exec
INSERT INTO devices (name, os, last_upload_ms)
VALUES (sqlc.arg(device), sqlc.arg(os), CAST(unixepoch('subsec') * 1000 AS INTEGER))
ON CONFLICT (name) DO UPDATE SET
  os = CASE excluded.os WHEN '' THEN devices.os ELSE excluded.os END,
  last_upload_ms = excluded.last_upload_ms;

-- name: DeviceSystems :many
SELECT name, os, last_upload_ms
FROM devices
ORDER BY name;
