package io.github.couchpotato007.wellbeing

import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * With notification access: records when a notification arrives (only the
 * app, not what it says) and when an app plays media, into the [Store].
 * Usage events have neither.
 */
class Listener : NotificationListenerService() {
    /** Notifications already counted, updates of them don't count again. */
    private val shown = mutableSetOf<String>()

    private val players = mutableMapOf<MediaSession, Player>()
    private var sessions: MediaSessionManager? = null
    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { watch(it.orEmpty()) }

    companion object {
        fun hasAccess(context: Context): Boolean =
            context.getSystemService(NotificationManager::class.java)
                .isNotificationListenerAccessGranted(ComponentName(context, Listener::class.java))
    }

    override fun onListenerConnected() {
        activeNotifications?.forEach { shown += it.key }
        val manager = getSystemService(MediaSessionManager::class.java)
        val me = ComponentName(this, Listener::class.java)
        manager.addOnActiveSessionsChangedListener(sessionsChanged, me)
        sessions = manager
        watch(manager.getActiveSessions(me))
    }

    override fun onListenerDisconnected() {
        sessions?.removeOnActiveSessionsChangedListener(sessionsChanged)
        sessions = null
        players.keys.toList().forEach { stop(it) }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification
        // ongoing ones (music, downloads, navigation) don't ask for attention,
        // a group's summary comes with its first notification
        if (sbn.isOngoing || n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (!shown.add(sbn.key) || sbn.packageName == packageName) return
        Store.get(this).put(Event(Event.NOTIFICATION, sbn.postTime, 0, label(sbn.packageName), sbn.packageName))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        shown -= sbn.key
    }

    private fun label(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        pkg
    }

    /** A media session, by its token, which stays the same for its controllers. */
    private data class MediaSession(val token: android.media.session.MediaSession.Token)

    /** Watches a session, `since` is when it started playing, null while it doesn't. */
    private inner class Player(val controller: MediaController) : MediaController.Callback() {
        var since: Long? = null

        override fun onPlaybackStateChanged(state: PlaybackState?) = update(this, state)
        override fun onSessionDestroyed() = stop(MediaSession(controller.sessionToken))
    }

    private fun watch(controllers: List<MediaController>) {
        val active = controllers.associateBy { MediaSession(it.sessionToken) }
        (players.keys - active.keys).forEach { stop(it) }
        for ((session, controller) in active) {
            if (session in players) continue
            val player = Player(controller)
            players[session] = player
            controller.registerCallback(player)
            update(player, controller.playbackState)
        }
    }

    /**
     * Writes the stretch as soon as playing starts and again when it stops, so
     * a killed listener loses at most its length.
     */
    private fun update(player: Player, state: PlaybackState?) {
        // buffering or skipping to the next track is still listening
        val playing = state?.state in setOf(
            PlaybackState.STATE_PLAYING,
            PlaybackState.STATE_BUFFERING,
            PlaybackState.STATE_CONNECTING,
            PlaybackState.STATE_FAST_FORWARDING,
            PlaybackState.STATE_REWINDING,
            PlaybackState.STATE_SKIPPING_TO_NEXT,
            PlaybackState.STATE_SKIPPING_TO_PREVIOUS,
            PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM,
        )
        val now = System.currentTimeMillis()
        val since = player.since
        when {
            playing && since == null -> player.since = record(player, now, now)
            !playing && since != null -> {
                record(player, since, now)
                player.since = null
            }
        }
    }

    private fun stop(session: MediaSession) {
        val player = players.remove(session) ?: return
        player.controller.unregisterCallback(player)
        player.since?.let { record(player, it, System.currentTimeMillis()) }
    }

    /** Stores the stretch from [start] to [end], returns the start it got. */
    private fun record(player: Player, start: Long, end: Long): Long {
        val pkg = player.controller.packageName
        val event = Event(Event.AUDIO, start, end - start, label(pkg), pkg)
        // the first write finds a free start, later ones change that event
        return Store.get(this).put(event, replace = start != end)
    }
}
