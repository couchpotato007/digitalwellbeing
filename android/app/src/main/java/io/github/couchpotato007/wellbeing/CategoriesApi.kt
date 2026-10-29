package io.github.couchpotato007.wellbeing

import org.json.JSONArray
import org.json.JSONObject

/** How a category counts on the dashboard. */
enum class Rating(val key: String, val label: String) {
    Productive("productive", "Productive"),
    Neutral("neutral", "Neutral"),
    Distracting("distracting", "Distracting");

    companion object {
        fun of(key: String) = entries.find { it.key == key } ?: Neutral
    }
}

/**
 * An app or website and its screen time in the last 30 days. [source] is why
 * it is in its category: "assigned", "rule", "known", "android", "browser"
 * or "none".
 */
data class CategoryItem(val name: String, val ms: Long, val source: String, val devices: List<String>)

/** An advanced rule: regexes on the app (or website) and title put events into [category]. [id] 0 is a new one. */
data class Rule(
    val id: Int,
    val category: String,
    val patterns: List<String>,
    val ignoreCase: Boolean = true,
    /** Empty for all devices */
    val devices: List<String> = emptyList(),
)

data class Category(
    /** A path like "Work > Programming" */
    val name: String,
    val rating: Rating,
    val builtin: Boolean,
    /** Screen time in the last 30 days */
    val ms: Long,
    val items: List<CategoryItem>,
    val rules: List<Rule>,
)

/** From `GET /api/categories`, see rules.gleam on the server. */
data class CategoryOverview(
    /** In the order of their colors */
    val categories: List<Category>,
    /** What has no category, the most used first */
    val unsorted: List<CategoryItem>,
    val unsortedMs: Long,
    val devices: List<String>,
    val categoryOrder: List<String>,
)

/** What a rule matches in the last 30 days. */
data class Preview(val screenMs: Long, val apps: List<UsageItem>, val titles: List<UsageItem>)

/**
 * The server's categories. Every change puts the stored events into
 * categories again. Errors are [HttpException]s, [Sync.describe] words them.
 */
object CategoriesApi {
    fun load(server: Server): CategoryOverview {
        val o = JSONObject(Sync.request("GET", url(server, "categories"), server.token, null))
        val items = { a: JSONArray ->
            a.objects().map {
                CategoryItem(it.getString("name"), it.getLong("ms"), it.getString("source"), it.getJSONArray("devices").strings())
            }
        }
        return CategoryOverview(
            categories = o.getJSONArray("categories").objects().map { c ->
                Category(
                    c.getString("name"),
                    Rating.of(c.getString("rating")),
                    c.getBoolean("builtin"),
                    c.getLong("ms"),
                    items(c.getJSONArray("items")),
                    c.getJSONArray("rules").objects().map {
                        Rule(
                            it.getInt("id"),
                            it.getString("category"),
                            it.getJSONArray("patterns").strings(),
                            it.getBoolean("ignore_case"),
                            it.getJSONArray("devices").strings(),
                        )
                    },
                )
            },
            unsorted = items(o.getJSONArray("unsorted")),
            unsortedMs = o.getLong("unsorted_ms"),
            devices = o.getJSONArray("devices").strings(),
            categoryOrder = o.getJSONArray("category_order").strings(),
        )
    }

    /** Adds a category or changes its rating, with [oldName] renames that one. */
    fun save(server: Server, name: String, rating: Rating, oldName: String = "") =
        post(server, "categories/save", JSONObject().put("name", name).put("rating", rating.key).put("old_name", oldName))

    /** Deletes a category with its rules, its apps go back to automatic. */
    fun delete(server: Server, name: String) = post(server, "categories/delete", JSONObject().put("name", name))

    /** Puts an app or website into [category], "" back to automatic. */
    fun assign(server: Server, app: String, category: String) =
        post(server, "categories/assign", JSONObject().put("app", app).put("category", category))

    fun addBuiltins(server: Server) = post(server, "categories/builtins", JSONObject())

    fun saveRule(server: Server, rule: Rule) = post(server, "rules", rule.toJson())

    fun deleteRule(server: Server, id: Int) {
        Sync.request("DELETE", url(server, "rules/$id"), server.token, null)
    }

    fun preview(server: Server, rule: Rule): Preview {
        val o = JSONObject(Sync.request("POST", url(server, "rules/preview"), server.token, rule.toJson().toString()))
        return Preview(o.getLong("screen_ms"), usages(o.getJSONArray("apps")), usages(o.getJSONArray("titles")))
    }

    private fun post(server: Server, path: String, body: JSONObject) {
        Sync.request("POST", url(server, path), server.token, body.toString())
    }

    private fun url(server: Server, path: String) = server.url.trimEnd('/') + "/api/" + path

    private fun Rule.toJson() = JSONObject()
        .put("id", id)
        .put("category", category)
        .put("patterns", JSONArray(patterns))
        .put("ignore_case", ignoreCase)
        .put("devices", JSONArray(devices))

    private fun usages(a: JSONArray) =
        a.objects().map { UsageItem(it.getString("name"), it.getString("detail"), it.getLong("ms")) }

    private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }

    private fun JSONArray.strings() = (0 until length()).map { getString(it) }
}
