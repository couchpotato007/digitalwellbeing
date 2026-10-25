-- name: CreateCategory :one
INSERT INTO categories (name)
VALUES (sqlc.arg(name))
ON CONFLICT(name) DO UPDATE SET name = excluded.name
RETURNING id, name;

-- name: ListCategories :many
SELECT id, name
FROM categories
ORDER BY name;
