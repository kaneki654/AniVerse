package com.example.aniverse_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * New-episode alerts for My List while the app is closed. A periodic job reads
 * the list the Dart side keeps in SharedPreferences (av.watchlist.v1), asks
 * AniList in one request how many episodes each show has out, and posts a
 * notification for any show with more than when it was last looked at.
 * Shows muted on My List (av.alertsMuted) are skipped, and nothing is posted
 * during the quiet hours set in Settings: the next run after them catches up.
 * Tapping the notification opens the new episode itself.
 */
object AlertCheck {
    const val EXTRA_ANIME = "aniverse.anime_id"
    const val EXTRA_EPISODE = "aniverse.episode"

    // shared_preferences stores a Dart double as a string behind this marker.
    private const val DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"

    private fun prefNumber(prefs: android.content.SharedPreferences, key: String, fallback: Double): Double =
        when (val v = prefs.all["flutter.$key"]) {
            is String -> v.removePrefix(DOUBLE_PREFIX).toDoubleOrNull() ?: fallback
            is Number -> v.toDouble()
            else -> fallback
        }

    /** Whether the hour now falls in the quiet hours (from..to, across midnight too). */
    fun quietNow(prefs: android.content.SharedPreferences, hour: Int): Boolean {
        val from = prefNumber(prefs, "av.quietFrom", -1.0).toInt()
        val to = prefNumber(prefs, "av.quietTo", 8.0).toInt()
        if (from < 0 || from == to) return false
        return if (from < to) hour in from until to else hour >= from || hour < to
    }
    private const val JOB_ID = 1907
    private const val CHANNEL = "episodes"
    private const val PREFS = "FlutterSharedPreferences"
    private const val SEEN = "aniverse_alerts"

    fun schedule(ctx: Context) {
        val js = ctx.getSystemService(JobScheduler::class.java) ?: return
        if (js.getPendingJob(JOB_ID) != null) return
        js.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(ctx, AlertJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(TimeUnit.HOURS.toMillis(3))
                .setPersisted(true)
                .build()
        )
    }

    fun cancel(ctx: Context) {
        ctx.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID)
    }

    /** One check; returns how many notifications it posted. Runs off the main thread. */
    fun run(ctx: Context): Int {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.av.alerts", false)) return 0
        if (quietNow(prefs, java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY))) return 0
        val raw = prefs.getString("flutter.av.watchlist.v1", null) ?: return 0
        val muted = HashSet<String>()
        try {
            val m = JSONArray(prefs.getString("flutter.av.alertsMuted", null) ?: "[]")
            for (i in 0 until m.length()) muted.add(m.getString(i))
        } catch (_: Exception) {
        }
        val follows = HashMap<Int, Pair<String, Int>>() // id -> (title, seen episode)
        try {
            val list = JSONArray(raw)
            for (i in 0 until list.length()) {
                val e = list.getJSONObject(i)
                if (e.optBoolean("deleted")) continue
                val id = e.optString("anime_id").toIntOrNull() ?: continue
                if (id.toString() in muted) continue
                follows[id] = e.optString("title") to e.optInt("seen_episode")
            }
        } catch (_: Exception) {
            return 0
        }
        if (follows.isEmpty()) return 0

        val media = fetch(follows.keys.take(50)) ?: return 0
        val seen = ctx.getSharedPreferences(SEEN, Context.MODE_PRIVATE)
        var posted = 0
        for (i in 0 until media.length()) {
            val m = media.getJSONObject(i)
            val id = m.optInt("id")
            val (title, seenEp) = follows[id] ?: continue
            val aired = airedEpisodes(m) ?: continue
            // Seen 0 means followed before anything aired; the first episode is news too.
            val notified = seen.getInt("n_$id", 0)
            if (aired <= seenEp || aired <= notified) continue
            val name = m.optJSONObject("title")?.let { t ->
                t.optString("english").takeIf { it.isNotBlank() && it != "null" } ?: t.optString("romaji")
            }?.takeIf { it.isNotBlank() && it != "null" } ?: title
            notify(ctx, id, name, aired, aired - maxOf(seenEp, notified))
            seen.edit().putInt("n_$id", aired).apply()
            posted++
        }
        return posted
    }

    /** As the app works it out: the episode before the next to air, or all of them once finished. */
    private fun airedEpisodes(m: JSONObject): Int? {
        val next = m.optJSONObject("nextAiringEpisode")
        if (next != null) return (next.optInt("episode") - 1).takeIf { it >= 0 }
        return when (m.optString("status")) {
            "FINISHED" -> m.optInt("episodes").takeIf { it > 0 }
            else -> null // airing without a schedule, or not started: nothing to say
        }
    }

    private fun fetch(ids: List<Int>): JSONArray? {
        val query = "query (\$ids: [Int]) { Page(perPage: 50) { media(id_in: \$ids, type: ANIME) " +
            "{ id status episodes nextAiringEpisode { episode } title { english romaji } } } }"
        val body = JSONObject().put("query", query).put("variables", JSONObject().put("ids", JSONArray(ids)))
        return try {
            val c = URL("https://graphql.anilist.co").openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 15000
            c.readTimeout = 15000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json")
            c.setRequestProperty("Accept", "application/json")
            c.outputStream.use { it.write(body.toString().toByteArray()) }
            if (c.responseCode != 200) return null
            val text = c.inputStream.bufferedReader().use { it.readText() }
            JSONObject(text).getJSONObject("data").getJSONObject("Page").getJSONArray("media")
        } catch (_: Exception) {
            null
        }
    }

    private fun notify(ctx: Context, id: Int, title: String, episode: Int, fresh: Int) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "New episodes", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "A show on My List has a new episode out"
                }
            )
        }
        val open = Intent(ctx, MainActivity::class.java)
            .putExtra(EXTRA_ANIME, id.toString())
            .putExtra(EXTRA_EPISODE, episode)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(ctx, id, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val text = if (fresh > 1) "$fresh new episodes, up to episode $episode" else "Episode $episode is out"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(ctx, CHANNEL)
        else @Suppress("DEPRECATION") Notification.Builder(ctx)
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_alert)
            .setContentTitle(title)
            .setContentText(text)
            .setColor(0xFFD10A1A.toInt())
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(id, n)
        } catch (_: SecurityException) {
            // Notifications switched off for the app since the alert was turned on.
        }
    }
}

/** The periodic job: the check, on a thread, then done. */
class AlertJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        Thread {
            AlertCheck.run(applicationContext)
            jobFinished(params, false)
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true
}
