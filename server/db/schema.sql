PRAGMA foreign_keys = ON;

CREATE TABLE devices (
    id          INTEGER PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    platform    TEXT NOT NULL,
    last_sync   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE categories (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE
);

CREATE TABLE apps (
    id          INTEGER PRIMARY KEY,
    app_id      TEXT NOT NULL UNIQUE,
    title       TEXT NOT NULL,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL
);

CREATE TABLE app_usage (
    id        INTEGER PRIMARY KEY,
    device_id INTEGER NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    app_id    INTEGER NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
    started_at     TEXT NOT NULL,
    ended_at       TEXT NOT NULL,
    CHECK (ended_at >= started_at),
    UNIQUE (device_id, app_id, started_at)
);

CREATE TABLE users (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX idx_usage_device_start ON app_usage(device_id, started_at);
CREATE INDEX idx_usage_app_start    ON app_usage(app_id, started_at);

CREATE TABLE screen_events (
    id          INTEGER PRIMARY KEY,
    device_id   INTEGER NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    ts          INTEGER NOT NULL,
    type        TEXT NOT NULL CHECK (type IN ('screen_on','screen_off','unlock'))
);
CREATE INDEX idx_screen_device_ts ON screen_events(device_id, ts);

CREATE TABLE limits (
    id            INTEGER PRIMARY KEY,
    user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    app_id        INTEGER REFERENCES apps(id) ON DELETE CASCADE,
    category_id   INTEGER REFERENCES categories(id) ON DELETE CASCADE,
    daily_seconds INTEGER NOT NULL CHECK (daily_seconds > 0),
    CHECK ((app_id IS NULL) <> (category_id IS NULL))
);

CREATE TABLE daily_summary (
    device_id     INTEGER NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    app_id        INTEGER NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
    day           TEXT NOT NULL,
    total_seconds INTEGER NOT NULL,
    launches      INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, app_id, day)
);
