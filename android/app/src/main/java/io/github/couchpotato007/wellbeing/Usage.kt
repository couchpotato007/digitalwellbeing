package io.github.couchpotato007.wellbeing

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Process
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Something that happened on the phone, see `shared.Kind` on the server:
 * - `window`: an app in the foreground, `app` is its name and `title` its
 *   package name, so category regexes can match either
 * - `screen`: the screen on, unlocked or not
 * - `unlock`: the phone unlocked, without duration
 * - `notification`: a new notification, without duration, of the app
 * - `audio`: an app playing media
 *
 * `tzOffsetMin` is the phone's UTC offset at the start, so days stay right
 * when it travels.
 */
data class Event(
    val kind: String,
    val startMs: Long,
    val durationMs: Long,
    val app: String,
    val title: String,
    val tzOffsetMin: Int = offsetAt(startMs),
) {
    val endMs get() = startMs + durationMs

    fun toJson(): JSONObject = JSONObject()
        .put("kind", kind)
        .put("start_ms", startMs)
        .put("duration_ms", durationMs)
        .put("app", app)
        .put("title", title)
        .put("tz_offset_min", tzOffsetMin)

    companion object {
        const val WINDOW = "window"
        const val SCREEN = "screen"
        const val UNLOCK = "unlock"
        const val NOTIFICATION = "notification"
        const val AUDIO = "audio"

        fun offsetAt(ms: Long): Int =
            ZoneId.systemDefault().rules.getOffset(Instant.ofEpochMilli(ms)).totalSeconds / 60
    }
}

object Usage {
    /** How far before `from` to look, to know which app was already open then. */
    const val LOOKBACK_MS = 6 * 60 * 60 * 1000L

    /** The kinds [events] finds, the others are reported as they happen. */
    val KINDS = setOf(Event.WINDOW, Event.SCREEN, Event.UNLOCK)

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
     * Packages that can be the home screen, they are what is shown between
     * apps, not an app being used. That is any app with a home activity, the
     * one picked as home too. Not the system's fallback home of the
     * Settings app (negative priority) or the chooser ("android").
     */
    fun launchers(context: Context): Set<String> {
        val pm = context.packageManager
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val all = pm.queryIntentActivities(home, PackageManager.MATCH_ALL)
            .filter { it.priority >= 0 }
            .map { it.activityInfo.packageName }
        val current = pm.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
        return (all + listOfNotNull(current)).toSet() - "android"
    }

    /**
     * Apps in the foreground, the screen being on and unlocks (see [KINDS])
     * that end at or after [fromMs], up to [toMs]. They aren't cut at
     * [fromMs], what was open then starts when it was opened (up to
     * [LOOKBACK_MS] before). Android keeps these events only for a few days.
     * The home screen ends the app before it but isn't an app itself, it
     * still counts as the screen being on.
     */
    fun events(context: Context, fromMs: Long, toMs: Long, launchers: Set<String> = launchers(context)): List<Event> {
        val usm = context.getSystemService(UsageStatsManager::class.java)
        val raw = usm.queryEvents(fromMs - LOOKBACK_MS, toMs)
        val tracker = Tracker()
        val e = UsageEvents.Event()
        while (raw.getNextEvent(e)) tracker.add(e)
        tracker.finish(toMs)

        val labels = Labels(context.packageManager)
        return tracker.events
            .filter { it.endMs >= fromMs }
            .filter { it.kind != Event.WINDOW || it.title !in launchers }
            .map { if (it.kind == Event.WINDOW) it.copy(app = labels[it.title]) else it }
            .sortedBy { it.startMs }
    }

    /**
     * What Android says each app (by package) is, like "game" or "social",
     * from `ApplicationInfo.category`, for the server to sort apps that
     * aren't known there. Apps without one are left out.
     */
    fun appTypes(context: Context, packages: Collection<String>): Map<String, String> {
        val pm = context.packageManager
        return packages.mapNotNull { pkg ->
            val info = try {
                pm.getApplicationInfo(pkg, 0)
            } catch (e: PackageManager.NameNotFoundException) {
                return@mapNotNull null
            }
            val type = when (info.category) {
                ApplicationInfo.CATEGORY_GAME -> "game"
                ApplicationInfo.CATEGORY_AUDIO -> "audio"
                ApplicationInfo.CATEGORY_VIDEO -> "video"
                ApplicationInfo.CATEGORY_IMAGE -> "image"
                ApplicationInfo.CATEGORY_SOCIAL -> "social"
                ApplicationInfo.CATEGORY_NEWS -> "news"
                ApplicationInfo.CATEGORY_MAPS -> "maps"
                ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
                ApplicationInfo.CATEGORY_ACCESSIBILITY -> "accessibility"
                else -> null
            }
            type?.let { pkg to it }
        }.toMap()
    }

    /** Screen time per day for the last [days] days, oldest first, from what this phone stored. */
    fun dailyTotals(context: Context, days: Int): List<Pair<LocalDate, Long>> {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val first = today.minusDays(days - 1L)
        val totals = (0 until days).associate { first.plusDays(it.toLong()) to 0L }.toMutableMap()
        val dayStart = { d: LocalDate -> d.atStartOfDay(zone).toInstant().toEpochMilli() }
        for (event in Store.get(context).events(dayStart(first), kind = Event.WINDOW)) {
            // split stretches that go past midnight
            var start = event.startMs
            while (start < event.endMs) {
                val day = Instant.ofEpochMilli(start).atZone(zone).toLocalDate()
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
        return Store.get(context).events(midnight, kind = Event.WINDOW)
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
     *
     * Also records when the screen was on and when the phone was unlocked.
     * The app name is filled in later, `app` is the package name until then.
     */
    private class Tracker {
        val events = mutableListOf<Event>()
        private var app: String? = null
        private var start = 0L
        private var pausedAt: Long? = null
        private var screenOn = true
        private var locked = false

        /** When the screen turned on, null while it is off or unknown. */
        private var screenSince: Long? = null

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
                    if (screenSince == null) screenSince = t
                    unlocked(t)
                }
                UsageEvents.Event.KEYGUARD_HIDDEN -> {
                    events += Event(Event.UNLOCK, t, 0, "", "")
                    locked = false
                    unlocked(t)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    screenOn = false
                    screenOff(t)
                    close(pausedAt ?: t)
                }
                UsageEvents.Event.KEYGUARD_SHOWN -> {
                    locked = true
                    close(pausedAt ?: t)
                }
                UsageEvents.Event.DEVICE_SHUTDOWN -> {
                    screenOff(t)
                    close(pausedAt ?: t)
                }
            }
        }

        fun finish(now: Long) {
            close(pausedAt ?: now)
            if (screenOn) screenOff(now)
        }

        private fun screenOff(t: Long) {
            screenSince?.let { if (t > it) events += Event(Event.SCREEN, it, t - it, "", "") }
            screenSince = null
        }

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
            if (open != null && end > start) events += Event(Event.WINDOW, start, end - start, open, open)
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
