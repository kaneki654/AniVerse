import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/api_service.dart';
import '../services/download_service.dart';
import '../services/native_bridge.dart';
import '../services/history_service.dart';
import '../services/net_speed.dart';
import '../theme.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/buffer_overlay.dart';
import '../widgets/player_controls.dart';

class WatchScreen extends StatefulWidget {
  final String animeId;
  final int epNum;

  /// Shown in watch history. Optional so any caller can open an episode, but
  /// without them the history row has no title or poster until the next watch.
  final String? title;
  final String? cover;

  const WatchScreen({
    super.key,
    required this.animeId,
    required this.epNum,
    this.title,
    this.cover,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

enum _Phase {
  /// Asking the server which streams exist.
  resolving,

  /// Streams found; opening one in the player.
  opening,

  playing,

  /// The stream died mid-episode; trying to get it back.
  reconnecting,

  /// Nothing could be played.
  failed,
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// The player that died, kept on screen (paused) so the last frame stays
  /// behind the reconnect circle instead of a black box.
  VideoPlayerController? _stale;

  _Phase _phase = _Phase.resolving;
  String category = 'sub';
  Map<String, dynamic>? _intro;
  Map<String, dynamic>? _outro;
  bool? _hasDub;
  List<Map<String, dynamic>> _sources = const [];
  int _sourceIndex = 0;
  String? _failReason;
  bool _secondLook = false;

  /// Set while asking the server for a new link because the one it gave us
  /// would not play.
  bool _refreshing = false;

  /// Bumped whenever earlier async work must stop mattering (new episode
  /// load, category switch, dispose), so a late reply cannot attach a player.
  int _generation = 0;

  // Reconnection.
  int _attempt = 0;
  bool _attemptInFlight = false;
  Timer? _retryTimer;
  DateTime? _retryAt;
  Duration _resumeAt = Duration.zero;

  // Stall detection and the buffering circle.
  Timer? _watchdog;
  DateTime? _bufferingSince;
  Duration _bufferedEnd = Duration.zero;
  DateTime _bufferProgressAt = DateTime.now();
  bool _wasBuffering = false;

  /// Bytes received when the buffered position last moved. HLS only reports a
  /// segment as buffered once all of it has arrived, so on a slow link the
  /// buffered position sits still for many seconds; counting the bytes since
  /// then is what lets the water rise while a segment is still downloading.
  int? _rxAtBufferAdvance;

  /// Learned from normal playback: bytes downloaded per second of video. Used
  /// to turn "bytes so far" into "seconds of video so far". The default is a
  /// typical 1080p stream (~1.2 Mbps) until the first real measurement.
  double _bytesPerMediaSecond = 150000;
  bool _bufferVisible = false;
  bool _bufferFinishing = false;
  Timer? _bufferShowTimer;
  Timer? _bufferHideTimer;

  // History.
  Timer? _historyTimer;
  Duration _lastGoodPosition = Duration.zero;
  bool _wasPlaying = false;

  final NetSpeedMeter _speed = NetSpeedMeter();

  /// How far the stream being opened is toward playing, 0..1, measured from
  /// what is really arriving. Drives the orb on the loading and reconnecting
  /// screens, which used to be handed no progress at all and so idled at a
  /// quarter full however much had downloaded.
  final ValueNotifier<double> _openProgress = ValueNotifier<double>(0);
  Timer? _openTicker;

  /// Whether a stream is being opened right now, rather than waiting on the
  /// server or a retry timer -- only then does the orb have something real to
  /// show.
  bool _openingStream = false;

  /// While the loading stage hands its orb to the player: the level the
  /// player's orb starts from, so it tops off from where the load had got to
  /// instead of starting empty.
  double? _bufferStartLevel;
  String _bufferLabel = 'BUFFERING';

  bool _immersive = false;
  bool _awake = false;

  /// ExoPlayer resumes after a stall once it holds this much video
  /// (DefaultLoadControl's bufferForPlaybackAfterRebufferMs), so the circle is
  /// full exactly when playback comes back.
  static const _resumeBuffer = Duration(seconds: 5);

  /// How long the player may sit buffering with no new data arriving before it
  /// is torn down and reopened. ExoPlayer usually gives up with an error well
  /// before this; this catches the connections that hang instead.
  static const _stallTimeout = Duration(seconds: 20);

  static const _retryDelays = [1, 2, 4, 8, 10];

  /// What ExoPlayer holds before it first starts (DefaultLoadControl's
  /// bufferForPlaybackMs).
  static const _startBuffer = Duration(milliseconds: 2500);

  /// Media seconds' worth of bytes a stream typically downloads before it can
  /// start: the playlists, then most of the first segment.
  static const _startupMediaSeconds = 6.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Rotation is what drives fullscreen, so landscape has to be allowed while
    // a video is open. The rest of the app stays portrait, which is why this is
    // set here and undone in dispose rather than in main().
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _speed.start();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _checkHealth());
    _historyTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    NativeBridge.onMedia = _onMedia;
    _resolve();
  }

  // --- finding and opening a stream -----------------------------------------------

  Future<void> _resolve() async {
    final gen = ++_generation;
    setState(() {
      _phase = _Phase.resolving;
      _failReason = null;
      _secondLook = false;
      _refreshing = false;
    });

    // A saved copy (classic_plus Downloads) plays without the server.
    final copy = DownloadService.find(widget.animeId, widget.epNum, category: category);
    if (copy != null && copy.done) {
      final path = await DownloadService.mediaPath(copy);
      if (gen != _generation || !mounted) return;
      _sources = [
        {'url': Uri.file(path).toString(), 'serverName': 'Downloaded', 'isM3U8': path.endsWith('.m3u8')},
      ];
      _intro = copy.intro;
      _outro = copy.outro;
      final p = HistoryService.progressFor(widget.animeId, widget.epNum);
      final from = (p != null && p.positionMs > 10000 && !p.finished) ? p.position : Duration.zero;
      setState(() => _phase = _Phase.opening);
      if (await _openFirstWorking(start: from, gen: gen)) return;
      if (gen != _generation || !mounted) return;
    }

    var data = await ApiService.getSources(widget.animeId, widget.epNum, category);
    if (gen != _generation || !mounted) return;

    // The resolver no longer caches failures and its providers time out now
    // and then, so one more look often finds what the first one missed.
    if ((data['sources'] as List).isEmpty && data['offline'] != true) {
      setState(() => _secondLook = true);
      await Future.delayed(const Duration(seconds: 2));
      if (gen != _generation || !mounted) return;
      data = await ApiService.getSources(widget.animeId, widget.epNum, category);
      if (gen != _generation || !mounted) return;
    }

    _applySourceData(data);
    if (_sources.isEmpty) {
      return _fail(_explain(data));
    }

    final saved = HistoryService.progressFor(widget.animeId, widget.epNum);
    final start = (saved != null && saved.positionMs > 10000 && !saved.finished)
        ? saved.position
        : Duration.zero;

    setState(() => _phase = _Phase.opening);
    var opened = await _openFirstWorking(start: start, gen: gen);
    if (gen != _generation || !mounted) return;

    if (!opened) {
      // The server can answer from a cache whose links have died since -- their
      // tokens expire, and some are tied to the server's IP, so a router
      // reconnect kills them all. That is exactly the "Wi-Fi dropped, came
      // back, now nothing plays" case, and it used to end here with an error.
      // Ask for new links before telling the user anything.
      final tried = _sources.length;
      setState(() {
        _phase = _Phase.resolving;
        _refreshing = true;
      });
      final fresh = await ApiService.getSources(
          widget.animeId, widget.epNum, category, fresh: true);
      if (gen != _generation || !mounted) return;
      if ((fresh['sources'] as List).isEmpty) {
        return _fail(fresh['offline'] == true
            ? _explain(fresh)
            : 'The server found $tried stream${tried == 1 ? '' : 's'}, but none '
                'of them would play, and a fresh search found nothing new. '
                'Try again in a moment.');
      }
      _applySourceData(fresh);
      setState(() {
        _phase = _Phase.opening;
        _refreshing = false;
      });
      opened = await _openFirstWorking(start: start, gen: gen);
      if (gen != _generation || !mounted) return;
    }

    if (!opened) {
      return _fail('The server found ${_sources.length} stream'
          '${_sources.length == 1 ? '' : 's'}, but none of them would play, '
          'even with fresh links. Try again in a moment.');
    }
    if (start > Duration.zero) _offerStartOver(start);
  }

  void _applySourceData(Map<String, dynamic> data) {
    _sources = [
      for (final s in (data['sources'] as List? ?? const []))
        if ((s as Map)['url'].toString().isNotEmpty) Map<String, dynamic>.from(s),
    ];
    _intro = data['intro'] as Map<String, dynamic>?;
    _outro = data['outro'] as Map<String, dynamic>?;
    _hasDub = data['hasDub'] as bool?;
  }

  String _explain(Map<String, dynamic> data) {
    if (data['offline'] == true) {
      return "Can't reach the AniVerse server. Check your connection, "
          'or the server address in Settings.';
    }
    if (category == 'dub' && _hasDub == false) {
      return 'This episode has no English dub yet.';
    }
    final err = (data['error'] ?? '').toString();
    if (err.isEmpty || err.contains('sources available')) {
      return 'No working ${category.toUpperCase()} stream was found for this '
          'episode right now. Streams come and go, so trying again in a minute '
          'often works.';
    }
    return err;
  }

  void _fail(String reason) {
    setState(() {
      _phase = _Phase.failed;
      _failReason = reason;
    });
  }

  /// Try the sources in order, starting with [first], and attach the first that
  /// opens. A single failing server used to end the attempt even when a working
  /// one sat next in the list.
  Future<bool> _openFirstWorking({
    required Duration start,
    required int gen,
    int first = 0,
  }) async {
    for (var i = 0; i < _sources.length; i++) {
      final index = (first + i) % _sources.length;
      final c = await _open(_sources[index], start);
      if (gen != _generation || !mounted) {
        await c?.dispose();
        return false;
      }
      if (c != null) {
        _attach(c, index);
        return true;
      }
    }
    return false;
  }

  Future<VideoPlayerController?> _open(Map<String, dynamic> source, Duration start) async {
    final url = source['url'].toString();
    // ExoPlayer infers the container from the URL's extension, and the proxied
    // URL is "/proxy/m3u8?url=..." with no ".m3u8" on the path, so without this
    // hint it runs progressive MP4 extractors over an HLS playlist and fails
    // with "None of the available extractors could read the stream".
    final isHls = source['isM3U8'] == true || url.contains('m3u8');
    final c = url.startsWith('file://')
        ? VideoPlayerController.file(File(Uri.parse(url).toFilePath()))
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            formatHint: isHls ? VideoFormat.hls : null,
          );

    final rx0 = _speed.totalBytes;
    final began = DateTime.now();
    _openProgress.value = 0.03;
    _openingStream = true;
    _openTicker?.cancel();
    _openTicker = Timer.periodic(
        const Duration(milliseconds: 250), (_) => _trackOpening(c, start, rx0, began));
    try {
      // initialize() waits for the first frames, and on a dead connection it
      // can wait forever -- the bound is what lets the next source get a turn.
      await c.initialize().timeout(const Duration(seconds: 45));
      if (start > Duration.zero && start < c.value.duration) {
        await c.seekTo(start);
        await _waitUntilPlayable(c);
      }
      _trackOpening(c, start, rx0, began);
      return c;
    } catch (e) {
      debugPrint('source ${source['serverName']} failed: $e');
      await c.dispose();
      return null;
    } finally {
      _openTicker?.cancel();
      _openTicker = null;
      _openingStream = false;
    }
  }

  /// Moves the loading orb from what is really arriving for the stream being
  /// opened. Two measures, whichever is further along:
  ///  - bytes received since the attempt began, which move from the first
  ///    playlist request on, long before the player reports anything;
  ///  - once the player reports video buffered where it will start, how much
  ///    of the start-up buffer it already holds -- the direct measure.
  /// It only ever rises, and stops short of full: only the video actually
  /// starting tops it off.
  void _trackOpening(VideoPlayerController c, Duration start, int? rx0, DateTime began) {
    if (!mounted) return;
    final resuming = start > Duration.zero;

    double byBytes = 0;
    final rx = _speed.totalBytes;
    if (rx != null && rx0 != null) {
      // A resume downloads twice: the opening, then again at the saved spot.
      final expected = _bytesPerMediaSecond * _startupMediaSeconds * (resuming ? 2 : 1);
      byBytes = 1 - math.exp(-math.max(0, rx - rx0) / expected);
    }

    double byBuffer = 0;
    final v = c.value;
    // Before the resume seek the buffer is at the opening, which is not where
    // playback will start, so it only counts once the seek has happened.
    if (!resuming || v.position >= start - const Duration(seconds: 1)) {
      var end = Duration.zero;
      for (final r in v.buffered) {
        if (r.start <= v.position + const Duration(seconds: 1) && r.end > end) end = r.end;
      }
      final ahead = (end - v.position).inMilliseconds / _startBuffer.inMilliseconds;
      byBuffer = ahead.clamp(0.0, 1.0).toDouble();
    }

    // Devices that do not report traffic still see the orb creep, rather than
    // freeze at the start for a load that is going fine.
    final secs = DateTime.now().difference(began).inMilliseconds / 1000;
    final byTime = 0.5 * (1 - math.exp(-secs / 15));

    final p = (0.03 + 0.92 * math.max(byBytes, math.max(byBuffer, byTime))).clamp(0.0, 0.95);
    if (p > _openProgress.value) _openProgress.value = p;
  }

  /// After a resume seek ExoPlayer drops what it buffered at the opening and
  /// buffers again at the saved position. Handing the player over before that
  /// finished meant a second, separate load behind the orb -- which then
  /// looked like the loading had gone backwards. Bounded, so a player that
  /// never reports its state cannot hold the screen.
  Future<void> _waitUntilPlayable(VideoPlayerController c) async {
    // Long enough for the seek to register as buffering.
    await Future.delayed(const Duration(milliseconds: 400));
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final v = c.value;
      if (v.hasError) throw StateError(v.errorDescription ?? 'playback error after seek');
      if (!v.isBuffering) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _attach(VideoPlayerController c, int index) {
    final from = _phase;
    final old = _controller;
    old?.removeListener(_onValue);
    _controller = c;
    _sourceIndex = index;
    _bufferedEnd = Duration.zero;
    _bufferProgressAt = DateTime.now();
    _bufferingSince = null;
    _rxAtBufferAdvance = _speed.totalBytes;
    c.addListener(_onValue);
    c.play();
    setState(() {
      _phase = _Phase.playing;
      _attempt = 0;
      _retryAt = null;
    });
    if (from == _Phase.opening || from == _Phase.reconnecting) _handOffOrb();
    // The frozen frame has done its job once the new player is up.
    final stale = _stale;
    _stale = null;
    if (old != null && old != stale) old.dispose();
    stale?.dispose();
  }

  /// Carry the loading orb into the player so it visibly fills to the top and
  /// fades as the video starts. It used to vanish the instant the player
  /// opened, at whatever level it had reached, so the fill never completed.
  void _handOffOrb() {
    _bufferShowTimer?.cancel();
    _bufferHideTimer?.cancel();
    setState(() {
      _bufferStartLevel = _openProgress.value;
      _bufferLabel = 'LOADING VIDEO';
      _bufferVisible = true;
      _bufferFinishing = true;
    });
    _bufferHideTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _bufferStartLevel = null;
        _bufferLabel = 'BUFFERING';
        _bufferFinishing = false;
        // A real stall that began meanwhile keeps the orb up, now measuring it.
        _bufferVisible = _wasBuffering;
      });
    });
  }

  void _offerStartOver(Duration from) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Resumed from ${_fmt(from)}'),
        duration: const Duration(seconds: 5),
        // A SnackBar with an action otherwise stays until dismissed, which
        // left this sitting over the video for the whole episode.
        persist: false,
        action: SnackBarAction(
          label: 'START OVER',
          textColor: AniVerseTheme.red,
          onPressed: () => _controller?.seekTo(Duration.zero),
        ),
      ),
    );
  }

  // --- watching the player -----------------------------------------------------------

  void _onValue() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;

    _syncWakelock(v.isPlaying);

    if (v.hasError) {
      _startReconnect();
      return;
    }
    if (v.position > Duration.zero) _lastGoodPosition = v.position;

    // New data arriving is what separates a slow connection from a dead one.
    final end = _bufferedEndOf(v);
    if (end > _bufferedEnd) {
      _learnBitrate(end);
      _bufferedEnd = end;
      _bufferProgressAt = DateTime.now();
      _rxAtBufferAdvance = _speed.totalBytes;
    } else if (end < _bufferedEnd - const Duration(seconds: 1)) {
      // Seeked back, or ExoPlayer dropped its buffer: start counting afresh,
      // otherwise nothing registers as progress until it passes the old mark.
      _bufferedEnd = end;
      _bufferProgressAt = DateTime.now();
      _rxAtBufferAdvance = _speed.totalBytes;
    }

    if (v.isBuffering != _wasBuffering) {
      _wasBuffering = v.isBuffering;
      v.isBuffering ? _bufferingStarted() : _bufferingEnded();
    }

    // Save on pause as well as on the timer, so stopping mid-episode and
    // closing the app keeps the exact spot.
    if (_wasPlaying && !v.isPlaying) _saveProgress();
    if (_wasPlaying != v.isPlaying) _syncSession(v);
    _wasPlaying = v.isPlaying;
  }

  void _learnBitrate(Duration newEnd) {
    final rx = _speed.totalBytes;
    final since = _rxAtBufferAdvance;
    // The first advance after opening covers the whole start-up buffer plus
    // API traffic, so it says little about the stream; skip it.
    if (rx == null || since == null || _bufferedEnd == Duration.zero) return;
    final seconds = (newEnd - _bufferedEnd).inMilliseconds / 1000;
    final bytes = rx - since;
    if (seconds < 1 || bytes <= 0) return;
    final rate = bytes / seconds;
    // 0.1 to 12 Mbps of video is plausible; anything else is a seek or other
    // traffic, not the stream's bitrate.
    if (rate < 12000 || rate > 1500000) return;
    _bytesPerMediaSecond = _bytesPerMediaSecond * 0.7 + rate * 0.3;
  }

  /// How close the player is to resuming, 0..1: video already buffered ahead,
  /// plus the part of the next segment that has arrived but is not counted yet.
  double _bufferFill(VideoPlayerValue v) {
    final aheadMs = math.max(0, (_bufferedEndOf(v) - v.position).inMilliseconds);
    final rx = _speed.totalBytes;
    final since = _rxAtBufferAdvance;
    final inFlight = (rx != null && since != null) ? math.max(0, rx - since) : 0;
    final have = aheadMs / 1000 * _bytesPerMediaSecond + inFlight;
    final need = _resumeBuffer.inMilliseconds / 1000 * _bytesPerMediaSecond;
    // Held just short of full: only playback actually resuming tops it off.
    return (have / need).clamp(0.0, 0.97);
  }

  static Duration _bufferedEndOf(VideoPlayerValue v) {
    var end = Duration.zero;
    for (final r in v.buffered) {
      if (r.end > end && r.start <= v.position + const Duration(seconds: 1)) end = r.end;
    }
    return end;
  }

  void _bufferingStarted() {
    _bufferingSince = DateTime.now();
    _bufferProgressAt = DateTime.now();
    _rxAtBufferAdvance ??= _speed.totalBytes;
    // Mid hand-off from the loading stage: let it finish. It checks for a
    // stall when it does and keeps the orb up if there is one; switching to
    // measuring now would drain the water it is topping off.
    if (_bufferStartLevel != null) return;
    _bufferHideTimer?.cancel();
    if (_bufferVisible) {
      setState(() => _bufferFinishing = false);
      return;
    }
    // A blip of a few hundred ms after a seek should not flash the circle.
    _bufferShowTimer?.cancel();
    _bufferShowTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _wasBuffering) setState(() => _bufferVisible = true);
    });
  }

  void _bufferingEnded() {
    _bufferingSince = null;
    _bufferShowTimer?.cancel();
    // The hand-off's own timer hides the orb.
    if (!_bufferVisible || _bufferStartLevel != null) return;
    // Let the water top off before the circle fades, rather than vanishing
    // half full.
    setState(() => _bufferFinishing = true);
    _bufferHideTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) {
        setState(() {
          _bufferVisible = false;
          _bufferFinishing = false;
        });
      }
    });
  }

  /// Runs every second.
  void _checkHealth() {
    if (!mounted) return;
    if (_phase == _Phase.reconnecting) {
      // Keeps the "retrying in Ns" countdown moving.
      setState(() {});
      return;
    }
    final c = _controller;
    if (_phase != _Phase.playing || c == null) return;
    if (c.value.hasError) return _startReconnect();

    final since = _bufferingSince;
    if (since != null &&
        DateTime.now().difference(since) > _stallTimeout &&
        DateTime.now().difference(_bufferProgressAt) > const Duration(seconds: 15)) {
      _startReconnect();
    }
  }

  // --- reconnecting ------------------------------------------------------------------

  void _startReconnect() {
    if (_phase == _Phase.reconnecting || !mounted) return;
    final c = _controller;
    if (c != null) {
      c.removeListener(_onValue);
      final at = c.value.position;
      if (at > Duration.zero && !c.value.hasError) _lastGoodPosition = at;
      // Paused, not disposed: it keeps the last frame on screen, and a stalled
      // (rather than dead) player must not come back to life and play audio
      // over the new one.
      c.pause().catchError((_) {});
    }
    _saveProgress();
    _resumeAt = _lastGoodPosition;
    _stale?.dispose();
    _stale = c;
    _controller = null;
    _bufferShowTimer?.cancel();
    _bufferHideTimer?.cancel();
    _syncWakelock(false);
    setState(() {
      _phase = _Phase.reconnecting;
      _attempt = 0;
      _bufferVisible = false;
      _bufferFinishing = false;
      _wasBuffering = false;
    });
    _scheduleAttempt(const Duration(milliseconds: 600));
  }

  void _scheduleAttempt([Duration? delay]) {
    final wait = delay ??
        Duration(seconds: _retryDelays[(_attempt - 1).clamp(0, _retryDelays.length - 1)]);
    _retryTimer?.cancel();
    _retryAt = DateTime.now().add(wait);
    _retryTimer = Timer(wait, _attemptReconnect);
    if (mounted) setState(() {});
  }

  void _retryNow() {
    _retryTimer?.cancel();
    _attemptReconnect();
  }

  /// One try at getting playback back. Keeps going for as long as the screen is
  /// open -- a phone that loses Wi-Fi for five minutes should pick up where it
  /// left off when the Wi-Fi returns, not strand the user on an error.
  Future<void> _attemptReconnect() async {
    if (_attemptInFlight || _phase != _Phase.reconnecting || !mounted) return;
    _attemptInFlight = true;
    final gen = _generation;
    setState(() {
      _attempt++;
      _retryAt = null;
    });

    var ok = false;
    try {
      if (_attempt <= 2 && _sources.isNotEmpty) {
        // The same stream first: cheapest, and after a network blip it is
        // usually still valid.
        final c = await _open(_sources[_sourceIndex], _resumeAt);
        if (gen != _generation || !mounted || _phase != _Phase.reconnecting) {
          await c?.dispose();
          return;
        }
        if (c != null) {
          _attach(c, _sourceIndex);
          ok = true;
        }
      } else {
        // Stream URLs carry tokens that expire, and the source itself may have
        // gone, so ask the server afresh and try everything it offers. It has
        // to be a fresh resolve: a plain request can be answered from the
        // server's cache, which hands back the very link that just died.
        final data = await ApiService.getSources(
            widget.animeId, widget.epNum, category, fresh: true);
        if (gen != _generation || !mounted || _phase != _Phase.reconnecting) return;
        if ((data['sources'] as List).isNotEmpty) {
          _applySourceData(data);
          ok = await _openFirstWorking(start: _resumeAt, gen: gen);
        }
      }
    } finally {
      _attemptInFlight = false;
    }
    if (!ok && mounted && gen == _generation && _phase == _Phase.reconnecting) {
      _scheduleAttempt();
    }
  }

  // --- history -----------------------------------------------------------------------

  void _saveProgress() {
    final c = _controller;
    final position = (c != null && c.value.isInitialized && !c.value.hasError)
        ? c.value.position
        : _lastGoodPosition;
    final duration = c?.value.duration ?? _stale?.value.duration ?? Duration.zero;
    // A load that never played is not something the user watched.
    if (position < const Duration(seconds: 3)) return;
    HistoryService.record(
      animeId: widget.animeId,
      episode: widget.epNum,
      title: widget.title,
      cover: widget.cover,
      position: position,
      duration: duration,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveProgress();
      HistoryService.flush();
    }
  }

  // --- screen chrome -----------------------------------------------------------------

  /// Hold the screen awake while video is actually playing.
  ///
  /// Android's display timeout does not know about video playback, so the
  /// screen was switching off mid-episode. Tied to isPlaying rather than to the
  /// screen being open, so pausing and walking away releases it instead of
  /// burning the battery on a static frame.
  void _syncWakelock(bool playing) {
    if (playing == _awake) return;
    _awake = playing;
    // FLAG_KEEP_SCREEN_ON on the activity window (MainActivity.kt). This can
    // fire as the app goes to the background, when there is no window to set it
    // on; Android clears the flag on the way out anyway, so nothing is lost.
    NativeBridge.keepScreenOn(playing);
  }

  /// Reload the current episode on the other audio track.
  void _toggleCategory() {
    _saveProgress();
    _retryTimer?.cancel();
    final old = _controller;
    old?.removeListener(_onValue);
    old?.dispose();
    _stale?.dispose();
    _stale = null;
    setState(() {
      category = category == 'sub' ? 'dub' : 'sub';
      _controller = null;
      _bufferVisible = false;
      _wasBuffering = false;
    });
    _resolve();
  }

  /// Rotate into or out of landscape. Rotating the device by hand does the same
  /// thing on its own -- this is for people who keep rotation locked.
  void _toggleFullscreen(bool currentlyFullscreen) {
    SystemChrome.setPreferredOrientations(
      currentlyFullscreen
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  /// Hide the status and navigation bars in landscape, restore them in portrait.
  void _syncSystemUi(bool fullscreen) {
    if (fullscreen == _immersive) return;
    _immersive = fullscreen;
    SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  // --- remotes and media buttons ---------------------------------------------------------

  /// Tells Android what is playing, for the lock screen and media buttons.
  void _syncSession(VideoPlayerValue v) => NativeBridge.mediaSession(true,
      title: widget.title ?? 'AniVerse',
      subtitle: 'Episode ${widget.epNum}',
      playing: v.isPlaying,
      position: v.position.inMilliseconds,
      duration: v.duration.inMilliseconds);

  void _seekBy(VideoPlayerController c, int seconds) {
    final to = c.value.position + Duration(seconds: seconds);
    c.seekTo(to < Duration.zero ? Duration.zero : (to > c.value.duration ? c.value.duration : to));
  }

  /// A headset, car or remote button (MainActivity's media session).
  void _onMedia(String action, int position) {
    final c = _controller;
    if (!mounted || c == null || !c.value.isInitialized) return;
    switch (action) {
      case 'play':
        c.play();
      case 'pause':
        c.pause();
      case 'forward':
        _seekBy(c, 10);
      case 'rewind':
        _seekBy(c, -10);
      case 'seek':
        c.seekTo(Duration(milliseconds: position));
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      final now = _controller;
      if (mounted && now != null) _syncSession(now.value);
    });
  }

  /// TV remotes and keyboards: Select, Enter or Space plays and pauses, left
  /// and right seek ten seconds, and the media keys work.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || (e is! KeyDownEvent && e is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.gameButtonA || k == LogicalKeyboardKey.mediaPlayPause) {
      c.value.isPlaying ? c.pause() : c.play();
    } else if (k == LogicalKeyboardKey.mediaPlay) {
      c.play();
    } else if (k == LogicalKeyboardKey.mediaPause) {
      c.pause();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(c, -10);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(c, 10);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    if (NativeBridge.onMedia == _onMedia) NativeBridge.onMedia = null;
    NativeBridge.mediaSession(false);
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    HistoryService.flush();
    _watchdog?.cancel();
    _historyTimer?.cancel();
    _retryTimer?.cancel();
    _bufferShowTimer?.cancel();
    _bufferHideTimer?.cancel();
    _openTicker?.cancel();
    _openProgress.dispose();
    _speed.dispose();
    _controller?.removeListener(_onValue);
    _controller?.dispose();
    _stale?.dispose();
    // Never leave the wakelock held after the player is gone.
    if (_awake) NativeBridge.keepScreenOn(false);
    // Leave the device as the rest of the app expects to find it.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // --- build -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Landscape is fullscreen: no chrome, video filling the screen.
    final fullscreen =
        MediaQuery.of(context).orientation == Orientation.landscape;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncSystemUi(fullscreen));

    final controller = _controller;
    final Widget body;

    switch (_phase) {
      case _Phase.resolving:
        body = _stage(
          fullscreen,
          (_) => AniVerseLoader(
            size: 72,
            label: _refreshing
                ? 'GETTING A FRESH LINK'
                : _secondLook
                    ? 'STILL LOOKING'
                    : 'FINDING SOURCES',
          ),
        );
      case _Phase.opening:
        body = _stage(fullscreen, (size) => _loadingOrb('LOADING VIDEO', size));
      case _Phase.reconnecting:
        body = _stage(fullscreen, _reconnectOverlay, behind: _stale);
      case _Phase.failed:
        body = _failure();
      case _Phase.playing:
        body = controller == null
            ? _stage(fullscreen, (_) => const SizedBox())
            : _player(controller, fullscreen);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      // SafeArea would letterbox the video behind the notch in landscape, so it
      // only applies while the system bars are actually showing.
      body: fullscreen ? Center(child: body) : SafeArea(child: Center(child: body)),
    );
  }

  Widget _player(VideoPlayerController controller, bool fullscreen) {
    // Only the picture is scaled to fit. The controls and the buffering circle
    // are laid out at screen size: inside the FittedBox they were laid out at
    // the video's pixel size (1920x1080) and then shrunk with it, which made
    // them tiny in landscape.
    final Widget video = fullscreen
        ? FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          )
        : VideoPlayer(controller);

    final player = Stack(
      fit: StackFit.expand,
      children: [
        Focus(autofocus: true, onKeyEvent: _onKey, child: Center(child: video)),
        AniVersePlayerControls(
          controller: controller,
          title: widget.title == null
              ? 'Episode ${widget.epNum}'
              : '${widget.title} · EP ${widget.epNum}',
          intro: _intro,
          outro: _outro,
          category: category,
          onToggleCategory: _toggleCategory,
          isFullscreen: fullscreen,
          onToggleFullscreen: () => _toggleFullscreen(fullscreen),
          hideTransport: _bufferVisible,
        ),
        // Above the controls so it is never hidden with them, but it lets
        // touches through: the back button and seek bar keep working while the
        // video buffers.
        IgnorePointer(
          child: LayoutBuilder(
            // Sized to the player, so it fits the short portrait player
            // without covering the title and seek bar.
            builder: (_, box) => AnimatedSwitcher(
              // Keeps the outgoing circle (already topped off to 100%) on
              // screen while it fades, instead of it vanishing at once.
              duration: const Duration(milliseconds: 250),
              child: _bufferVisible
                  ? Center(
                      key: const ValueKey('buffer'),
                      child: _bufferOverlay(controller, _orbSize(box)),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );

    final ratio = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;

    // In landscape the video takes the whole screen; in portrait it keeps its
    // aspect ratio so the episode list is not pushed off-screen.
    return fullscreen
        ? SizedBox.expand(child: player)
        : AspectRatio(aspectRatio: ratio, child: player);
  }

  Widget _bufferOverlay(VideoPlayerController controller, double size) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, v, __) => ValueListenableBuilder<double?>(
        valueListenable: _speed.mbps,
        builder: (_, mbps, __) => BufferOverlay(
          // Not v.isPlaying: ExoPlayer reports "not playing" for the whole of a
          // stall, so that would always read LOADING.
          label: _bufferLabel,
          progress: _bufferFinishing ? 1.0 : _bufferFill(v),
          initialLevel: _bufferStartLevel,
          mbps: mbps,
          size: size,
        ),
      ),
    );
  }

  /// The orb for a stream being opened, filling from [_openProgress]. [measured]
  /// false means there is nothing real to show yet (waiting on the server or a
  /// retry timer), and the water idles rather than pretending.
  Widget _loadingOrb(String label, double size,
      {String? detail, VoidCallback? onRetry, bool measured = true}) {
    return ValueListenableBuilder<double>(
      valueListenable: _openProgress,
      builder: (_, progress, __) => ValueListenableBuilder<double?>(
        valueListenable: _speed.mbps,
        builder: (_, mbps, __) => BufferOverlay(
          label: label,
          progress: measured ? progress : null,
          mbps: mbps,
          size: size,
          detail: detail,
          onRetry: onRetry,
        ),
      ),
    );
  }

  Widget _reconnectOverlay(double size) {
    final retryAt = _retryAt;
    final String detail;
    if (retryAt != null) {
      final secs = retryAt.difference(DateTime.now()).inMilliseconds / 1000;
      detail = 'Connection lost · retrying in ${secs.ceil().clamp(1, 99)}s';
    } else {
      detail = _attempt <= 2 ? 'Reconnecting to the stream…' : 'Looking for the stream again…';
    }
    return _loadingOrb(
      'RECONNECTING',
      size,
      measured: _openingStream,
      detail: '$detail\nYou\'ll continue from ${_fmt(_resumeAt)}',
      onRetry: retryAt != null ? _retryNow : null,
    );
  }

  /// A video-shaped stage for the non-playing states, with its own back button
  /// since the player controls are not there to provide one.
  /// One size for every orb, so the loading stage and the player draw it the
  /// same and nothing jumps when one hands over to the other. Sized to the
  /// video area, so it fits the short portrait player without covering the
  /// title and seek bar.
  static double _orbSize(BoxConstraints box) =>
      (box.maxHeight * 0.36).clamp(72.0, 136.0).toDouble();

  Widget _stage(bool fullscreen, Widget Function(double orbSize) child,
      {VideoPlayerController? behind}) {
    final frame = LayoutBuilder(builder: (_, box) => Stack(
      fit: StackFit.expand,
      children: [
        if (behind != null && behind.value.isInitialized)
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: behind.value.size.width,
              height: behind.value.size.height,
              child: VideoPlayer(behind),
            ),
          ),
        if (behind != null) const ColoredBox(color: Color(0x99000000)),
        Center(child: child(_orbSize(box))),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    ));
    return fullscreen
        ? SizedBox.expand(child: frame)
        : AspectRatio(aspectRatio: 16 / 9, child: frame);
  }

  Widget _failure() {
    final other = category == 'sub' ? 'DUB' : 'SUB';
    // Offering a dub the server already said does not exist just leads to a
    // second failure.
    final offerSwitch = category == 'dub' || _hasDub != false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(height: 12),
          const Icon(Icons.wifi_tethering_error_rounded,
              color: AniVerseTheme.textDim, size: 44),
          const SizedBox(height: 14),
          const Text("Couldn't play this episode",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            _failReason ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AniVerseTheme.textDim, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _resolve,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
            style: FilledButton.styleFrom(backgroundColor: AniVerseTheme.red),
          ),
          if (offerSwitch) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _toggleCategory,
              child: Text('Switch to $other', style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ],
      ),
    );
  }
}
