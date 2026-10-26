-- Applied on every start, and the schema parrot generates src/server/sql.gleam
-- from (see README.md).

CREATE TABLE IF NOT EXISTS events (
    device      TEXT    NOT NULL,
    kind        TEXT    NOT NULL CHECK (kind IN ('window', 'web')),
    start_ms    INTEGER NOT NULL,
    duration_ms INTEGER NOT NULL CHECK (duration_ms >= 0),
    app         TEXT    NOT NULL,
    title       TEXT    NOT NULL,
    category    TEXT    NOT NULL,
    PRIMARY KEY (device, kind, start_ms)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS events_start ON events(start_ms);
CREATE INDEX IF NOT EXISTS events_app ON events(device, app, title);

-- What a device told about itself on its last upload.
CREATE TABLE IF NOT EXISTS devices (
    name        TEXT    PRIMARY KEY,
    os          TEXT    NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS categories (
    id          INTEGER PRIMARY KEY,
    name        TEXT    NOT NULL,
    regex       TEXT    NOT NULL,
    ignore_case BOOLEAN NOT NULL,
    devices     TEXT    NOT NULL -- JSON array, [] is all devices
);
