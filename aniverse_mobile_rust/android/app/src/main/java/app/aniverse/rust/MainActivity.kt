package app.aniverse.rust

import android.annotation.SuppressLint
import android.app.AlertDialog
import android.app.NativeActivity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.media.SoundPool
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.util.TypedValue
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.graphics.PathParser
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min

// The manga UI's ink and paper (lib/ui_manga/ink/manga.dart).
private const val PAPER = 0xFFF5F1E8.toInt()
private const val PANEL = 0xFFFFFFFF.toInt()
private const val INK = 0xFF121010.toInt()
private const val GRAY = 0xFF5C5852.toInt()
private const val RED = 0xFFE50914.toInt()

/**
 * Slint owns NativeActivity's surface; the player is an overlay above it,
 * lettered like the manga player (lib/ui_manga/screens/watch_screen.dart):
 * a paper bar with the title, CC and the SUB/DUB switch, the video, and a
 * panel with an inked seek bar, the time, next, picture in picture and full
 * screen. The activity also hands Rust the back key and the system bars'
 * size, and plays the manga sounds and opens links for it.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class MainActivity : NativeActivity() {
    companion object {
        init {
            // NativeActivity dlopens the library without telling the class loader, so the
            // native methods below would not resolve. This returns that same loaded library.
            System.loadLibrary("aniverse_rust")
        }
    }

    private external fun nativePlaybackEvent(payload: String)
    private external fun nativeBack()
    private external fun nativeInsets(top: Float, bottom: Float)
    private external fun nativePlayerCommand(command: String)

    private val handler = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var overlay: FrameLayout? = null
    private var request: JSONObject? = null
    private var topBar: LinearLayout? = null
    private var controls: LinearLayout? = null
    private var videoBox: FrameLayout? = null
    private var playerView: PlayerView? = null
    private var seek: InkSeekBar? = null
    private var timeText: TextView? = null
    private var playButton: GlyphView? = null
    private var fullButton: GlyphView? = null
    private var ccButton: InkButton? = null
    private var skipButton: InkButton? = null
    private var buffering: ProgressBar? = null
    private var failure: LinearLayout? = null
    private var failureText: TextView? = null
    private var resumeAfterPause = false
    private var fullscreen = false
    private var captions = true
    private var hudShown = true
    private var insetTop = 0
    private var insetBottom = 0
    private var sounds: SoundPool? = null
    private val soundIds = HashMap<String, Int>()
    private val titleFace by lazy { Typeface.createFromAsset(assets, "fonts/MangaTitle-Oblique.ttf") }
    private val labelFace by lazy { Typeface.createFromAsset(assets, "fonts/RobotoCondensed-Bold.ttf") }

    private val progress = object : Runnable {
        override fun run() {
            val p = player ?: return
            reportProgress()
            updateSkipButton()
            handler.postDelayed(this, 2000)
            if (p.duration > 0) seek?.buffered = p.bufferedPosition.toFloat() / p.duration
        }
    }
    private val clock = object : Runnable {
        override fun run() {
            val p = player ?: return
            updateTime(p)
            handler.postDelayed(this, 500)
        }
    }
    private val hideHud = Runnable { if (player?.isPlaying == true) showHud(false) }

    override fun onCreate(savedInstanceState: Bundle?) {
        // The manifest's android.app.lib_name loads libaniverse_rust.so and
        // invokes android_main with the real AndroidApp and native event loop.
        super.onCreate(savedInstanceState)
        // Slint fills its native view (fullscreen); tell it how much of that view the
        // system bars cover. The view may itself already sit below the status bar, so
        // only the overlap counts.
        window.decorView.setOnApplyWindowInsetsListener { v, insets ->
            v.post { reportInsets() }
            v.onApplyWindowInsets(insets)
        }
        window.decorView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> reportInsets() }
        window.decorView.requestApplyInsets()
        loadSounds()
    }

    private var reported = Pair(-1f, -1f)

    private fun reportInsets() {
        val root = window.decorView
        val insets = root.rootWindowInsets ?: return
        val (barTop, barBottom) = if (Build.VERSION.SDK_INT >= 30) {
            val bars = insets.getInsets(WindowInsets.Type.systemBars())
            bars.top to bars.bottom
        } else {
            @Suppress("DEPRECATION")
            insets.systemWindowInsetTop to insets.systemWindowInsetBottom
        }
        val content = root.findViewById<View>(android.R.id.content) ?: return
        val at = IntArray(2)
        content.getLocationOnScreen(at)
        val screen = root.height
        val top = max(0, barTop - at[1])
        val bottom = max(0, (at[1] + content.height) - (screen - barBottom))
        val density = resources.displayMetrics.density
        val next = Pair(top / density, bottom / density)
        if (next != reported && screen > 0) {
            reported = next
            runCatching { nativeInsets(next.first, next.second) }
        }
    }

    /** The overlay draws under the system bars: its top bar keeps clear of the status bar. */
    private fun watchInsets(view: View) {
        view.setOnApplyWindowInsetsListener { _, insets ->
            val (top, bottom) = if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars())
                bars.top to bars.bottom
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetTop to insets.systemWindowInsetBottom
            }
            insetTop = top
            insetBottom = bottom
            topBar?.setPadding(dp(4), if (fullscreen) 0 else top, dp(8), 0)
            insets
        }
        view.requestApplyInsets()
    }

    // --- services for Rust -------------------------------------------------------------------

    private fun loadSounds() {
        val attributes = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_GAME)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val pool = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(attributes).build()
        sounds = pool
        for (name in listOf("achieve", "boss", "click", "don", "error", "hit", "page", "pop", "select", "skip", "slash", "splat", "start")) {
            @SuppressLint("DiscouragedApi")
            val id = resources.getIdentifier("manga_$name", "raw", packageName)
            if (id != 0) soundIds[name] = pool.load(this, id, 1)
        }
    }

    /** Sfx.play: one of the manga sounds. Called from Rust on any thread. */
    fun playSfx(name: String, volume: Float) {
        val id = soundIds[name] ?: return
        val v = volume.coerceIn(0f, 1f)
        sounds?.play(id, v, v, 1, 0, 1f)
    }

    fun openUrl(url: String) = runOnUiThread {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
        }
    }

    fun exitToBackground() = runOnUiThread { moveTaskToBack(true) }

    // --- the player -----------------------------------------------------------------------

    /** Called through JNI. All Android and Media3 objects stay on the main thread. */
    fun playStream(payload: String) = runOnUiThread {
        try {
            stopStreamOnUiThread(reportClosed = false)
            val data = JSONObject(payload)
            request = data
            val url = data.getString("url")
            val factory = DefaultHttpDataSource.Factory().setUserAgent("AniVerse-Rust (Android)")
                .setConnectTimeoutMs(15000).setReadTimeoutMs(30000)
                .setAllowCrossProtocolRedirects(true)
            val sourceFactory = DefaultMediaSourceFactory(DefaultDataSource.Factory(this, factory))
            val step = data.optLong("seek_step", 10).coerceIn(1, 120) * 1000
            val exo = ExoPlayer.Builder(this)
                .setMediaSourceFactory(sourceFactory)
                .setSeekBackIncrementMs(step)
                .setSeekForwardIncrementMs(step)
                .build()
            player = exo
            exo.setAudioAttributes(AudioAttributes.DEFAULT, true)
            val item = MediaItem.Builder().setUri(Uri.parse(url))
                .setMediaId("${data.optString("anime_id")}/${data.optInt("episode", 1)}")
            val path = Uri.parse(url).path.orEmpty().lowercase()
            if (path.endsWith(".m3u8") || path.contains("/proxy/m3u8")) item.setMimeType(MimeTypes.APPLICATION_M3U8)
            captions = false
            if (!data.isNull("subtitle_url")) {
                val subtitle = data.optString("subtitle_url")
                if (subtitle.isNotBlank()) {
                    val mime = if (Uri.parse(subtitle).path.orEmpty().endsWith(".srt")) MimeTypes.APPLICATION_SUBRIP else MimeTypes.TEXT_VTT
                    item.setSubtitleConfigurations(listOf(MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitle))
                        .setMimeType(mime).setLanguage(data.optString("subtitle_language").ifBlank { "en" })
                        .setSelectionFlags(C.SELECTION_FLAG_DEFAULT).build()))
                    captions = true
                }
            }
            buildOverlay(data, exo)
            exo.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) {
                    buffering?.visibility = if (state == Player.STATE_BUFFERING) View.VISIBLE else View.GONE
                    if (state == Player.STATE_ENDED) {
                        reportProgress(ended = true)
                        showHud(true)
                    }
                    updateSkipButton()
                }
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    playButton?.data = if (isPlaying) Glyphs.PAUSE else Glyphs.PLAY
                    if (isPlaying) scheduleHide() else showHud(true)
                    if (isPlaying) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                override fun onPlayerError(error: PlaybackException) {
                    reportProgress(error = "Playback interrupted. Check your connection or try another source.")
                    failureText?.text = "PLAYBACK INTERRUPTED"
                    failure?.visibility = View.VISIBLE
                    showHud(true)
                }
            })
            exo.setMediaItem(item.build())
            exo.seekTo(data.optLong("position_ms", 0).coerceAtLeast(0))
            exo.setPlaybackSpeed(data.optDouble("speed", 1.0).toFloat().coerceIn(0.25f, 3f))
            exo.prepare()
            exo.playWhenReady = true
            handler.post(progress)
            handler.post(clock)
        } catch (error: Exception) {
            reportProgress(error = "Unable to open this video: ${error.message.orEmpty()}")
            stopStreamOnUiThread(reportClosed = true)
        }
    }

    private fun label(text: String, size: Float, color: Int, face: Typeface = labelFace) = TextView(this).apply {
        this.text = text
        setTextColor(color)
        typeface = face
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
        includeFontPadding = false
    }

    private fun glyph(data: String, tint: Int, description: String, click: () -> Unit) = GlyphView(this, data, tint).apply {
        contentDescription = description
        isClickable = true
        setOnClickListener {
            playSfx("click", 0.35f)
            click()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun buildOverlay(data: JSONObject, exo: ExoPlayer) {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK); isClickable = true; isFocusable = true }
        overlay = root
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(column, FrameLayout.LayoutParams(-1, -1))

        // The bar: back, OVERGEARED · EP 3, the gear, CC, the SUB/DUB switch.
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(PAPER)
            setPadding(dp(4), insetTop, dp(8), 0)
        }
        topBar = bar
        bar.addView(glyph(Glyphs.BACK, INK, "Back") { stopStreamOnUiThread(reportClosed = true) }, LinearLayout.LayoutParams(dp(48), dp(56)))
        bar.addView(label("${data.optString("title").uppercase()} · EP ${data.optInt("episode", 1)}", 20f, INK, titleFace).apply {
            setPadding(dp(8), 0, dp(8), 0)
        }, LinearLayout.LayoutParams(0, -2, 1f))
        bar.addView(glyph(Glyphs.GEAR, INK, "Playback speed") { chooseSpeed() }, LinearLayout.LayoutParams(dp(44), dp(56)))
        val cc = InkButton(this, "CC", labelFace, if (captions) RED else PANEL, if (captions) PANEL else INK) { toggleCaptions() }
        ccButton = cc
        bar.addView(cc, LinearLayout.LayoutParams(-2, dp(44)).apply { leftMargin = dp(4) })
        if (!data.optBoolean("local", false)) {
            val category = data.optString("category", "sub")
            val next = if (category == "sub") "SUB" else if (category == "dub") "DUB" else "TL"
            bar.addView(InkButton(this, "⇄ $next", labelFace, RED, PANEL) { command("switch") },
                LinearLayout.LayoutParams(-2, dp(44)).apply { leftMargin = dp(8) })
        }
        column.addView(bar, LinearLayout.LayoutParams(-1, -2))
        column.addView(View(this).apply { setBackgroundColor(INK) }, LinearLayout.LayoutParams(-1, dp(3)))

        // The video: tap for the bars, double-tap a side to skip.
        val box = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        videoBox = box
        val view = PlayerView(this).apply {
            player = exo
            useController = false
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(Color.BLACK)
        }
        playerView = view
        view.subtitleView?.apply {
            val textColor = when (data.optString("subtitle_color", "white")) {
                "yellow" -> Color.YELLOW
                "cyan" -> Color.CYAN
                "green" -> Color.GREEN
                else -> Color.WHITE
            }
            val fraction = when (data.optString("subtitle_size", "m")) {
                "s" -> 0.040f
                "l" -> 0.065f
                "xl" -> 0.080f
                else -> 0.0533f
            }
            setApplyEmbeddedStyles(false)
            setFractionalTextSize(fraction)
            setStyle(CaptionStyleCompat(textColor,
                if (data.optBoolean("subtitle_background", true)) 0xB0000000.toInt() else Color.TRANSPARENT,
                Color.TRANSPARENT, CaptionStyleCompat.EDGE_TYPE_OUTLINE, Color.BLACK, null))
        }
        box.addView(view, FrameLayout.LayoutParams(-1, -1))
        val gestures = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                showHud(!hudShown)
                return true
            }
            override fun onDoubleTap(e: MotionEvent): Boolean {
                val p = player ?: return true
                if (e.x < box.width / 2f) p.seekBack() else p.seekForward()
                playSfx("skip", 0.35f)
                return true
            }
        })
        box.setOnTouchListener { _, e -> gestures.onTouchEvent(e) }
        buffering = ProgressBar(this).apply {
            isIndeterminate = true
            indeterminateTintList = android.content.res.ColorStateList.valueOf(RED)
            visibility = View.GONE
        }
        box.addView(buffering, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER))
        skipButton = InkButton(this, "SKIP INTRO", labelFace, RED, PANEL) { skip() }.apply { visibility = View.GONE }
        box.addView(skipButton, FrameLayout.LayoutParams(-2, dp(44), Gravity.END or Gravity.BOTTOM).apply {
            bottomMargin = dp(14); rightMargin = dp(14)
        })
        // Nothing plays: the shock panel, and a way to try again.
        failure = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xEE0A0909.toInt())
            setPadding(dp(24), dp(16), dp(24), dp(16))
            addView(label("ガーン!", 40f, PANEL, Typeface.DEFAULT_BOLD).apply { gravity = Gravity.CENTER })
            failureText = label("PLAYBACK INTERRUPTED", 13f, PANEL).apply { gravity = Gravity.CENTER; setPadding(0, dp(8), 0, dp(12)) }
            addView(failureText)
            addView(InkButton(this@MainActivity, "RETRY", labelFace, RED, PANEL) {
                failure?.visibility = View.GONE
                player?.prepare()
                player?.play()
            }, LinearLayout.LayoutParams(-2, dp(44)))
            visibility = View.GONE
        }
        box.addView(failure, FrameLayout.LayoutParams(-1, -1))
        column.addView(box, LinearLayout.LayoutParams(-1, 0))

        // The panel: the inked seek bar, the time, play, next, PiP, full screen.
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(PANEL)
            setPadding(dp(12), dp(6), dp(8), dp(4))
        }
        controls = panel
        seek = InkSeekBar(this) { f ->
            val p = player ?: return@InkSeekBar
            if (p.duration > 0) p.seekTo((p.duration * f).toLong())
            scheduleHide()
        }
        panel.addView(seek, LinearLayout.LayoutParams(-1, dp(34)))
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        playButton = glyph(Glyphs.PAUSE, INK, "Play or pause") {
            val p = player ?: return@glyph
            if (p.isPlaying) p.pause() else p.play()
        }
        row.addView(playButton, LinearLayout.LayoutParams(dp(40), dp(44)))
        timeText = label("0:00 / 0:00", 13f, INK)
        row.addView(timeText, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(4) })
        if (data.optBoolean("has_next", false)) {
            row.addView(glyph(Glyphs.SKIP_NEXT, INK, "Next episode") { command("next") }, LinearLayout.LayoutParams(dp(48), dp(44)))
        }
        if (Build.VERSION.SDK_INT >= 26) {
            row.addView(glyph(Glyphs.PIP, INK, "Picture in picture") { enterPip() }, LinearLayout.LayoutParams(dp(48), dp(44)))
        }
        fullButton = glyph(Glyphs.FULLSCREEN, INK, "Full screen") { setFullscreen(!fullscreen) }
        row.addView(fullButton, LinearLayout.LayoutParams(dp(48), dp(44)))
        panel.addView(row, LinearLayout.LayoutParams(-1, -2))
        column.addView(View(this).apply { setBackgroundColor(INK) }, LinearLayout.LayoutParams(-1, dp(3)))
        column.addView(panel, LinearLayout.LayoutParams(-1, -2))
        val rest = View(this).apply { setOnClickListener { showHud(!hudShown) } }
        column.addView(rest, LinearLayout.LayoutParams(-1, 0, 1f))
        addContentView(root, ViewGroup.LayoutParams(-1, -1))
        watchInsets(root)
        root.post { layoutVideo() }
        applyCaptions()
        showHud(true)
    }

    /** Portrait: the video 16:9 under the bar. Full screen: it takes the room. */
    private fun layoutVideo() {
        val box = videoBox ?: return
        val root = overlay ?: return
        val params = box.layoutParams as LinearLayout.LayoutParams
        if (fullscreen) {
            params.height = 0
            params.weight = 1f
        } else {
            params.height = root.width * 9 / 16
            params.weight = 0f
        }
        box.layoutParams = params
        (box.parent as? LinearLayout)?.getChildAt((box.parent as LinearLayout).childCount - 1)?.visibility =
            if (fullscreen) View.GONE else View.VISIBLE
    }

    private fun setFullscreen(on: Boolean) {
        fullscreen = on
        fullButton?.data = if (on) Glyphs.FULLSCREEN_EXIT else Glyphs.FULLSCREEN
        requestedOrientation = if (on) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        if (Build.VERSION.SDK_INT >= 30) {
            window.insetsController?.let {
                if (on) it.hide(WindowInsets.Type.systemBars()) else it.show(WindowInsets.Type.systemBars())
            }
        }
        topBar?.setPadding(dp(4), if (on) 0 else insetTop, dp(8), 0)
        overlay?.post { layoutVideo() }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        overlay?.post { layoutVideo() }
    }

    private fun showHud(show: Boolean) {
        hudShown = show
        val v = if (show || isInPictureInPictureModeCompat()) View.VISIBLE else View.INVISIBLE
        topBar?.visibility = if (isInPictureInPictureModeCompat()) View.GONE else v
        controls?.visibility = if (isInPictureInPictureModeCompat()) View.GONE else v
        handler.removeCallbacks(hideHud)
        if (show) scheduleHide()
    }

    private fun scheduleHide() {
        handler.removeCallbacks(hideHud)
        handler.postDelayed(hideHud, 4000)
    }

    private fun toggleCaptions() {
        captions = !captions
        applyCaptions()
    }

    private fun applyCaptions() {
        val p = player ?: return
        p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !captions).build()
        ccButton?.setColors(if (captions) RED else PANEL, if (captions) PANEL else INK)
    }

    private fun chooseSpeed() {
        val p = player ?: return
        val speeds = floatArrayOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)
        val names = speeds.map { if (it == p.playbackParameters.speed) "● ${fmt(it)}×" else "${fmt(it)}×" }.toTypedArray()
        AlertDialog.Builder(this).setTitle("PLAYBACK SPEED").setItems(names) { _, i -> p.setPlaybackSpeed(speeds[i]) }.show()
    }

    private fun fmt(v: Float) = if (v == v.toInt().toFloat()) v.toInt().toString() else v.toString()

    /** Next episode or SUB ⇄ DUB: the overlay steps aside while Rust finds the stream. */
    private fun command(name: String) {
        stopStreamOnUiThread(reportClosed = false)
        runCatching { nativePlayerCommand(name) }
    }

    private fun skipTarget(): Long {
        val p = player ?: return -1
        val data = request ?: return -1
        val now = p.currentPosition
        val start = data.optLong("intro_start_ms", -1)
        val end = data.optLong("intro_end_ms", -1)
        val outroStart = data.optLong("outro_start_ms", -1)
        val outroEnd = data.optLong("outro_end_ms", -1)
        return when {
            start >= 0 && end > start && now in start until end -> end
            outroStart >= 0 && outroEnd > outroStart && now in outroStart until outroEnd -> outroEnd
            else -> -1
        }
    }

    private fun skip() {
        val target = skipTarget()
        if (target >= 0) player?.seekTo(target)
        playSfx("skip", 0.35f)
        updateSkipButton()
    }

    private fun updateSkipButton() {
        val target = skipTarget()
        val intro = request?.optLong("intro_end_ms", -2)
        skipButton?.apply {
            visibility = if (target >= 0 && !isInPictureInPictureModeCompat()) View.VISIBLE else View.GONE
            setText(if (target == intro) "SKIP INTRO" else "SKIP OUTRO")
        }
    }

    private fun updateTime(p: Player) {
        val duration = max(p.duration, 0)
        val position = max(p.currentPosition, 0)
        timeText?.text = "${clock(position)} / ${clock(duration)}"
        seek?.let { if (!it.dragging && duration > 0) it.fraction = position.toFloat() / duration }
    }

    private fun clock(ms: Long): String {
        val s = ms / 1000
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%d:%02d".format(m, sec)
    }

    private fun reportProgress(ended: Boolean = false, error: String? = null, closed: Boolean = false) {
        val data = request ?: return
        val p = player
        val event = JSONObject().put("anime_id", data.optString("anime_id"))
            .put("title", data.optString("title")).put("cover", data.optString("cover"))
            .put("episode", data.optInt("episode", 1))
            .put("position_ms", p?.currentPosition?.coerceAtLeast(0) ?: data.optLong("position_ms", 0))
            .put("duration_ms", p?.duration?.coerceAtLeast(0) ?: 0)
            .put("ended", ended)
            .put("closed", closed)
        if (error != null) event.put("error", error)
        runCatching { nativePlaybackEvent(event.toString()) }
    }

    fun pauseStream() = runOnUiThread { player?.pause(); reportProgress() }
    fun resumeStream() = runOnUiThread { player?.play() }
    fun seekStream(positionMs: Long) = runOnUiThread { player?.seekTo(positionMs.coerceAtLeast(0)) }
    fun stopStream() = runOnUiThread { stopStreamOnUiThread(reportClosed = true) }

    private fun stopStreamOnUiThread(reportClosed: Boolean) {
        handler.removeCallbacks(progress)
        handler.removeCallbacks(clock)
        handler.removeCallbacks(hideHud)
        if (request != null) reportProgress(closed = reportClosed)
        playerView?.player = null
        player?.release(); player = null
        (overlay?.parent as? ViewGroup)?.removeView(overlay)
        overlay = null; playerView = null; skipButton = null; failure = null; failureText = null; request = null
        topBar = null; controls = null; videoBox = null; seek = null; timeText = null; playButton = null
        fullButton = null; ccButton = null; buffering = null
        resumeAfterPause = false
        if (fullscreen) setFullscreen(false)
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= 26 && player != null) {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build())
        }
    }

    private fun isInPictureInPictureModeCompat() = Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        showHud(!isInPictureInPictureMode)
    }

    override fun onUserLeaveHint() {
        if (request?.optBoolean("pip_auto", true) == true && player?.isPlaying == true) enterPip()
        super.onUserLeaveHint()
    }

    override fun onPause() {
        reportProgress()
        if (!isInPictureInPictureModeCompat() && request?.optBoolean("bg_audio", false) != true) {
            resumeAfterPause = player?.isPlaying == true
            player?.pause()
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (resumeAfterPause) { player?.play(); resumeAfterPause = false }
    }

    /** Back: out of full screen, then out of the player, then Rust turns its pages. */
    @Deprecated("Android NativeActivity back compatibility")
    override fun onBackPressed() {
        when {
            fullscreen -> setFullscreen(false)
            player != null -> stopStreamOnUiThread(reportClosed = true)
            else -> runCatching { nativeBack() }.onFailure {
                @Suppress("DEPRECATION")
                super.onBackPressed()
            }
        }
    }

    override fun onDestroy() {
        stopStreamOnUiThread(reportClosed = true)
        sounds?.release()
        sounds = null
        super.onDestroy()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

/** A Material glyph in one colour, a little inside its box. */
class GlyphView(context: Context, data: String, private val tint: Int) : View(context) {
    private var path: Path = PathParser.createPathFromPathData(data)
    private val drawn = Path()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val scaling = Matrix()
    var data: String = data
        set(value) {
            field = value
            path = PathParser.createPathFromPathData(value)
            invalidate()
        }

    override fun onDraw(canvas: Canvas) {
        val s = min(width, height) * (if (isPressed) 0.5f else 0.6f) / 512f
        scaling.setScale(s, s)
        scaling.postTranslate((width - 512 * s) / 2, (height - 512 * s) / 2)
        path.transform(scaling, drawn)
        paint.color = tint
        canvas.drawPath(drawn, paint)
    }

    override fun drawableStateChanged() {
        super.drawableStateChanged()
        invalidate()
    }
}

/** InkButton: condensed capitals in a heavy ink frame with a hard shadow. Held, it drops onto it. */
class InkButton(context: Context, private var text: String, face: Typeface, private var fill: Int, private var fg: Int, private val onTap: () -> Unit) : View(context) {
    private val density = resources.displayMetrics.density
    private val shadow = 3 * density
    private val border = 2.5f * density
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = face
        textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 12f, resources.displayMetrics)
        letterSpacing = 0.02f
    }
    private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private var down = false

    init {
        isClickable = true
        contentDescription = text
    }

    fun setText(value: String) {
        if (value == text) return
        text = value
        contentDescription = value
        requestLayout()
        invalidate()
    }

    fun setColors(fill: Int, fg: Int) {
        this.fill = fill
        this.fg = fg
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = (textPaint.measureText(text) + 28 * density + shadow + border * 2).toInt()
        setMeasuredDimension(resolveSize(w, widthMeasureSpec), resolveSize((40 * density + shadow).toInt(), heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        val off = if (down) shadow else 0f
        val w = width - shadow
        val h = height - shadow
        if (!down) {
            boxPaint.color = INK
            boxPaint.style = Paint.Style.FILL
            rect.set(shadow, shadow, w + shadow, h + shadow)
            canvas.drawRect(rect, boxPaint)
        }
        rect.set(off, off, w + off, h + off)
        boxPaint.color = fill
        boxPaint.style = Paint.Style.FILL
        canvas.drawRect(rect, boxPaint)
        boxPaint.color = INK
        boxPaint.style = Paint.Style.STROKE
        boxPaint.strokeWidth = border
        rect.inset(border / 2, border / 2)
        canvas.drawRect(rect, boxPaint)
        textPaint.color = fg
        val y = off + h / 2 - (textPaint.descent() + textPaint.ascent()) / 2
        canvas.drawText(text, off + (w - textPaint.measureText(text)) / 2, y, textPaint)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { down = true; invalidate() }
            MotionEvent.ACTION_UP -> {
                down = false
                invalidate()
                (context as? MainActivity)?.playSfx("click", 0.35f)
                performClick()
                onTap()
            }
            MotionEvent.ACTION_CANCEL -> { down = false; invalidate() }
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }
}

/** The seek bar as an inked strip: red ink filling it, a red thumb ringed in ink. */
class InkSeekBar(context: Context, private val onSeek: (Float) -> Unit) : View(context) {
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    var dragging = false
        private set
    var fraction = 0f
        set(value) {
            field = value.coerceIn(0f, 1f)
            invalidate()
        }
    var buffered = 0f
        set(value) {
            field = value.coerceIn(0f, 1f)
            invalidate()
        }

    override fun onDraw(canvas: Canvas) {
        val pad = 10 * density
        val h = 10 * density
        val top = (height - h) / 2
        val left = pad
        val right = width - pad
        val border = 2.5f * density
        rect.set(left, top, right, top + h)
        paint.style = Paint.Style.FILL
        paint.color = PANEL
        canvas.drawRect(rect, paint)
        paint.color = 0xFFD6CFC2.toInt()
        canvas.drawRect(left, top, left + (right - left) * buffered, top + h, paint)
        paint.color = RED
        canvas.drawRect(left, top, left + (right - left) * fraction, top + h, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = border
        paint.color = INK
        canvas.drawRect(rect, paint)
        val x = left + (right - left) * fraction
        val r = 8 * density
        paint.style = Paint.Style.FILL
        paint.color = RED
        canvas.drawCircle(x, height / 2f, r, paint)
        paint.style = Paint.Style.STROKE
        paint.color = INK
        canvas.drawCircle(x, height / 2f, r, paint)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val pad = 10 * density
        val f = ((event.x - pad) / (width - 2 * pad)).coerceIn(0f, 1f)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                dragging = true
                parent?.requestDisallowInterceptTouchEvent(true)
                fraction = f
            }
            MotionEvent.ACTION_UP -> {
                dragging = false
                fraction = f
                onSeek(f)
            }
            MotionEvent.ACTION_CANCEL -> dragging = false
        }
        return true
    }
}
