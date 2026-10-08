package com.example.aniverse_mobile

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.media.SoundPool
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var native: MethodChannel? = null

    // --- picture in picture ------------------------------------------------------
    // The player tells us when a video is playing (and its shape); leaving the
    // app then shrinks it into a floating window instead of stopping it.
    private var pipReady = false
    private var pipAspect = Rational(16, 9)

    // --- sound effects -------------------------------------------------------------
    private var sounds: SoundPool? = null
    private val soundIds = HashMap<String, Int>()

    private var pendingPermission: MethodChannel.Result? = null

    // --- media session ---------------------------------------------------------------
    // While an episode is open: headset buttons, car controls, TV remotes, the
    // lock screen and Android's media controls play, pause and seek it.
    private var session: MediaSession? = null

    // --- Chromecast (CastBridge.kt) ------------------------------------------------------
    private val castBridge = CastBridge(this) { native }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Bytes received so far, for the player's download-speed readout
        // (lib/services/net_speed.dart). video_player does not expose
        // ExoPlayer's bandwidth meter, and while the player is buffering this
        // app's traffic is the stream itself.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aniverse/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "rxBytes" -> {
                        val own = TrafficStats.getUidRxBytes(Process.myUid())
                        // Some devices do not account per app (UNSUPPORTED = -1);
                        // the device-wide counter is the next best thing.
                        result.success(
                            if (own != TrafficStats.UNSUPPORTED.toLong()) own
                            else TrafficStats.getTotalRxBytes()
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // Everything else the Dart side needs from Android (lib/services/native_bridge.dart).
        native = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aniverse/native").apply {
            setMethodCallHandler { call, result ->
                if (castBridge.handle(call, result)) return@setMethodCallHandler
                when (call.method) {
                    "sfx" -> {
                        playSound(
                            call.argument<String>("name") ?: "",
                            (call.argument<Double>("volume") ?: 0.35).toFloat(),
                            (call.argument<Double>("rate") ?: 1.0).toFloat(),
                        )
                        result.success(null)
                    }
                    "pipSupported" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    )
                    "setPipReady" -> {
                        pipReady = call.argument<Boolean>("ready") ?: false
                        val w = call.argument<Int>("w") ?: 16
                        val h = call.argument<Int>("h") ?: 9
                        pipAspect = clampAspect(w, h)
                        updatePipParams()
                        result.success(null)
                    }
                    "enterPip" -> result.success(enterPip())
                    // Android TV and other big screens driven by a remote.
                    "isTv" -> {
                        val ui = getSystemService(android.app.UiModeManager::class.java)
                        result.success(
                            ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                                packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        )
                    }
                    "isMetered" -> {
                        val cm = getSystemService(android.net.ConnectivityManager::class.java)
                        result.success(cm?.isActiveNetworkMetered ?: false)
                    }
                    "downloadsActive" -> {
                        DownloadKeepAlive.update(
                            applicationContext,
                            call.argument<Boolean>("on") == true,
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("progress") ?: -1,
                        )
                        result.success(null)
                    }
                    // Swipe gestures in the full-screen player: this window's
                    // brightness (-1 hands it back to the system) and media volume.
                    "getBrightness" -> {
                        val own = window.attributes.screenBrightness
                        result.success(
                            if (own >= 0) own.toDouble()
                            else try {
                                android.provider.Settings.System.getInt(
                                    contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS
                                ) / 255.0
                            } catch (_: Exception) { 0.5 }
                        )
                    }
                    "setBrightness" -> {
                        val v = (call.argument<Double>("value") ?: -1.0).toFloat()
                        runOnUiThread {
                            window.attributes = window.attributes.apply {
                                screenBrightness = if (v < 0) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                                else v.coerceIn(0.01f, 1f)
                            }
                        }
                        result.success(null)
                    }
                    "getVolume" -> {
                        val am = getSystemService(android.media.AudioManager::class.java)
                        val max = am?.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC) ?: 0
                        result.success(
                            if (am == null || max == 0) 0.5
                            else am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC).toDouble() / max
                        )
                    }
                    "setVolume" -> {
                        val am = getSystemService(android.media.AudioManager::class.java)
                        if (am != null) {
                            val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                            val v = (call.argument<Double>("value") ?: 0.5).coerceIn(0.0, 1.0)
                            am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, Math.round(v * max).toInt(), 0)
                        }
                        result.success(null)
                    }
                    "keepScreenOn" -> {
                        val on = call.argument<Boolean>("on") == true
                        runOnUiThread {
                            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "mediaSession" -> {
                        updateSession(
                            call.argument<Boolean>("active") == true,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("subtitle") ?: "",
                            call.argument<Boolean>("playing") == true,
                            (call.argument<Number>("position") ?: 0).toLong(),
                            (call.argument<Number>("duration") ?: 0).toLong(),
                            call.argument<Boolean>("hasNext") == true,
                        )
                        result.success(null)
                    }
                    "shareImage" -> {
                        val file = java.io.File(call.argument<String>("path") ?: "")
                        val sent = try {
                            val uri = androidx.core.content.FileProvider.getUriForFile(this@MainActivity, "$packageName.files", file)
                            val send = Intent(Intent.ACTION_SEND)
                                .setType("image/png")
                                .putExtra(Intent.EXTRA_STREAM, uri)
                                .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(Intent.createChooser(send, "Share your AniVerse card"))
                            true
                        } catch (_: Exception) {
                            false
                        }
                        result.success(sent)
                    }
                    "notificationsAllowed" -> result.success(notificationsAllowed())
                    "requestNotifications" -> requestNotifications(result)
                    "scheduleAlerts" -> {
                        if (call.argument<Boolean>("on") == true) AlertCheck.schedule(this@MainActivity)
                        else AlertCheck.cancel(this@MainActivity)
                        result.success(null)
                    }
                    "checkAlertsNow" -> Thread {
                        val n = AlertCheck.run(applicationContext)
                        runOnUiThread { result.success(n) }
                    }.start()
                    // The anime a tapped alert was about, once, for the Dart side to open.
                    "takeLaunchAnime" -> {
                        result.success(intent?.let { takeAlert(it) })
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeAlert(intent)?.let { native?.invokeMethod("openAnime", it) }
    }

    /** The alert a launch came from, once: "animeId" or "animeId:episode" to play it. */
    private fun takeAlert(intent: Intent): String? {
        val id = intent.getStringExtra(AlertCheck.EXTRA_ANIME) ?: return null
        val ep = intent.getIntExtra(AlertCheck.EXTRA_EPISODE, 0)
        intent.removeExtra(AlertCheck.EXTRA_ANIME)
        intent.removeExtra(AlertCheck.EXTRA_EPISODE)
        return if (ep > 0) "$id:$ep" else id
    }

    // --- picture in picture --------------------------------------------------------------

    private fun clampAspect(w: Int, h: Int): Rational {
        // Android refuses ratios outside 1:2.39..2.39:1.
        if (w <= 0 || h <= 0) return Rational(16, 9)
        val r = w.toDouble() / h
        return when {
            r > 2.39 -> Rational(239, 100)
            r < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val b = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
            // Android 12+: going home while a video plays slides it into PiP by itself.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) b.setAutoEnterEnabled(pipReady).setSeamlessResizeEnabled(true)
            setPictureInPictureParams(b.build())
        } catch (_: Exception) {
            // Not supported on this device; the in-app button just stays hidden.
        }
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(pipAspect).build())
        } catch (_: Exception) {
            false
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        // With a remote or keyboard Android frames the focused view -- here the
        // whole Flutter view. The app draws its own focus ring on the control.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) noFocusHighlight(window.decorView)
    }

    private fun noFocusHighlight(v: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) v.defaultFocusHighlightEnabled = false
        if (v is ViewGroup) for (i in 0 until v.childCount) noFocusHighlight(v.getChildAt(i))
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Before Android 12 there is no auto-enter; this is the moment to do it by hand.
        if (pipReady && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        native?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    // --- media session ----------------------------------------------------------------------

    private fun media(action: String, position: Long = 0) =
        runOnUiThread { native?.invokeMethod("media", mapOf("action" to action, "position" to position)) }

    private fun updateSession(
        active: Boolean, title: String, subtitle: String,
        playing: Boolean, position: Long, duration: Long, hasNext: Boolean,
    ) {
        if (!active) {
            session?.run { isActive = false; release() }
            session = null
            return
        }
        val s = session ?: MediaSession(this, "AniVerse").also { s ->
            s.setCallback(object : MediaSession.Callback() {
                override fun onPlay() = media("play")
                override fun onPause() = media("pause")
                override fun onStop() = media("pause")
                override fun onSkipToNext() = media("next")
                override fun onFastForward() = media("forward")
                override fun onRewind() = media("rewind")
                override fun onSeekTo(pos: Long) = media("seek", pos)
            })
            session = s
        }
        s.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
                .build()
        )
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND or PlaybackState.ACTION_STOP
        if (hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    position, if (playing) 1f else 0f,
                )
                .build()
        )
        s.isActive = true
    }

    // --- sound effects ----------------------------------------------------------------------

    /** [rate] 0.5..2 shifts the pitch: each palette has its own voice. */
    private fun playSound(name: String, volume: Float, rate: Float) {
        val pool = sounds ?: SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build().also { pool ->
                sounds = pool
                // Referenced by name here so release resource shrinking keeps them.
                val raw = mapOf(
                    "click" to R.raw.sfx_click, "select" to R.raw.sfx_select, "splat" to R.raw.sfx_splat,
                    "slash" to R.raw.sfx_slash, "start" to R.raw.sfx_start, "skip" to R.raw.sfx_skip,
                    "error" to R.raw.sfx_error, "achieve" to R.raw.sfx_achieve, "hit" to R.raw.sfx_hit,
                    "boss" to R.raw.sfx_boss,
                )
                raw.forEach { (k, res) -> soundIds[k] = pool.load(this, res, 1) }
            }
        val id = soundIds[name] ?: return
        val v = volume.coerceIn(0f, 1f)
        // The very first call lands before loading finishes and is silent; every
        // later one plays at once.
        pool.play(id, v, v, 1, 0, rate.coerceIn(0.5f, 2f))
    }

    // --- notifications ---------------------------------------------------------------------------

    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED

    private fun requestNotifications(result: MethodChannel.Result) {
        if (notificationsAllowed()) return result.success(true)
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), PERMISSION_REQUEST)
    }

    @Deprecated("Still the callback for Activity.requestPermissions")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        @Suppress("DEPRECATION")
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
    }

    override fun onDestroy() {
        session?.release()
        session = null
        castBridge.dispose()
        sounds?.release()
        sounds = null
        super.onDestroy()
    }

    companion object {
        private const val PERMISSION_REQUEST = 7301
    }
}
