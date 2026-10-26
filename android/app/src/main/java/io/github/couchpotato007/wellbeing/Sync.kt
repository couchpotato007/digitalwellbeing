package io.github.couchpotato007.wellbeing

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

data class Server(val url: String, val token: String, val device: String)

/** The server and the outcome of the last sync, in shared preferences. */
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var server: Server?
        get() {
            val url = prefs.getString("url", null) ?: return null
            return Server(url, prefs.getString("token", "")!!, prefs.getString("device", "")!!)
        }
        set(server) {
            val edit = prefs.edit()
            if (server == null) edit.clear()
            else edit.putString("url", server.url).putString("token", server.token).putString("device", server.device)
            edit.apply()
        }

    var lastSync: String?
        get() = prefs.getString("last_sync", null)
        set(value) = prefs.edit().putString("last_sync", value).apply()
}

/** Same protocol as the desktop agent, see README.md. */
object Sync {
    /** How far back to go when the server has nothing for this device yet. */
    private const val FIRST_SYNC_DAYS = 30L

    /** How much of the already synced time is synced again. */
    private const val RESYNC_MS = 600_000L

    private const val WORK_NAME = "sync"

    /** Syncs once and returns the number of uploaded events. */
    fun run(context: Context): Int {
        val settings = Settings(context)
        val server = settings.server ?: throw IOException("No server set up")
        val result = runCatching {
            val base = server.url.trimEnd('/') + "/api/devices/" +
                URLEncoder.encode(server.device, "UTF-8").replace("+", "%20")
            val cursor = JSONObject(request("GET", "$base/cursor", server.token, null)).getLong("cursor_ms")
            val now = System.currentTimeMillis()
            val from = if (cursor == 0L) now - TimeUnit.DAYS.toMillis(FIRST_SYNC_DAYS) else cursor - RESYNC_MS
            val events = Usage.events(context, from, now)
            val body = JSONObject()
                .put("from_ms", from)
                .put("events", JSONArray(events.map { it.toJson() }))
            request("POST", "$base/events", server.token, body.toString())
            events.size
        }
        val time = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date())
        settings.lastSync = result.fold(
            { "$time: uploaded $it events" },
            { "$time: failed, ${it.message}" },
        )
        return result.getOrThrow()
    }

    /** Syncs every 15 minutes (the shortest WorkManager allows) while online. */
    fun schedule(context: Context) {
        val work = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, work)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    fun request(method: String, url: String, token: String, body: String?): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = 15_000
            conn.readTimeout = 60_000
            conn.setRequestProperty("Authorization", "Bearer $token")
            if (body != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.outputStream.use { it.write(body.toByteArray()) }
            }
            val status = conn.responseCode
            if (status >= 300) {
                val error = conn.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                throw IOException("HTTP $status $error".trim())
            }
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }
}

class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result =
        try {
            Sync.run(applicationContext)
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
}
