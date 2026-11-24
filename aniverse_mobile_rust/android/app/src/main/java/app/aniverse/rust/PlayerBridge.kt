package app.aniverse.rust

/** Kept as a small Android-facing adapter; the payload is PlaybackRequest JSON. */
class PlayerBridge(private val activity: MainActivity) {
    fun play(requestJson: String) = activity.playStream(requestJson)
    fun pause() = activity.pauseStream()
    fun resume() = activity.resumeStream()
    fun seek(positionMs: Long) = activity.seekStream(positionMs)
    fun stop() = activity.stopStream()
}
