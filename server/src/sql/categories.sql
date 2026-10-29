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

-- Screen time since `since_ms` per device, app, title and site, to show
-- what is in which category and what a rule would match.
-- name: RecentUsage :many
SELECT device, app, title, site, CAST(sum(duration_ms) AS INTEGER) AS ms
FROM events
WHERE kind = 'window' AND start_ms >= sqlc.arg(since_ms)
GROUP BY device, app, title, site;

-- name: ListCategoryDefs :many
SELECT name, rating, builtin
FROM category_defs
ORDER BY id;

-- Adds a category, or changes its rating.
-- name: SaveCategoryDef :exec
INSERT INTO category_defs (name, rating, builtin)
VALUES (sqlc.arg(name), sqlc.arg(rating), sqlc.arg(builtin))
ON CONFLICT (name) DO UPDATE SET rating = excluded.rating;

-- name: RenameCategoryDef :exec
UPDATE category_defs SET name = sqlc.arg(new_name)
WHERE name = sqlc.arg(old_name);

-- name: RenameCategoryRules :exec
UPDATE categories SET name = sqlc.arg(new_name)
WHERE name = sqlc.arg(old_name);

-- name: RenameCategoryAssigned :exec
UPDATE assigned_apps SET category = sqlc.arg(new_name)
WHERE category = sqlc.arg(old_name);

-- name: DeleteCategoryDef :exec
DELETE FROM category_defs
WHERE name = sqlc.arg(name);

-- name: DeleteCategoryRules :exec
DELETE FROM categories
WHERE name = sqlc.arg(name);

-- name: DeleteCategoryAssigned :exec
DELETE FROM assigned_apps
WHERE category = sqlc.arg(name);

-- name: ListAssigned :many
SELECT app, category
FROM assigned_apps;

-- name: Assign :exec
INSERT INTO assigned_apps (app, category)
VALUES (sqlc.arg(app), sqlc.arg(category))
ON CONFLICT (app) DO UPDATE SET category = excluded.category;

-- name: Unassign :exec
DELETE FROM assigned_apps
WHERE app = sqlc.arg(app);

-- name: ListAppTypes :many
SELECT app, type
FROM app_types;

-- name: SetAppType :exec
INSERT INTO app_types (app, type)
VALUES (sqlc.arg(app), sqlc.arg(type))
ON CONFLICT (app) DO UPDATE SET type = excluded.type;
