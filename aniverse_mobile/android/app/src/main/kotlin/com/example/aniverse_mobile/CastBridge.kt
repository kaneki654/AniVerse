package com.example.aniverse_mobile

import android.app.Activity
import android.content.Context
import android.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaTrack
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Which Chromecast app plays our episodes: Google's default media receiver,
 * which takes HLS and WebVTT straight from the AniVerse proxy (it answers
 * cross-origin requests for this). Named in AndroidManifest.xml.
 */
class CastSetup : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID)
            .setStopReceiverApplicationWhenEndingSession(true)
            .build()

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}

/**
 * Chromecast for the player (lib/services/native_bridge.dart): the device
 * picker, handing the episode over, and telling the Dart side when a cast
 * starts and ends -- with where it got to, so the phone carries on from there.
 * Without Google Play services there is no Cast, and the menu entry stays hidden.
 */
class CastBridge(private val activity: Activity, private val channel: () -> MethodChannel?) {
    private var lastPosition = 0L
    private var tried = false
    private var context: CastContext? = null

    /** Set up on first use, so the app starts no slower for people who never cast. */
    private val cast: CastContext?
        get() {
            if (!tried) {
                tried = true
                context = try {
                    @Suppress("DEPRECATION") // The Task form defers the same work; this is the main thread.
                    CastContext.getSharedInstance(activity).also {
                        it.sessionManager.addSessionManagerListener(listener, CastSession::class.java)
                    }
                } catch (_: Exception) {
                    null // no Google Play services
                }
            }
            return context
        }

    private val session: CastSession? get() = cast?.sessionManager?.currentCastSession

    private val listener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(s: CastSession, sessionId: String) = tell("connected", s)
        override fun onSessionResumed(s: CastSession, wasSuspended: Boolean) = tell("connected", s)
        override fun onSessionEnding(s: CastSession) {
            s.remoteMediaClient?.approximateStreamPosition?.takeIf { it > 0 }?.let { lastPosition = it }
        }
        override fun onSessionEnded(s: CastSession, error: Int) = tell("ended", s)
        override fun onSessionStartFailed(s: CastSession, error: Int) = tell("failed", s)
        override fun onSessionResumeFailed(s: CastSession, error: Int) = tell("ended", s)
        override fun onSessionSuspended(s: CastSession, reason: Int) {}
        override fun onSessionStarting(s: CastSession) {}
        override fun onSessionResuming(s: CastSession, sessionId: String) {}
    }

    private fun tell(state: String, s: CastSession) {
        channel()?.invokeMethod(
            "cast",
            mapOf("state" to state, "device" to (s.castDevice?.friendlyName ?: "TV"), "position" to lastPosition),
        )
    }

    /** The calls from native_bridge.dart; false for anything that is not about casting. */
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "castAvailable" -> result.success(cast != null)
            "castDevice" -> result.success(session?.takeIf { it.isConnected }?.castDevice?.friendlyName)
            "castPick" -> result.success(pick())
            "castLoad" -> result.success(load(call))
            "castSeek" -> {
                val pos = (call.argument<Number>("position") ?: 0).toLong()
                session?.remoteMediaClient?.seek(MediaSeekOptions.Builder().setPosition(pos).build())
                result.success(null)
            }
            "castPlayPause" -> {
                session?.remoteMediaClient?.togglePlayback()
                result.success(null)
            }
            "castStop" -> {
                cast?.sessionManager?.endCurrentSession(true)
                result.success(null)
            }
            else -> return false
        }
        return true
    }

    /** The device list, or -- while casting -- the controls for the cast. */
    private fun pick(): Boolean {
        val c = cast ?: return false
        // The mediarouter dialogs need an AppCompat theme; FlutterActivity has none.
        val themed = ContextThemeWrapper(activity, androidx.appcompat.R.style.Theme_AppCompat_NoActionBar)
        if (session?.isConnected == true) {
            MediaRouteControllerDialog(themed).show()
        } else {
            MediaRouteChooserDialog(themed).apply { c.mergedSelector?.let { routeSelector = it } }.show()
        }
        return true
    }

    // Where the TV is, every second, and when an episode ends there: the phone
    // shows the position, offers skips, and sends the next episode.
    private var watched: RemoteMediaClient? = null
    private val progress = RemoteMediaClient.ProgressListener { position, duration ->
        if (position > 0) lastPosition = position
        channel()?.invokeMethod(
            "castProgress",
            mapOf("position" to position, "duration" to duration, "playing" to (watched?.isPlaying == true)),
        )
    }
    private val status = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() {
            val c = watched ?: return
            if (c.playerState == MediaStatus.PLAYER_STATE_IDLE && c.idleReason == MediaStatus.IDLE_REASON_FINISHED) {
                channel()?.invokeMethod("castFinished", null)
            }
        }
    }

    private fun watch(client: RemoteMediaClient) {
        if (watched === client) return
        watched?.removeProgressListener(progress)
        watched?.unregisterCallback(status)
        client.addProgressListener(progress, 1000)
        client.registerCallback(status)
        watched = client
    }

    private fun load(call: MethodCall): Boolean {
        val client = session?.remoteMediaClient ?: return false
        watch(client)
        val url = call.argument<String>("url") ?: return false
        val subs = call.argument<String>("subtitles")?.takeIf { it.isNotEmpty() }
        val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_TV_SHOW).apply {
            putString(MediaMetadata.KEY_TITLE, call.argument<String>("title") ?: "AniVerse")
            putString(MediaMetadata.KEY_SUBTITLE, call.argument<String>("subtitle") ?: "")
        }
        val track = subs?.let {
            MediaTrack.Builder(1, MediaTrack.TYPE_TEXT)
                .setName("Subtitles")
                .setSubtype(MediaTrack.SUBTYPE_SUBTITLES)
                .setContentId(it)
                .setContentType("text/vtt")
                .build()
        }
        val info = MediaInfo.Builder(url)
            .setContentUrl(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(if (call.argument<Boolean>("hls") == true) "application/x-mpegURL" else "video/mp4")
            .setMetadata(meta)
            .apply { track?.let { setMediaTracks(listOf(it)) } }
            .build()
        val request = MediaLoadRequestData.Builder()
            .setMediaInfo(info)
            .setAutoplay(true)
            .setCurrentTime((call.argument<Number>("position") ?: 0).toLong())
            .apply { if (track != null) setActiveTrackIds(longArrayOf(1)) }
            .build()
        lastPosition = 0
        // The TV can still refuse it (a stream it cannot fetch or decode): say so,
        // so the phone does not sit paused behind the casting screen.
        client.load(request).setResultCallback { r ->
            if (!r.status.isSuccess) channel()?.invokeMethod("castLoadFailed", r.status.statusCode)
        }
        return true
    }

    fun dispose() {
        watched?.removeProgressListener(progress)
        watched?.unregisterCallback(status)
        watched = null
        context?.sessionManager?.removeSessionManagerListener(listener, CastSession::class.java)
    }
}
