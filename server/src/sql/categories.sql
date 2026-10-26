-- name: ListCategories :many
SELECT id, name
FROM categories
ORDER BY name;

-- name: GetCategory :one
SELECT id, name
FROM categories
WHERE id = sqlc.arg(id);

-- name: CreateCategory :one
INSERT INTO categories (name)
VALUES (sqlc.arg(name))
RETURNING id, name;

-- name: UpdateCategory :one
UPDATE categories
SET name = sqlc.arg(name)
WHERE id = sqlc.arg(id)
RETURNING id, name;

-- name: DeleteCategory :one
DELETE FROM categories
WHERE id = sqlc.arg(id)
RETURNING id;
