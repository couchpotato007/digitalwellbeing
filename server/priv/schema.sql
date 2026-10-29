-- Applied on every start, and the schema parrot generates src/server/sql.gleam
-- from (see README.md). Changes to existing tables also need a step in
-- db.migrate.

-- `kind` is one of shared.Kind. `tz_offset_min` is the device's UTC offset
-- then, NULL from agents that don't send it. `site` is the website of a
-- piece of a browser window (they are split where the tab changes), '' for
-- everything else.
CREATE TABLE IF NOT EXISTS events (
    device        TEXT    NOT NULL,
    kind          TEXT    NOT NULL CHECK (kind IN ('window', 'web', 'screen', 'unlock', 'notification', 'audio')),
    start_ms      INTEGER NOT NULL,
    duration_ms   INTEGER NOT NULL CHECK (duration_ms >= 0),
    app           TEXT    NOT NULL,
    title         TEXT    NOT NULL,
    category      TEXT    NOT NULL,
    tz_offset_min INTEGER,
    site          TEXT    NOT NULL DEFAULT '',
    PRIMARY KEY (device, kind, start_ms)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS events_start ON events(start_ms);
CREATE INDEX IF NOT EXISTS events_app ON events(device, app, title);

-- What a device told about itself on its last upload, and when that was.
CREATE TABLE IF NOT EXISTS devices (
    name           TEXT    PRIMARY KEY,
    os             TEXT    NOT NULL,
    last_upload_ms INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;

-- The categories, in the order of their colors. `builtin` is the name a
-- built-in one started with, its known apps follow it (categories.catalog).
CREATE TABLE IF NOT EXISTS category_defs (
    id          INTEGER PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE,
    rating      TEXT    NOT NULL CHECK (rating IN ('productive', 'neutral', 'distracting')),
    builtin     TEXT    NOT NULL DEFAULT ''
);

-- Apps and websites assigned to a category by hand.
CREATE TABLE IF NOT EXISTS assigned_apps (
    app         TEXT    PRIMARY KEY COLLATE NOCASE,
    category    TEXT    NOT NULL
) WITHOUT ROWID;

-- What phones say their apps are, like 'game' or 'social'.
CREATE TABLE IF NOT EXISTS app_types (
    app         TEXT    PRIMARY KEY COLLATE NOCASE,
    type        TEXT    NOT NULL
) WITHOUT ROWID;

-- The advanced rules: a regex on the app and title puts events into the
-- category `name`.
CREATE TABLE IF NOT EXISTS categories (
    id          INTEGER PRIMARY KEY,
    name        TEXT    NOT NULL,
    regex       TEXT    NOT NULL,
    ignore_case BOOLEAN NOT NULL,
    devices     TEXT    NOT NULL -- JSON array, [] is all devices
);
