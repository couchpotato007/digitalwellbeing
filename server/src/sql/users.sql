-- name: ListUsers :many
SELECT id, name, created_at, updated_at
FROM users
ORDER BY id;

-- name: GetUser :one
SELECT id, name, created_at, updated_at
FROM users
WHERE id = sqlc.arg(id);

-- name: CreateUser :one
INSERT INTO users (name)
VALUES (sqlc.arg(name))
RETURNING id, name, created_at, updated_at;

-- name: UpdateUser :one
UPDATE users
SET name = sqlc.arg(name),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(id)
RETURNING id, name, created_at, updated_at;

-- name: DeleteUser :one
DELETE FROM users
WHERE id = sqlc.arg(id)
RETURNING id;
