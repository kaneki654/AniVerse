package com.example.aniverse_mobile

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.SoundPool
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import android.util.Rational
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
                        val id = intent?.getStringExtra(AlertCheck.EXTRA_ANIME)
                        intent?.removeExtra(AlertCheck.EXTRA_ANIME)
                        result.success(id)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra(AlertCheck.EXTRA_ANIME)?.let {
            intent.removeExtra(AlertCheck.EXTRA_ANIME)
            native?.invokeMethod("openAnime", it)
        }
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

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Before Android 12 there is no auto-enter; this is the moment to do it by hand.
        if (pipReady && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        native?.invokeMethod("pipChanged", isInPictureInPictureMode)
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
        sounds?.release()
        sounds = null
        super.onDestroy()
    }

    companion object {
        private const val PERMISSION_REQUEST = 7301
    }
}
