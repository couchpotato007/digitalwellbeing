package io.github.couchpotato007.wellbeing

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

/** What the server's dashboard shows, from `GET /api/stats`, see stats.gleam. */
data class Report(
    val date: String,
    val firstDate: String,
    val days: Int,
    val device: String,
    val previousDate: String,
    val nextDate: String,
    val today: String,
    val totalMs: Long,
    val previousMs: Long,
    val sessions: Int,
    val longestSessionMs: Long,
    /** Local time like "07:45", "" if there was no screen time. */
    val firstActive: String,
    val lastActive: String,
    /** Per hour ("07") for one day, otherwise per day ("2026-10-26", detail is the weekday). */
    val timeline: List<UsageItem>,
    /** Per hour of the day, summed over all days. */
    val hours: List<UsageItem>,
    /** Per device for one day, otherwise per day. */
    val strips: List<Strip>,
    /** Top-level categories, the index picks the color, see [categoryColor]. */
    val categoryOrder: List<String>,
    val deviceNames: List<String>,
    /** Operating system per device name, like "NixOS 25.05 (Warbler)", missing if unknown. */
    val deviceOs: Map<String, String>,
    /** Detail is when the device was last active. */
    val devices: List<UsageItem>,
    val categories: List<UsageItem>,
    val apps: List<UsageItem>,
    val titles: List<UsageItem>,
    val domains: List<UsageItem>,
)

data class UsageItem(val name: String, val detail: String, val ms: Long)

/** From `GET /api/insights`, see insights.gleam on the server. */
data class Insights(
    val pickups: Int,
    /** 24 entries, per hour of the day. */
    val pickupHours: List<Int>,
    /** "07:12", for several days the median, "" for none. */
    val firstPickup: String,
    /** Unlocks up to a minute after a notification. */
    val notificationPickups: Int,
    /** The app used first after an unlock. */
    val pickupApps: List<CountItem>,
    val notifications: Int,
    val notificationApps: List<CountItem>,
    val screenOns: Int,
    val shortScreenOns: Int,
    val medianScreenOnMs: Long,
    val audioMs: Long,
    val audioApps: List<UsageItem>,
    /** Screen time by the rating of its category. */
    val productiveMs: Long,
    val neutralMs: Long,
    val distractingMs: Long,
    /** Stretches of 25+ minutes in one productive category. */
    val longStretches: Int,
    val longStretchMs: Long,
    /** Name is the category, detail when ("10:05–11:40"). */
    val longestStretch: UsageItem,
    val longStretchCategories: List<UsageItem>,
    val appSwitches: Int,
    val medianSessionMs: Long,
    val phoneDuringComputerMs: Long,
    val pickupsDuringComputer: Int,
    val total: Comparison,
    /** Earlier periods count only up to the same time of day. */
    val untilNow: Boolean,
    val categories: List<Comparison>,
    val apps: List<Comparison>,
    /** Per day the average of the 7 days up to it, empty for one day. */
    val trend: List<Long>,
    /** Average per weekday (0 Sunday) and hour of the last 4 weeks. */
    val weekHours: List<List<Long>>,
)

data class CountItem(val name: String, val count: Int)

/**
 * [ms] against the median of earlier periods, [score] a robust z-score:
 * beyond ±2 is unusual. Without at least 3 [periods] there is nothing to say.
 */
data class Comparison(val name: String, val ms: Long, val usualMs: Long, val periods: Int, val score: Double)

/** Screen time per app over time, from `GET /api/timeline`, see timeline.gleam. */
data class Timeline(
    /** 15 minutes for a day, hours for a week, days for longer. */
    val buckets: List<Bucket>,
    /** The most used apps, then "Other". A bucket's values add up to its [Bucket.ms]. */
    val series: List<Series>,
    /** For up to 7 days, oldest first. */
    val sessions: List<Session>,
)

/** [label] is the local time ("07:15"), weekday and hour ("Mon 07:00") or date ("10-26"). */
data class Bucket(val startMs: Long, val endMs: Long, val label: String, val ms: Long)

data class Series(val name: String, val totalMs: Long, val values: List<Long>)

/** Screen time without breaks of 5+ minutes, [start] and [end] are local times. */
data class Session(
    val date: String,
    val startMs: Long,
    val endMs: Long,
    val start: String,
    val end: String,
    val activeMs: Long,
    val devices: List<String>,
    val apps: List<UsageItem>,
)

/** A row of the activity view. [date] is set for rows of a day, empty for rows of a device. */
data class Strip(val label: String, val date: String, val startMs: Long, val endMs: Long, val segments: List<Segment>)

/** [device] is "" from servers before segments had one. */
data class Segment(val startMs: Long, val endMs: Long, val device: String, val category: String)

object Stats {
    /** [date] "" is today, [device] "" is all devices. */
    fun load(server: Server, date: String, days: Int, device: String): Report {
        val query = "date=" + encode(date) + "&days=$days&device=" + encode(device)
        val body = Sync.request("GET", server.url.trimEnd('/') + "/api/stats?$query", server.token, null)
        return parse(JSONObject(body))
    }

    /** Like [load], null from servers without insights. */
    fun insights(server: Server, date: String, days: Int, device: String): Insights? {
        val query = "date=" + encode(date) + "&days=$days&device=" + encode(device)
        val body = try {
            Sync.request("GET", server.url.trimEnd('/') + "/api/insights?$query", server.token, null)
        } catch (e: HttpException) {
            if (e.status == 404) return null else throw e
        }
        val o = JSONObject(body)
        val counts = { a: JSONArray -> a.objects().map { CountItem(it.getString("name"), it.getInt("count")) } }
        val comparison = { c: JSONObject ->
            Comparison(c.getString("name"), c.getLong("ms"), c.getLong("usual_ms"), c.getInt("periods"), c.getDouble("score"))
        }
        val longest = o.getJSONObject("longest_stretch")
        return Insights(
            pickups = o.getInt("pickups"),
            pickupHours = o.getJSONArray("pickup_hours").let { a -> (0 until a.length()).map { a.getInt(it) } },
            firstPickup = o.getString("first_pickup"),
            notificationPickups = o.getInt("notification_pickups"),
            pickupApps = counts(o.getJSONArray("pickup_apps")),
            notifications = o.getInt("notifications"),
            notificationApps = counts(o.getJSONArray("notification_apps")),
            screenOns = o.getInt("screen_ons"),
            shortScreenOns = o.getInt("short_screen_ons"),
            medianScreenOnMs = o.getLong("median_screen_on_ms"),
            audioMs = o.getLong("audio_ms"),
            audioApps = usages(o.getJSONArray("audio_apps")),
            productiveMs = o.optLong("productive_ms"),
            neutralMs = o.optLong("neutral_ms"),
            distractingMs = o.optLong("distracting_ms"),
            longStretches = o.getInt("long_stretches"),
            longStretchMs = o.getLong("long_stretch_ms"),
            longestStretch = UsageItem(longest.getString("name"), longest.getString("detail"), longest.getLong("ms")),
            longStretchCategories = usages(o.getJSONArray("long_stretch_categories")),
            appSwitches = o.getInt("app_switches"),
            medianSessionMs = o.getLong("median_session_ms"),
            phoneDuringComputerMs = o.getLong("phone_during_computer_ms"),
            pickupsDuringComputer = o.getInt("pickups_during_computer"),
            total = comparison(o.getJSONObject("total")),
            untilNow = o.getBoolean("until_now"),
            categories = o.getJSONArray("categories").objects().map(comparison),
            apps = o.optJSONArray("apps")?.objects()?.map(comparison).orEmpty(),
            trend = o.getJSONArray("trend").objects().map { it.getLong("ms") },
            weekHours = o.getJSONArray("week_hours").let { a ->
                (0 until a.length()).map { d -> a.getJSONArray(d).let { h -> (0 until h.length()).map { h.getLong(it) } } }
            },
        )
    }

    /** Like [load], null from servers without it. */
    fun timeline(server: Server, date: String, days: Int, device: String): Timeline? {
        val query = "date=" + encode(date) + "&days=$days&device=" + encode(device)
        val body = try {
            Sync.request("GET", server.url.trimEnd('/') + "/api/timeline?$query", server.token, null)
        } catch (e: HttpException) {
            if (e.status == 404) return null else throw e
        }
        val o = JSONObject(body)
        return Timeline(
            buckets = o.getJSONArray("buckets").objects().map {
                Bucket(it.getLong("start_ms"), it.getLong("end_ms"), it.getString("label"), it.getLong("ms"))
            },
            series = o.getJSONArray("series").objects().map { s ->
                val values = s.getJSONArray("values")
                Series(s.getString("name"), s.getLong("total_ms"), (0 until values.length()).map { values.getLong(it) })
            },
            sessions = o.getJSONArray("sessions").objects().map {
                Session(
                    it.getString("date"),
                    it.getLong("start_ms"),
                    it.getLong("end_ms"),
                    it.getString("start"),
                    it.getString("end"),
                    it.getLong("active_ms"),
                    it.getJSONArray("devices").strings(),
                    usages(it.getJSONArray("apps")),
                )
            },
        )
    }

    private fun encode(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private fun parse(o: JSONObject) = Report(
        date = o.getString("date"),
        firstDate = o.getString("first_date"),
        days = o.getInt("days"),
        device = o.getString("device"),
        previousDate = o.getString("previous_date"),
        nextDate = o.getString("next_date"),
        today = o.getString("today"),
        totalMs = o.getLong("total_ms"),
        previousMs = o.getLong("previous_ms"),
        sessions = o.getInt("sessions"),
        longestSessionMs = o.getLong("longest_session_ms"),
        firstActive = o.getString("first_active"),
        lastActive = o.getString("last_active"),
        timeline = usages(o.getJSONArray("timeline")),
        hours = usages(o.getJSONArray("hours")),
        strips = o.getJSONArray("strips").objects().map { s ->
            Strip(
                s.getString("label"),
                s.getString("date"),
                s.getLong("start_ms"),
                s.getLong("end_ms"),
                s.getJSONArray("segments").objects().map {
                    Segment(it.getLong("start_ms"), it.getLong("end_ms"), it.optString("device"), it.getString("category"))
                },
            )
        },
        categoryOrder = o.getJSONArray("category_order").strings(),
        deviceNames = o.getJSONArray("device_names").strings(),
        // servers before the OS was stored don't send it
        deviceOs = o.optJSONObject("device_os")?.let { os ->
            os.keys().asSequence().associateWith { os.getString(it) }
        }.orEmpty(),
        devices = usages(o.getJSONArray("devices")),
        categories = usages(o.getJSONArray("categories")),
        apps = usages(o.getJSONArray("apps")),
        titles = usages(o.getJSONArray("titles")),
        domains = usages(o.getJSONArray("domains")),
    )

    private fun usages(a: JSONArray) =
        a.objects().map { UsageItem(it.getString("name"), it.getString("detail"), it.getLong("ms")) }

    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }

    private fun JSONArray.strings() = (0 until length()).map { getString(it) }
}

/** "NixOS 25.05 (Warbler)" -> "NixOS" */
fun osName(os: String) = os.substringBefore(' ')

/** "Work > Programming" -> "Work" */
fun topLevel(category: String) = category.substringBefore(" > ")

/** The color slot (0 to 7) of a category, null for gray, like stats.color_slot. */
fun colorSlot(order: List<String>, category: String): Int? =
    order.indexOf(topLevel(category)).takeIf { it in 0..7 }
