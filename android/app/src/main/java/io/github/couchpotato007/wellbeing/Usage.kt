package io.github.couchpotato007.wellbeing

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Process
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId

/**
 * One stretch of time an app was in the foreground, like the agent's `Window`
 * events: `app` is the app's name, `title` its package name, so category
 * regexes on the server can match either.
 */
data class Event(val startMs: Long, val durationMs: Long, val app: String, val title: String) {
    val endMs get() = startMs + durationMs

    fun toJson(): JSONObject = JSONObject()
        .put("kind", "window")
        .put("start_ms", startMs)
        .put("duration_ms", durationMs)
        .put("app", app)
        .put("title", title)
}

object Usage {
    /** How far before `from` to look, to know which app was already open then. */
    private const val LOOKBACK_MS = 6 * 60 * 60 * 1000L

    /** Switching activities within an app pauses it for a moment, that stays one stretch. */
    private const val MERGE_MS = 2_000L

    private const val DREAM_ACTIVITY = "android.service.dreams.DreamActivity"

    fun hasAccess(context: Context): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java)
        val mode = ops.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Foreground app events between [fromMs] and [toMs], cut to that range.
     * Android keeps these events only for a few days.
     */
    fun events(context: Context, fromMs: Long, toMs: Long): List<Event> {
        val usm = context.getSystemService(UsageStatsManager::class.java)
        val raw = usm.queryEvents(fromMs - LOOKBACK_MS, toMs)
        val tracker = Tracker()
        val e = UsageEvents.Event()
        while (raw.getNextEvent(e)) tracker.add(e)
        tracker.finish(toMs)

        val labels = Labels(context.packageManager)
        return tracker.stretches.mapNotNull { (pkg, start, end) ->
            val clipped = maxOf(start, fromMs)
            if (end <= clipped) null
            else Event(clipped, end - clipped, labels[pkg], pkg)
        }
    }

    /** Screen time per day for the last [days] days, oldest first. */
    fun dailyTotals(context: Context, days: Int): List<Pair<LocalDate, Long>> {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val first = today.minusDays(days - 1L)
        val totals = (0 until days).associate { first.plusDays(it.toLong()) to 0L }.toMutableMap()
        val dayStart = { d: LocalDate -> d.atStartOfDay(zone).toInstant().toEpochMilli() }
        for (event in events(context, dayStart(first), System.currentTimeMillis())) {
            // split stretches that go past midnight
            var start = event.startMs
            while (start < event.endMs) {
                val day = java.time.Instant.ofEpochMilli(start).atZone(zone).toLocalDate()
                val end = minOf(event.endMs, dayStart(day.plusDays(1)))
                totals[day] = (totals[day] ?: 0L) + (end - start)
                start = end
            }
        }
        return totals.toList().sortedBy { it.first }
    }

    /** The apps used most today, with their time. */
    fun topAppsToday(context: Context, count: Int): List<Pair<String, Long>> {
        val midnight = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        return events(context, midnight, System.currentTimeMillis())
            .groupBy { it.app }
            .mapValues { (_, events) -> events.sumOf { it.durationMs } }
            .toList()
            .sortedByDescending { it.second }
            .take(count)
    }

    /**
     * Turns resume/pause events into stretches of one app being in the
     * foreground. Only time with the screen on and unlocked counts: when the
     * screen turns off, the always-on display starts as an activity of System
     * UI, which would otherwise count until the next app is opened.
     */
    private class Tracker {
        val stretches = mutableListOf<Triple<String, Long, Long>>()
        private var app: String? = null
        private var start = 0L
        private var pausedAt: Long? = null
        private var screenOn = true
        private var locked = false

        /** The app resumed while locked. It counts from the unlock, it resumes before that. */
        private var behindLock: String? = null

        private val usable get() = screenOn && !locked

        fun add(e: UsageEvents.Event) {
            val t = e.timeStamp
            pausedAt?.let { if (t - it > MERGE_MS) close(it) }
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> when {
                    // the always-on display and screensavers
                    e.className == DREAM_ACTIVITY -> {}
                    usable -> open(e.packageName, t)
                    else -> behindLock = e.packageName
                }
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> {
                    if (e.packageName == behindLock) behindLock = null
                    if (e.packageName == app && pausedAt == null) pausedAt = t
                }
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    screenOn = true
                    unlocked(t)
                }
                UsageEvents.Event.KEYGUARD_HIDDEN -> {
                    locked = false
                    unlocked(t)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    screenOn = false
                    close(pausedAt ?: t)
                }
                UsageEvents.Event.KEYGUARD_SHOWN -> {
                    locked = true
                    close(pausedAt ?: t)
                }
                UsageEvents.Event.DEVICE_SHUTDOWN -> close(pausedAt ?: t)
            }
        }

        fun finish(now: Long) = close(pausedAt ?: now)

        private fun open(pkg: String, t: Long) {
            if (pkg != app) {
                close(pausedAt ?: t)
                app = pkg
                start = t
            }
            pausedAt = null
            behindLock = null
        }

        private fun unlocked(t: Long) {
            val pkg = behindLock
            if (usable && pkg != null) open(pkg, t)
        }

        private fun close(end: Long) {
            val open = app
            if (open != null && end > start) stretches += Triple(open, start, end)
            app = null
            pausedAt = null
        }
    }

    private class Labels(private val pm: PackageManager) {
        private val cache = mutableMapOf<String, String>()

        operator fun get(pkg: String): String = cache.getOrPut(pkg) {
            try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                pkg
            }
        }
    }
}
