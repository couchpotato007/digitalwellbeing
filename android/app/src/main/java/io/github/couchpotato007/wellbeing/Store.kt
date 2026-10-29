package io.github.couchpotato007.wellbeing

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * Everything collected on this phone, kept until long after it is uploaded.
 * The server is only reachable now and then (e.g. behind a VPN at home), so
 * collecting doesn't wait for it: Android forgets its usage events after
 * about a week, this doesn't.
 *
 * `pending_from_ms` is the start of the oldest event that changed since the
 * last upload, the next upload sends everything from there on.
 */
class Store private constructor(context: Context) :
    SQLiteOpenHelper(context, "events.db", null, 1) {

    companion object {
        @Volatile
        private var instance: Store? = null

        /** One per process, the notification listener and the workers share it. */
        fun get(context: Context): Store = instance ?: synchronized(this) {
            instance ?: Store(context.applicationContext).also { instance = it }
        }

        /** How long events are kept on the phone. */
        const val KEEP_DAYS = 400L
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE events (
                kind          TEXT    NOT NULL,
                start_ms      INTEGER NOT NULL,
                duration_ms   INTEGER NOT NULL,
                app           TEXT    NOT NULL,
                title         TEXT    NOT NULL,
                tz_offset_min INTEGER NOT NULL,
                PRIMARY KEY (kind, start_ms)
            ) WITHOUT ROWID
            """
        )
        db.execSQL("CREATE TABLE state (key TEXT PRIMARY KEY, value INTEGER NOT NULL) WITHOUT ROWID")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    /**
     * Replaces the events of [kinds] that end at or after [fromMs] and start
     * at or after [notBeforeMs] with [events]. Events aren't cut at [fromMs],
     * so an app that is still open stays one event while it grows.
     */
    @Synchronized
    fun replace(kinds: Set<String>, notBeforeMs: Long, fromMs: Long, events: List<Event>) {
        val db = writableDatabase
        val marks = kinds.joinToString(",") { "?" }
        val where = "kind IN ($marks) AND start_ms >= ? AND start_ms + duration_ms >= ?"
        val args = kinds.toTypedArray() + notBeforeMs.toString() + fromMs.toString()
        db.beginTransaction()
        try {
            val oldest = db.rawQuery("SELECT min(start_ms) FROM events WHERE $where", args).use {
                if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else Long.MAX_VALUE
            }
            db.delete("events", where, args)
            events.forEach { db.insertWithOnConflict("events", null, it.values(), SQLiteDatabase.CONFLICT_REPLACE) }
            markPending(db, minOf(oldest, events.minOfOrNull { it.startMs } ?: Long.MAX_VALUE))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /**
     * Adds an event that is reported as it happens (a notification) or
     * changes one with the same kind and start (media playing longer).
     * Returns the start it got: events of one kind need different starts.
     */
    @Synchronized
    fun put(event: Event, replace: Boolean = false): Long {
        val db = writableDatabase
        db.beginTransaction()
        try {
            var start = event.startMs
            if (replace) {
                db.insertWithOnConflict("events", null, event.values(), SQLiteDatabase.CONFLICT_REPLACE)
            } else {
                while (db.insertWithOnConflict(
                        "events", null, event.copy(startMs = start).values(), SQLiteDatabase.CONFLICT_IGNORE,
                    ) == -1L
                ) start++
            }
            markPending(db, start)
            db.setTransactionSuccessful()
            return start
        } finally {
            db.endTransaction()
        }
    }

    private fun markPending(db: SQLiteDatabase, startMs: Long) {
        if (startMs == Long.MAX_VALUE) return
        db.execSQL(
            "INSERT INTO state VALUES ('pending_from_ms', ?) " +
                "ON CONFLICT (key) DO UPDATE SET value = min(value, excluded.value)",
            arrayOf(startMs),
        )
    }

    /**
     * Takes the start of the oldest change since the last upload,
     * `Long.MAX_VALUE` for none. Changes from now on are pending again, give
     * it back with [restorePending] if the upload fails.
     */
    @Synchronized
    fun takePending(): Long {
        val value = getState("pending_from_ms") ?: Long.MAX_VALUE
        writableDatabase.delete("state", "key = 'pending_from_ms'", null)
        return value
    }

    @Synchronized
    fun restorePending(fromMs: Long) = markPending(writableDatabase, fromMs)

    /**
     * [fromMs], or the start of a stored event that goes over it, so an
     * upload from there doesn't cut an event in two.
     */
    fun boundary(fromMs: Long): Long {
        var from = fromMs
        while (true) {
            val earlier = readableDatabase.rawQuery(
                "SELECT min(start_ms) FROM events WHERE start_ms < ? AND start_ms + duration_ms > ?",
                arrayOf(from.toString(), from.toString()),
            ).use { if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null } ?: return from
            from = earlier
        }
    }

    /** Events starting from [fromMs] to [toMs], of [kind] or all kinds, by start. */
    fun events(fromMs: Long, toMs: Long = Long.MAX_VALUE, kind: String? = null): List<Event> {
        val where = "start_ms >= ? AND start_ms < ?" + if (kind != null) " AND kind = ?" else ""
        val args = listOfNotNull(fromMs.toString(), toMs.toString(), kind).toTypedArray()
        return readableDatabase.query(
            "events",
            arrayOf("kind", "start_ms", "duration_ms", "app", "title", "tz_offset_min"),
            where, args, null, null, "start_ms",
        ).use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(Event(c.getString(0), c.getLong(1), c.getLong(2), c.getString(3), c.getString(4), c.getInt(5)))
                }
            }
        }
    }

    /** Removes the app events of [packages], everything from the oldest is uploaded again. */
    @Synchronized
    fun removeApps(packages: Set<String>) {
        if (packages.isEmpty()) return
        val db = writableDatabase
        val marks = packages.joinToString(",") { "?" }
        val where = "kind = 'window' AND title IN ($marks)"
        val args = packages.toTypedArray()
        db.beginTransaction()
        try {
            val oldest = db.rawQuery("SELECT min(start_ms) FROM events WHERE $where", args).use {
                if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else Long.MAX_VALUE
            }
            db.delete("events", where, args)
            markPending(db, oldest)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Number of events and the start of the oldest, for the settings. */
    fun summary(): Pair<Long, Long?> =
        readableDatabase.rawQuery("SELECT count(*), min(start_ms) FROM events", null).use {
            it.moveToFirst()
            it.getLong(0) to if (it.isNull(1)) null else it.getLong(1)
        }

    fun getState(key: String): Long? =
        readableDatabase.rawQuery("SELECT value FROM state WHERE key = ?", arrayOf(key)).use {
            if (it.moveToFirst()) it.getLong(0) else null
        }

    @Synchronized
    fun setState(key: String, value: Long) {
        writableDatabase.insertWithOnConflict(
            "state", null,
            ContentValues().apply { put("key", key); put("value", value) },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    /** Forgets events that started before [beforeMs]. */
    @Synchronized
    fun prune(beforeMs: Long) {
        writableDatabase.delete("events", "start_ms < ?", arrayOf(beforeMs.toString()))
    }

    private fun Event.values() = ContentValues().apply {
        put("kind", kind)
        put("start_ms", startMs)
        put("duration_ms", durationMs)
        put("app", app)
        put("title", title)
        put("tz_offset_min", tzOffsetMin)
    }
}
