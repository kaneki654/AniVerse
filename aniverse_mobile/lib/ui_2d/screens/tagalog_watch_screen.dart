import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../../services/history_service.dart';
import '../../services/native_bridge.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_logo.dart';
import '../theme_2d.dart';
import '../widgets/pixel_extras.dart';
import 'watch_screen.dart';

/// An episode's official Tagalog dub, in YouTube's own player.
///
/// The dubs are the Philippine licensees' (Muse Philippines, Ani-One
/// Philippines), free on their YouTube channels and licensed for the
/// Philippines. They play in YouTube's embedded player -- the server's
/// /tagalog/{id}/{ep} page (app/tagalog.py) in a web view -- so the views and
/// the ads stay with the channel. The page reports where playback is, which
/// keeps watch history, Continue Watching and the achievements working.
class TagalogWatchScreen extends StatefulWidget {
  final String animeId;
  final int epNum;
  final String? title;
  final String? cover;

  /// {channel, episodes: {"1": youtube id}}, from ApiService.tagalog.
  final Map<String, dynamic> dub;

  const TagalogWatchScreen({
    super.key,
    required this.animeId,
    required this.epNum,
    required this.dub,
    this.title,
    this.cover,
  });

  @override
  State<TagalogWatchScreen> createState() => _TagalogWatchScreenState();
}

class _TagalogWatchScreenState extends State<TagalogWatchScreen> {
  late final WebViewController _web;
  String? _error;
  bool _awake = false;
  bool _leaving = false;

  Map<String, dynamic> get _episodes => Map<String, dynamic>.from(widget.dub['episodes'] as Map? ?? const {});
  String get _channel => (widget.dub['channel'] ?? 'the channel').toString();
  String? get _video => _episodes['${widget.epNum}']?.toString();
  bool _has(int ep) => _episodes.containsKey('$ep');

  @override
  void initState() {
    super.initState();
    AppSettings.setTagalogFor(widget.animeId, true);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final saved = HistoryService.progressFor(widget.animeId, widget.epNum);
    final start = saved != null && !saved.finished && saved.positionMs > 10000 ? saved.positionMs ~/ 1000 : 0;
    final page = Uri.parse('${ApiService.webUrl}/tagalog/${widget.animeId}/${widget.epNum}?start=$start');
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('AniVerse', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // The player page stays the page; a tap through to YouTube itself
        // (its logo, a channel link) opens the YouTube app instead.
        onNavigationRequest: (r) {
          if (r.isMainFrame && !r.url.startsWith(ApiService.webUrl)) {
            launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) setState(() => _error = "Couldn't reach the AniVerse server.");
        },
      ))
      ..loadRequest(page);
    final android = _web.platform;
    if (android is AndroidWebViewController) {
      // Start without a tap; and YouTube's full-screen button opens a page of its own.
      android.setMediaPlaybackRequiresUserGesture(false);
      android.setCustomWidgetCallbacks(
        onShowCustomWidget: (widget, onHidden) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _FullScreen(onHidden: onHidden, child: widget),
        )),
        onHideCustomWidget: () {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      );
    }
  }

  void _onMessage(String raw) {
    Map m;
    try {
      m = json.decode(raw) as Map;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'progress':
        final t = (m['t'] as num?)?.toDouble() ?? 0, d = (m['d'] as num?)?.toDouble() ?? 0;
        if (d > 0) {
          HistoryService.record(
            animeId: widget.animeId,
            episode: widget.epNum,
            title: widget.title,
            cover: widget.cover,
            position: Duration(milliseconds: (t * 1000).round()),
            duration: Duration(milliseconds: (d * 1000).round()),
          );
        }
        final playing = m['playing'] == true;
        if (playing != _awake) {
          _awake = playing;
          NativeBridge.keepScreenOn(playing);
        }
      case 'ended':
        if (_has(widget.epNum + 1) && !_leaving) {
          _leaving = true;
          pixelToast(context, 'Next: EP ${widget.epNum + 1} in Tagalog.');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _go(widget.epNum + 1);
          });
        }
      case 'error':
        final code = (m['code'] as num?)?.toInt();
        setState(() => _error = (code == 100 || code == 101 || code == 150)
            ? "This Tagalog dub can't play here: $_channel licenses it for the Philippines only."
            : "YouTube couldn't play this episode (error $code).");
    }
  }

  void _go(int ep) => Navigator.of(context).pushReplacement(FadeScaleRoute(
        backdrop: false,
        page: TagalogWatchScreen(animeId: widget.animeId, epNum: ep, dub: widget.dub, title: widget.title, cover: widget.cover),
      ));

  void _openInYouTube() {
    final v = _video;
    if (v != null) launchUrl(Uri.parse('https://www.youtube.com/watch?v=$v'), mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    HistoryService.flush();
    if (_awake) NativeBridge.keepScreenOn(false);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setEnabledSystemUIMode(landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    final player = Stack(children: [
      Positioned.fill(child: WebViewWidget(controller: _web)),
      if (_error != null)
        Positioned.fill(
          child: ColoredBox(
            color: Px.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center, style: PxFont.text(15, height: 1.4)),
                  const SizedBox(height: 16),
                  PixelButton(label: 'Open in YouTube', icon: Sprites.play, fontSize: 8, onPressed: _openInYouTube),
                ]),
              ),
            ),
          ),
        ),
    ]);
    // Turned sideways, the video is the whole screen.
    if (landscape) return Scaffold(backgroundColor: Colors.black, body: player);

    final eps = _episodes.keys.map(int.parse).toList()..sort();
    return Scaffold(
      backgroundColor: Px.ink,
      appBar: AppBar(
        title: Text('EP ${widget.epNum} · TAGALOG', style: PxFont.label(10)),
        actions: [
          // Back to the usual streams (and this show stops opening in Tagalog).
          PixelButton(
            label: 'Sub / Dub',
            kind: PixelButtonKind.dark,
            fontSize: 7,
            onPressed: () {
              AppSettings.setTagalogFor(widget.animeId, false);
              Navigator.of(context).pushReplacement(FadeScaleRoute(
                backdrop: false,
                page: WatchScreen(animeId: widget.animeId, epNum: widget.epNum, title: widget.title, cover: widget.cover),
              ));
            },
          ),
          PixelIconButton(
            sprite: Sprites.play,
            tooltip: 'Open in the YouTube app',
            color: Px.ash,
            onPressed: _openInYouTube,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(aspectRatio: 16 / 9, child: player),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              Text((widget.title ?? '').toUpperCase(), style: PxFont.label(10)),
              const SizedBox(height: 8),
              Text(
                'Official Tagalog dub from $_channel on YouTube, licensed for the Philippines. '
                'Turn the phone sideways for full screen.',
                style: PxFont.text(14, color: Px.ash, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(children: [
                if (_has(widget.epNum - 1))
                  PixelButton(label: 'EP ${widget.epNum - 1}', kind: PixelButtonKind.dark, fontSize: 8, onPressed: () => _go(widget.epNum - 1)),
                const Spacer(),
                if (_has(widget.epNum + 1))
                  PixelButton(label: 'EP ${widget.epNum + 1}', icon: Sprites.skipNext, fontSize: 8, onPressed: () => _go(widget.epNum + 1)),
              ]),
              const SizedBox(height: 18),
              SectionHeader(title: 'Tagalog episodes'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in eps)
                  PixelButton(
                    label: '$e',
                    kind: e == widget.epNum ? PixelButtonKind.blood : PixelButtonKind.dark,
                    fontSize: 8,
                    onPressed: e == widget.epNum ? null : () => _go(e),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// YouTube's own full-screen view, from its full-screen button.
class _FullScreen extends StatefulWidget {
  final Widget child;
  final VoidCallback onHidden;
  const _FullScreen({required this.child, required this.onHidden});

  @override
  State<_FullScreen> createState() => _FullScreenState();
}

class _FullScreenState extends State<_FullScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  @override
  void dispose() {
    widget.onHidden();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: Center(child: widget.child));
}
