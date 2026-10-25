-- name: CreateUser :one
INSERT INTO users (name)
VALUES (sqlc.arg(name))
RETURNING id, name, created_at, updated_at;

-- name: GetUser :one
SELECT id, name, created_at, updated_at
FROM users
WHERE id = sqlc.arg(id);
