package com.example.aniverse_mobile

import android.net.TrafficStats
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
