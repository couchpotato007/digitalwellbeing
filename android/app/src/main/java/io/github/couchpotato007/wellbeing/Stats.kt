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
    /** Detail is when the device was last active. */
    val devices: List<UsageItem>,
    val categories: List<UsageItem>,
    val apps: List<UsageItem>,
    val titles: List<UsageItem>,
    val domains: List<UsageItem>,
)

data class UsageItem(val name: String, val detail: String, val ms: Long)

/** A row of the activity view. [date] is set for rows of a day, empty for rows of a device. */
data class Strip(val label: String, val date: String, val startMs: Long, val endMs: Long, val segments: List<Segment>)

data class Segment(val startMs: Long, val endMs: Long, val category: String)

object Stats {
    /** [date] "" is today, [device] "" is all devices. */
    fun load(server: Server, date: String, days: Int, device: String): Report {
        val query = "date=" + encode(date) + "&days=$days&device=" + encode(device)
        val body = Sync.request("GET", server.url.trimEnd('/') + "/api/stats?$query", server.token, null)
        return parse(JSONObject(body))
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
                    Segment(it.getLong("start_ms"), it.getLong("end_ms"), it.getString("category"))
                },
            )
        },
        categoryOrder = o.getJSONArray("category_order").strings(),
        deviceNames = o.getJSONArray("device_names").strings(),
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

/** "Work > Programming" -> "Work" */
fun topLevel(category: String) = category.substringBefore(" > ")

/** The color slot (0 to 7) of a category, null for gray, like stats.color_slot. */
fun colorSlot(order: List<String>, category: String): Int? =
    order.indexOf(topLevel(category)).takeIf { it in 0..7 }
