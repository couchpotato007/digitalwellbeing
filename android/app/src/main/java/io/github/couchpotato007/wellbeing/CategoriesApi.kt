package io.github.couchpotato007.wellbeing

import org.json.JSONArray
import org.json.JSONObject

/** A category rule from `GET /api/categories`, see rules.gleam. [id] 0 is a new one. */
data class Rule(
    val id: Int,
    /** A path like "Work > Programming" */
    val name: String,
    /** Regexes, any of them matching the app or title puts an event in the category */
    val patterns: List<String>,
    val ignoreCase: Boolean,
    /** Empty for all devices */
    val devices: List<String>,
    /** Screen time of the category in the last 30 days */
    val ms: Long = 0,
)

data class CategoryOverview(
    val rules: List<Rule>,
    val devices: List<String>,
    val categoryOrder: List<String>,
    val uncategorizedApps: List<UsageItem>,
    val uncategorizedTitles: List<UsageItem>,
)

/** What a rule matches in the last 30 days, whatever deeper rules say. */
data class Preview(val screenMs: Long, val apps: List<UsageItem>, val titles: List<UsageItem>)

/** The server's category rules. Errors are [HttpException]s, [Sync.describe] words them. */
object CategoriesApi {
    fun load(server: Server): CategoryOverview {
        val o = JSONObject(Sync.request("GET", url(server), server.token, null))
        return CategoryOverview(
            rules = o.getJSONArray("rules").objects().map {
                Rule(
                    it.getInt("id"),
                    it.getString("name"),
                    it.getJSONArray("patterns").strings(),
                    it.getBoolean("ignore_case"),
                    it.getJSONArray("devices").strings(),
                    it.getLong("ms"),
                )
            },
            devices = o.getJSONArray("devices").strings(),
            categoryOrder = o.getJSONArray("category_order").strings(),
            uncategorizedApps = usages(o.getJSONArray("uncategorized_apps")),
            uncategorizedTitles = usages(o.getJSONArray("uncategorized_titles")),
        )
    }

    /** Adds the rule, or changes the one with its id. The server puts all events in categories again. */
    fun save(server: Server, rule: Rule) {
        Sync.request("POST", url(server), server.token, rule.toJson().toString())
    }

    fun delete(server: Server, id: Int) {
        Sync.request("DELETE", url(server) + "/$id", server.token, null)
    }

    fun preview(server: Server, rule: Rule): Preview {
        val o = JSONObject(Sync.request("POST", url(server) + "/preview", server.token, rule.toJson().toString()))
        return Preview(o.getLong("screen_ms"), usages(o.getJSONArray("apps")), usages(o.getJSONArray("titles")))
    }

    /** Adds [text] as a pattern that matches exactly it to the rule with [id]. */
    fun assign(server: Server, id: Int, text: String) {
        val body = JSONObject().put("id", id).put("text", text)
        Sync.request("POST", url(server) + "/assign", server.token, body.toString())
    }

    private fun url(server: Server) = server.url.trimEnd('/') + "/api/categories"

    private fun Rule.toJson() = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("patterns", JSONArray(patterns))
        .put("ignore_case", ignoreCase)
        .put("devices", JSONArray(devices))

    private fun usages(a: JSONArray) =
        a.objects().map { UsageItem(it.getString("name"), it.getString("detail"), it.getLong("ms")) }

    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }

    private fun JSONArray.strings() = (0 until length()).map { getString(it) }
}

/** "x.com (1)" -> "x\.com \(1\)", a pattern that matches only the text, like categories.escape. */
fun escapePattern(text: String) = text.map { if (it in "\\^$.|?*+()[]{}") "\\$it" else "$it" }.joinToString("")
