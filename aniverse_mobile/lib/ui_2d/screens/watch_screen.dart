import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../../services/download_service.dart';
import '../../services/history_service.dart';
import '../../services/native_bridge.dart';
import '../../services/net_speed.dart';
import '../../services/party_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../theme_2d.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/buffer_overlay.dart';
import '../widgets/pixel_extras.dart';
import '../widgets/player_controls.dart';

class WatchScreen extends StatefulWidget {
  final String animeId;
  final int epNum;

  /// Shown in watch history. Optional so any caller can open an episode, but
  /// without them the history row has no title or poster until the next watch.
  final String? title;
  final String? cover;

  /// The audio to start on: sub or dub.
  final String category;

  /// Join this watch party as the episode opens.
  final String? partyCode;

  const WatchScreen({
    super.key,
    required this.animeId,
    required this.epNum,
    this.title,
    this.cover,
    this.category = 'sub',
    this.partyCode,
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

  // Subtitles.
  /// The viewer's pick from the CC button; null until they make one, which
  /// means on for SUB and off for DUB (a dub's tracks mostly repeat its audio).
  bool? _captionsChoice;

  /// Whether the source playing now has its subtitle file loaded.
  bool _hasCaptions = false;

  /// Whether the HUD's bottom bar is showing, so the text can sit above it.
  bool _hudVisible = true;

  /// Parsed subtitle files by URL, so a reconnect does not fetch them again.
  final Map<String, ClosedCaptionFile> _captionFiles = {};

  bool get _captionsOn => _captionsChoice ?? category == 'sub';

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

  // --- 1.9 ---------------------------------------------------------------------------

  /// Episodes out, from the anime's details: what "next episode" may open.
  int _aired = 0;
  bool _prefetched = false;
  bool _startedOnce = false;
  bool _pipSupported = false;

  /// Chromecast: whether this device can cast, and the TV it is casting to.
  bool _castAvailable = false;
  String? _castTo;
  bool _pipWasReady = false;

  /// Playing a downloaded copy rather than a stream.
  bool _offline = false;

  /// HLS variants per master playlist URL: (height, bandwidth, url), lowest first.
  final Map<String, List<(int, int, String)>> _variants = {};

  /// The playlist actually opened for the source playing: a variant or the master.
  String? _playingUrl;

  /// The subtitle track in use.
  String? _trackUrl;

  PartyConnection? _party;
  DateTime _remoteUntil = DateTime.fromMillisecondsSinceEpoch(0);
  (PartyState, double, DateTime)? _pendingParty;

  // The end card: next episode with a countdown.
  bool _upNext = false;
  int _upNextLeft = 0;
  Timer? _upNextTimer;

  VideoPlayerOptions get _options => VideoPlayerOptions(allowBackgroundPlayback: AppSettings.bgAudio);

  @override
  void initState() {
    super.initState();
    category = widget.category;
    ApiService.getAnimeDetails(widget.animeId).then((a) {
      if (a != null && mounted) setState(() => _aired = airedEpisodes(a));
    });
    NativeBridge.pipSupported().then((v) {
      if (mounted) setState(() => _pipSupported = v);
    });
    NativeBridge.inPip.addListener(_onPip);
    NativeBridge.onMedia = _onMedia;
    NativeBridge.castAvailable().then((v) {
      if (mounted) setState(() => _castAvailable = v);
    });
    NativeBridge.castDevice.addListener(_onCast);
    NativeBridge.onCastEnded = _onCastEnded;
    final code = widget.partyCode;
    if (code != null && PartyConnection.validCode(code)) _joinParty(code.toUpperCase());
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

    // A saved copy plays without the server, and without spending data.
    final copy = DownloadService.find(widget.animeId, widget.epNum, category: category);
    if (copy != null && copy.done) {
      final path = await DownloadService.mediaPath(copy);
      final subs = await DownloadService.subtitlePath(copy);
      if (gen != _generation || !mounted) return;
      _offline = true;
      _sources = [
        {
          'url': Uri.file(path).toString(),
          'serverName': 'Downloaded',
          'isM3U8': path.endsWith('.m3u8'),
          'intro': copy.intro,
          'outro': copy.outro,
          'subtitles': [if (subs != null) {'url': Uri.file(subs).toString(), 'label': 'Saved', 'default': true}],
        },
      ];
      final p = HistoryService.progressFor(widget.animeId, widget.epNum);
      final from = (p != null && p.positionMs > 10000 && !p.finished) ? p.position : Duration.zero;
      setState(() => _phase = _Phase.opening);
      if (await _openFirstWorking(start: from, gen: gen)) {
        if (mounted) pixelToast(context, 'Playing the downloaded copy.');
        return;
      }
      if (gen != _generation || !mounted) return;
      _offline = false; // the saved copy would not open: try streaming instead
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
      // No subbed copy anywhere, but the server found a dub: play that rather
      // than an error screen with a button for it, and say why.
      if (category == 'sub' && _hasDub == true && data['offline'] != true) {
        setState(() {
          category = 'dub';
          _captionsChoice = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No subbed version was found, so this is the English dub.'),
          duration: Duration(seconds: 5),
        ));
        return _resolve();
      }
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
    // Intro/outro are taken per source when one is attached (_loadSkipTimes):
    // each provider's markers fit only its own cut of the episode.
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
    Sfx.play('error');
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
    final String opened;
    final VideoPlayerController c;
    if (url.startsWith('file://')) {
      opened = url;
      c = VideoPlayerController.file(File(Uri.parse(url).toFilePath()), videoPlayerOptions: _options);
    } else {
      opened = isHls ? await _qualityUrl(url) : url;
      c = VideoPlayerController.networkUrl(
        Uri.parse(opened),
        formatHint: isHls ? VideoFormat.hls : null,
        videoPlayerOptions: _options,
      );
    }

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
      _playingUrl = opened;
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
    // Opening is not something to tell the party about.
    _remoteUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    c.play();
    c.setPlaybackSpeed(AppSettings.speed).catchError((_) {});
    if (!_startedOnce) {
      _startedOnce = true;
      Sfx.play('start');
    }
    setState(() {
      _phase = _Phase.playing;
      _attempt = 0;
      _retryAt = null;
      _hasCaptions = false;
    });
    final pending = _pendingParty;
    if (pending != null) {
      _pendingParty = null;
      final (s, t, at) = pending;
      _applyParty(s, t + (s.playing ? DateTime.now().difference(at).inMilliseconds / 1000 : 0));
    }
    if (index < _sources.length) {
      _loadCaptions(c, _sources[index]);
      _loadSkipTimes(c, _sources[index]);
    }
    if (from == _Phase.opening || from == _Phase.reconnecting) _handOffOrb();
    // The frozen frame has done its job once the new player is up.
    final stale = _stale;
    _stale = null;
    if (old != null && old != stale) old.dispose();
    stale?.dispose();
  }

  /// Loads the source's own subtitle file into [c]. Done once the video is
  /// already playing, not before: a slow or broken subtitle file must never be
  /// what stops an episode from starting. Most "sub" streams are the raw
  /// episode with the text in a separate file, so this is what puts the
  /// subtitles on screen at all.
  Timer? _skipTimer;

  /// Intro/outro for the source now playing: its own markers when its provider
  /// has them, otherwise the server's -- from AniSkip, or found by matching
  /// this episode's audio with its neighbour's. That can take a couple of
  /// minutes the first time, so a "pending" answer is asked again, and better
  /// times replace earlier ones.
  void _loadSkipTimes(VideoPlayerController c, Map<String, dynamic> source, [int attempt = 0]) {
    _skipTimer?.cancel();
    Map<String, dynamic>? own(String k) =>
        source[k] is Map ? Map<String, dynamic>.from(source[k] as Map) : null;
    if (attempt == 0) {
      setState(() {
        _intro = own('intro');
        _outro = own('outro');
      });
    }
    if (_intro != null && _outro != null) return;
    final gen = _generation;
    Future<void> ask() async {
      final d = c.value.duration;
      if (d <= Duration.zero) return;
      final r = await ApiService.skipTimes(widget.animeId, widget.epNum, d.inMilliseconds / 1000,
          (source['serverName'] ?? '').toString(), category);
      if (!mounted || gen != _generation || _controller != c || r == null) return;
      Map<String, dynamic>? got(String k) => r[k] is Map ? Map<String, dynamic>.from(r[k] as Map) : null;
      setState(() {
        _intro = own('intro') ?? got('intro') ?? _intro;
        _outro = own('outro') ?? got('outro') ?? _outro;
      });
      if (r['pending'] == true && attempt < 4) {
        const waits = [60, 90, 150, 300];
        _skipTimer = Timer(Duration(seconds: waits[attempt]), () {
          if (mounted && gen == _generation && _controller == c) _loadSkipTimes(c, source, attempt + 1);
        });
      }
    }

    ask();
  }

  List<Map> _tracksOf(Map<String, dynamic>? source) =>
      ((source?['subtitles'] ?? []) as List).whereType<Map>().where((t) => (t['url'] ?? '').toString().isNotEmpty).toList();

  /// The language picked in Settings when the stream has it, else the one the
  /// source flags as default, else English, else the first.
  Map _pickTrack(List<Map> tracks) {
    bool named(Map t, String p) => (t['label'] ?? '').toString().toLowerCase().startsWith(p);
    final lang = AppSettings.subLang.toLowerCase();
    return (lang.isNotEmpty ? tracks.where((t) => named(t, lang)).firstOrNull : null) ??
        tracks.where((t) => t['default'] == true).firstOrNull ??
        tracks.where((t) => named(t, 'english')).firstOrNull ??
        tracks.first;
  }

  Future<void> _loadCaptions(VideoPlayerController c, Map<String, dynamic> source, {Map? track}) async {
    final tracks = _tracksOf(source);
    if (tracks.isEmpty) return;
    final url = ((track ?? _pickTrack(tracks))['url'] ?? '').toString();
    if (url.isEmpty) return;

    var file = _captionFiles[url];
    if (file == null) {
      final text = url.startsWith('file://')
          ? await File(Uri.parse(url).toFilePath()).readAsString().catchError((_) => '')
          : await ApiService.getSubtitleFile(url);
      if (text == null) return;
      final parsed = WebVTTCaptionFile(text);
      if (parsed.captions.isEmpty) return;
      file = _captionFiles[url] = parsed;
    }
    if (!mounted || _controller != c) return;
    await c.setClosedCaptionFile(Future.value(file));
    _trackUrl = url;
    if (mounted && _controller == c) setState(() => _hasCaptions = true);
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
    if (_wasPlaying != v.isPlaying) {
      _syncPip(v);
      _syncSession(v);
    }
    _wasPlaying = v.isPlaying;

    // The next episode's streams are looked up near the end of this one, so
    // the server has them ready when "up next" fires.
    final d = v.duration.inMilliseconds;
    if (!_prefetched && !_offline && d > 60000 && _aired > widget.epNum && v.position.inMilliseconds > d * 0.85) {
      _prefetched = true;
      ApiService.getSources(widget.animeId, widget.epNum + 1, category);
    }
    if (v.isCompleted && !_upNext && _aired > widget.epNum && d > 0) _startUpNext();
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

  // --- quality ----------------------------------------------------------------------

  /// The variants a master playlist offers, fetched once per source.
  Future<List<(int, int, String)>> _variantsOf(String master) async {
    final known = _variants[master];
    if (known != null) return known;
    final out = <(int, int, String)>[];
    try {
      final r = await http.get(Uri.parse(master)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final lines = r.body.split('\n').map((l) => l.trim()).toList();
        final base = Uri.parse(master);
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
          var j = i + 1;
          while (j < lines.length && (lines[j].isEmpty || lines[j].startsWith('#'))) {
            j++;
          }
          if (j >= lines.length) continue;
          final h = int.tryParse(RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[i])?.group(1) ?? '') ?? 0;
          final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ?? '') ?? 0;
          out.add((h, bw, base.resolve(lines[j]).toString()));
        }
        out.sort((a, b) => a.$2.compareTo(b.$2));
      }
    } catch (_) {
      // No list of qualities: the master plays on automatic.
    }
    return _variants[master] = out;
  }

  /// What to open for [master]: the lowest variant with data saver on, the
  /// height picked last time if this stream has it, else the master (automatic).
  Future<String> _qualityUrl(String master) async {
    final pick = AppSettings.quality;
    if (!AppSettings.dataSaver && pick == 'auto') {
      // Still learn the list, for the menu, without holding the open up.
      unawaited(_variantsOf(master));
      return master;
    }
    final vs = await _variantsOf(master);
    if (vs.isEmpty) return master;
    if (AppSettings.dataSaver) return vs.first.$3;
    final want = int.tryParse(pick);
    return vs.where((v) => v.$1 == want).firstOrNull?.$3 ?? master;
  }

  String get _qualityLabel {
    final src = _sources.isEmpty ? null : _sources[_sourceIndex]['url']?.toString();
    final vs = src == null ? null : _variants[src];
    final now = vs?.where((v) => v.$3 == _playingUrl).firstOrNull;
    if (now == null) return 'Auto';
    return now.$1 > 0 ? '${now.$1}p' : '${now.$2 ~/ 1000} kbps';
  }

  /// Opens the current source again at the same spot: after a quality change,
  /// or with a reported source taken out.
  Future<void> _reopen({int? first}) async {
    final c = _controller;
    final at = c?.value.position ?? _lastGoodPosition;
    final gen = ++_generation;
    _saveProgress();
    c?.removeListener(_onValue);
    await c?.pause().catchError((_) {});
    _stale?.dispose();
    _stale = c;
    _controller = null;
    setState(() => _phase = _Phase.opening);
    final ok = _sources.isNotEmpty && await _openFirstWorking(start: at, gen: gen, first: first ?? _sourceIndex);
    if (gen != _generation || !mounted) return;
    if (!ok) {
      _resumeAt = at;
      final data = await ApiService.getSources(widget.animeId, widget.epNum, category);
      if (gen != _generation || !mounted) return;
      _applySourceData(data);
      if (_sources.isNotEmpty && await _openFirstWorking(start: at, gen: gen)) return;
      if (gen == _generation && mounted) _fail('No other stream would play this episode. Try again in a moment, or switch between SUB and DUB.');
    }
  }

  // --- the menu --------------------------------------------------------------------------

  static const _reasons = [
    "Video won't play", 'Wrong episode', 'Audio and video out of sync',
    'Subtitles missing or wrong', 'Keeps buffering', 'Very bad quality',
  ];

  Future<void> _openMenu() async {
    final src = _sources.isEmpty ? null : _sources[_sourceIndex];
    final master = src?['url']?.toString() ?? '';
    final vs = _offline || master.isEmpty ? const <(int, int, String)>[] : await _variantsOf(master);
    final tracks = _tracksOf(src);
    final speed = _controller?.value.playbackSpeed ?? 1.0;
    if (!mounted) return;
    final saved = DownloadService.find(widget.animeId, widget.epNum, category: category);
    final choice = await pickOption<String>(context, 'Player', [
      if (vs.length > 1) ('quality', 'Quality · $_qualityLabel${AppSettings.dataSaver ? ' (data saver)' : ''}'),
      ('speed', 'Speed · ${speed == 1 ? 'normal' : '${speed}x'}'),
      if (tracks.isNotEmpty) ('subs', 'Subtitles · ${_captionsOn ? (tracks.where((t) => t['url'] == _trackUrl).firstOrNull?['label'] ?? 'on') : 'off'}'),
      ('size', 'Subtitle size · ${AppSettings.subSize.toUpperCase()}'),
      if (!_offline && (saved == null || saved.status == 'failed')) ('download', 'Download this episode'),
      if (_party == null) ('party', 'Start a watch party') else ('invite', 'Party ${_party!.code} · copy invite'),
      if (_party == null) ('join', 'Join a party by code'),
      if (_pipSupported) ('pip', 'Picture in picture'),
      if (_castAvailable && !_offline && src != null)
        _castTo == null ? ('cast', 'Cast to TV') : ('cast', 'Casting to $_castTo · stop'),
      if (!_offline && src != null) ('report', 'Report a problem'),
    ], null);
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'quality':
        final pick = await pickOption<String>(context, 'Quality', [
          ('auto', 'Auto'),
          for (final v in vs.reversed) ('${v.$1}', v.$1 > 0 ? '${v.$1}p' : '${v.$2 ~/ 1000} kbps'),
        ], AppSettings.quality);
        if (pick == null) return;
        await AppSettings.set('quality', pick);
        // A quality picked by hand beats data saver for now.
        if (AppSettings.dataSaver && pick != 'auto') await AppSettings.set('dataSaver', false);
        _reopen();
      case 'speed':
        final pick = await pickOption<double>(context, 'Speed', [
          for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) (r, r == 1 ? 'Normal' : '${r}x'),
        ], speed);
        if (pick == null) return;
        await AppSettings.set('speed', pick);
        await _controller?.setPlaybackSpeed(pick);
      case 'subs':
        final pick = await pickOption<String>(context, 'Subtitles', [
          ('', 'Off'),
          for (final t in tracks) (t['url'].toString(), (t['label'] ?? 'Subtitles').toString()),
        ], _captionsOn ? _trackUrl : '');
        if (pick == null) return;
        if (pick.isEmpty) {
          setState(() => _captionsChoice = false);
        } else {
          setState(() => _captionsChoice = true);
          final c = _controller;
          if (c != null && pick != _trackUrl && src != null) {
            _loadCaptions(c, src, track: tracks.firstWhere((t) => t['url'] == pick));
          }
        }
      case 'size':
        final pick = await pickOption<String>(context, 'Subtitle size',
            const [('s', 'Small'), ('m', 'Medium'), ('l', 'Large'), ('xl', 'Extra large')], AppSettings.subSize);
        if (pick != null) await AppSettings.set('subSize', pick);
        if (mounted) setState(() {});
      case 'download':
        DownloadService.enqueue(
            animeId: widget.animeId, episode: widget.epNum, category: category,
            title: widget.title ?? '', cover: widget.cover ?? '');
        pixelToast(context, 'Downloading. It will be under Saved, ready to play offline.');
      case 'party':
        _joinParty(PartyConnection.newCode());
        Sfx.play('select');
      case 'invite':
        await Clipboard.setData(ClipboardData(text: _party!.inviteLink));
        if (mounted) pixelToast(context, 'Invite link copied. Anyone with it joins, in the app (code ${_party!.code}) or the website.');
      case 'join':
        final ctl = TextEditingController();
        final code = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('JOIN A PARTY'),
            content: TextField(
              controller: ctl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Party code, like K7QX2M'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
              TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim().toUpperCase()), child: const Text('JOIN')),
            ],
          ),
        );
        if (code != null && PartyConnection.validCode(code)) _joinParty(code);
      case 'pip':
        NativeBridge.enterPip();
      case 'cast':
        if (_castTo != null) {
          NativeBridge.castStop();
        } else if (!await NativeBridge.castPick() && mounted) {
          pixelToast(context, "Casting needs Google Play services, and this device doesn't have it.");
        }
      case 'report':
        final reason = await pickOption<String>(context, "What's wrong?", [for (final r in _reasons) (r, r)], null);
        if (reason == null || src == null) return;
        ApiService.report(widget.animeId, widget.epNum, category, master, reason);
        Sfx.play('slash');
        if (mounted) pixelToast(context, 'Thanks for reporting. That stream is set aside for everyone; trying another.');
        _sources.removeAt(_sourceIndex);
        _reopen(first: _sources.isEmpty ? 0 : _sourceIndex % _sources.length);
    }
  }

  // --- picture in picture -----------------------------------------------------------------

  void _onPip() {
    if (mounted) setState(() {});
  }

  /// Leaving the app while a video plays shrinks it into a window.
  void _syncPip(VideoPlayerValue v) {
    final ready = AppSettings.pipAuto && _pipSupported && v.isPlaying;
    if (ready == _pipWasReady) return;
    _pipWasReady = ready;
    final size = v.size;
    NativeBridge.setPipReady(ready,
        w: size.width > 0 ? size.width.round() : 16, h: size.height > 0 ? size.height.round() : 9);
  }

  // --- Chromecast -------------------------------------------------------------------------

  /// A cast started (or ended): the episode goes over to the TV from where it
  /// is, and the phone becomes the remote.
  void _onCast() {
    final device = NativeBridge.castDevice.value;
    if (!mounted || device == _castTo) return;
    setState(() => _castTo = device);
    if (device == null) return;
    final c = _controller;
    final src = _sources.isEmpty ? null : _sources[_sourceIndex];
    final url = src?['url']?.toString() ?? '';
    if (url.isEmpty || url.startsWith('file://')) {
      pixelToast(context, 'Saved episodes play on this phone only. Pick one to stream to cast it.');
      return;
    }
    c?.pause();
    NativeBridge.castLoad(url,
        title: widget.title ?? 'AniVerse',
        subtitle: 'Episode ${widget.epNum}${category == 'dub' ? ' (dub)' : ''}',
        position: (c?.value.position ?? _lastGoodPosition).inMilliseconds,
        subtitles: _captionsOn ? _trackUrl : null,
        hls: src?['isM3U8'] == true || url.contains('m3u8'));
    Sfx.play('select');
  }

  /// Back on the phone: carry on from where the TV got to.
  void _onCastEnded(int positionMs) {
    final c = _controller;
    if (!mounted || c == null || !c.value.isInitialized) return;
    if (positionMs > 0) c.seekTo(Duration(milliseconds: positionMs));
    c.play();
  }

  // --- media buttons --------------------------------------------------------------------

  /// Tells Android what is playing, for the lock screen and media buttons.
  void _syncSession(VideoPlayerValue v) {
    NativeBridge.mediaSession(true,
        title: widget.title ?? 'AniVerse',
        subtitle: 'Episode ${widget.epNum}',
        playing: v.isPlaying,
        position: v.position.inMilliseconds,
        duration: v.duration.inMilliseconds,
        hasNext: _aired > widget.epNum);
  }

  /// A headset, car or remote button.
  void _onMedia(String action, int position) {
    final c = _controller;
    if (!mounted || c == null || !c.value.isInitialized) return;
    final at = c.value.position;
    switch (action) {
      case 'play':
        c.play();
      case 'pause':
        c.pause();
      case 'next':
        if (_aired > widget.epNum) return _goEpisode(widget.epNum + 1);
      case 'forward':
        c.seekTo(at + const Duration(seconds: 10));
      case 'rewind':
        c.seekTo(at - const Duration(seconds: 10) < Duration.zero ? Duration.zero : at - const Duration(seconds: 10));
      case 'seek':
        c.seekTo(Duration(milliseconds: position));
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _userAction();
      final now = _controller;
      if (now != null) _syncSession(now.value);
    });
  }

  // --- next episode -------------------------------------------------------------------------

  /// Another episode: in a party the room is told first so everyone comes along.
  void _goEpisode(int ep, {String? anime}) {
    final code = _party?.code;
    if (anime == null && _party != null) _party!.sendEpisode(ep);
    _party?.close();
    final same = anime == null || anime == widget.animeId;
    Navigator.of(context).pushReplacement(FadeScaleRoute(
      backdrop: false,
      page: WatchScreen(
        animeId: anime ?? widget.animeId,
        epNum: ep,
        title: same ? widget.title : null,
        cover: same ? widget.cover : null,
        category: category,
        partyCode: code,
      ),
    ));
  }

  void _startUpNext() {
    setState(() {
      _upNext = true;
      _upNextLeft = 8;
    });
    _upNextTimer?.cancel();
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _upNextLeft--);
      if (_upNextLeft <= 0) {
        t.cancel();
        _goEpisode(widget.epNum + 1);
      }
    });
  }

  void _cancelUpNext() {
    _upNextTimer?.cancel();
    setState(() => _upNext = false);
  }

  // --- watch party ----------------------------------------------------------------------------

  void _joinParty(String code) {
    _party?.close();
    final p = PartyConnection(code: code, getState: _partyState, onState: _applyParty);
    _party = p;
    p.connect();
    if (mounted) setState(() {});
  }

  void _leaveParty() {
    _party?.close();
    setState(() => _party = null);
  }

  PartyState _partyState() {
    final c = _controller;
    final playing = _phase == _Phase.playing && c != null && c.value.isPlaying;
    final t = c != null && _phase == _Phase.playing ? c.value.position : _lastGoodPosition;
    return PartyState(anime: widget.animeId, ep: widget.epNum, category: category, playing: playing, t: t.inMilliseconds / 1000);
  }

  /// Someone in the party played, paused, seeked or changed episode: follow.
  void _applyParty(PartyState s, double t) {
    if (!mounted) return;
    if (s.anime != widget.animeId || s.ep != widget.epNum) {
      pixelToast(context, '${s.by.isEmpty ? 'The party' : s.by} moved to episode ${s.ep}');
      _goEpisode(s.ep, anime: s.anime);
      return;
    }
    if (s.category != category && (s.category == 'sub' || _hasDub != false)) {
      _pendingParty = (s, t, DateTime.now());
      _toggleCategory(fromParty: true);
      return;
    }
    final c = _controller;
    if (_phase != _Phase.playing || c == null) {
      _pendingParty = (s, t, DateTime.now());
      return;
    }
    _remoteUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    if ((c.value.position.inMilliseconds / 1000 - t).abs() > 1.5) c.seekTo(Duration(milliseconds: (t * 1000).round()));
    if (s.playing && !c.value.isPlaying) c.play();
    if (!s.playing && c.value.isPlaying) c.pause();
  }

  /// The viewer played, paused or seeked: tell the party.
  void _userAction() {
    if (_party != null && _phase == _Phase.playing && DateTime.now().isAfter(_remoteUntil)) _party!.send();
    final c = _controller;
    if (c != null && c.value.isInitialized) _syncSession(c.value);
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
  void _toggleCategory({bool fromParty = false}) {
    final at = _controller?.value.position ?? _lastGoodPosition;
    if (!fromParty && _party != null) {
      _party!.send(PartyState(
          anime: widget.animeId, ep: widget.epNum, category: category == 'sub' ? 'dub' : 'sub',
          playing: true, t: at.inMilliseconds / 1000));
    }
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
      _hasCaptions = false;
      _captionsChoice = null;
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

  @override
  void dispose() {
    _upNextTimer?.cancel();
    _party?.close();
    NativeBridge.inPip.removeListener(_onPip);
    NativeBridge.setPipReady(false);
    if (NativeBridge.onMedia == _onMedia) NativeBridge.onMedia = null;
    NativeBridge.mediaSession(false);
    NativeBridge.castDevice.removeListener(_onCast);
    if (NativeBridge.onCastEnded == _onCastEnded) NativeBridge.onCastEnded = null;
    _skipTimer?.cancel();
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

    final party = _party;
    return Scaffold(
      backgroundColor: Colors.black,
      // SafeArea would letterbox the video behind the notch in landscape, so it
      // only applies while the system bars are actually showing.
      body: fullscreen || NativeBridge.inPip.value
          ? Center(child: body)
          : SafeArea(
              child: party == null
                  ? Center(child: body)
                  : Column(children: [body, Expanded(child: _PartyPanel(party: party, onLeave: _leaveParty))]),
            ),
    );
  }

  Widget _player(VideoPlayerController controller, bool fullscreen) {
    // In a picture-in-picture window: the picture and nothing else.
    if (NativeBridge.inPip.value) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(width: controller.value.size.width, height: controller.value.size.height, child: VideoPlayer(controller)),
        ),
      );
    }
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
        Center(child: video),
        // Not while the buffering orb is up: the picture is frozen, so the line
        // is stale, and in the portrait player it lands on the orb's label.
        if (_hasCaptions && _captionsOn && !_bufferVisible)
          IgnorePointer(
            child: _Captions(controller: controller, fullscreen: fullscreen, lifted: _hudVisible),
          ),
        AniVersePlayerControls(
          controller: controller,
          title: widget.title == null
              ? 'Episode ${widget.epNum}'
              : '${widget.title} · EP ${widget.epNum}',
          intro: _intro,
          outro: _outro,
          category: category,
          onToggleCategory: _toggleCategory,
          captionsOn: _hasCaptions ? _captionsOn : null,
          onToggleCaptions: () => setState(() => _captionsChoice = !_captionsOn),
          onHudVisibleChanged: (v) {
            if (mounted && v != _hudVisible) setState(() => _hudVisible = v);
          },
          onOpenMenu: _openMenu,
          onPip: _pipSupported ? () => NativeBridge.enterPip() : null,
          onUserAction: _userAction,
          onNextEpisode: _aired > widget.epNum ? () => _goEpisode(widget.epNum + 1) : null,
          isFullscreen: fullscreen,
          onToggleFullscreen: () => _toggleFullscreen(fullscreen),
          hideTransport: _bufferVisible,
        ),
        if (_castTo != null)
          Positioned.fill(
            child: ColoredBox(
              color: Px.black,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('CASTING TO ${_castTo!.toUpperCase()}',
                      textAlign: TextAlign.center,
                      style: PxFont.label(fullscreen ? 11 : 9, color: Px.gold).copyWith(shadows: PxFont.outline(1.2))),
                  const SizedBox(height: 14),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    PixelButton(label: 'Controls', fontSize: 8, onPressed: NativeBridge.castPick),
                    const SizedBox(width: 12),
                    PixelButton(
                        label: 'Stop casting', kind: PixelButtonKind.dark, fontSize: 8, onPressed: NativeBridge.castStop),
                  ]),
                ]),
              ),
            ),
          ),
        if (_upNext)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xCC050305),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('UP NEXT: EP ${widget.epNum + 1} IN $_upNextLeft', style: PxFont.label(fullscreen ? 11 : 9).copyWith(shadows: PxFont.outline(1.2))),
                  const SizedBox(height: 14),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    PixelButton(label: 'Play now', icon: Sprites.play, fontSize: 8, onPressed: () {
                      _upNextTimer?.cancel();
                      _goEpisode(widget.epNum + 1);
                    }),
                    const SizedBox(width: 12),
                    PixelButton(label: 'Cancel', kind: PixelButtonKind.dark, fontSize: 8, onPressed: _cancelUpNext),
                  ]),
                ]),
              ),
            ),
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
  // Smaller share than the classic orb: the pixel orb is taller (its falling
  // drops hang below it), and at 36% its label ran into the seek bar.
  static double _orbSize(BoxConstraints box) =>
      (box.maxHeight * 0.30).clamp(64.0, 130.0).toDouble();

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
        if (behind != null) const ColoredBox(color: Color(0x99050305)),
        Center(child: child(_orbSize(box))),
        Positioned(
          top: 4,
          left: 4,
          child: PixelIconButton(
            sprite: Sprites.back,
            tooltip: 'Back',
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
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PixelIconButton(
              sprite: Sprites.back,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(height: 8),
          BossFight(onDefeat: _resolve, size: 110),
          const SizedBox(height: 14),
          Text("COULDN'T PLAY THIS EPISODE",
              textAlign: TextAlign.center,
              style: PxFont.label(10).copyWith(shadows: PxFont.outline(1.2))),
          const SizedBox(height: 12),
          Text(
            _failReason ?? '',
            textAlign: TextAlign.center,
            style: PxFont.text(14, color: Px.ash, height: 1.45),
          ),
          const SizedBox(height: 22),
          PixelButton(label: 'Try again', icon: Sprites.refresh, onPressed: _resolve),
          if (offerSwitch) ...[
            const SizedBox(height: 14),
            PixelButton(
              label: 'Switch to $other',
              icon: Sprites.swap,
              kind: PixelButtonKind.dark,
              fontSize: 8,
              onPressed: _toggleCategory,
            ),
          ],
        ],
      ),
    );
  }
}

/// The subtitle line, drawn like game dialogue: pixel text on a dark box.
class _Captions extends StatelessWidget {
  final VideoPlayerController controller;
  final bool fullscreen;

  /// Raised clear of the HUD's bottom bar while it shows.
  final bool lifted;

  const _Captions({required this.controller, required this.fullscreen, required this.lifted});

  /// Subtitle size from Settings.
  static double get _scale => switch (AppSettings.subSize) { 's' => 0.8, 'l' => 1.25, 'xl' => 1.5, _ => 1.0 };

  @override
  Widget build(BuildContext context) {
    // The bottom bar is a seek track plus a row of buttons: 92dp tall in
    // landscape, 60dp in the portrait player.
    final bottom = lifted ? (fullscreen ? 98.0 : 64.0) : (fullscreen ? 24.0 : 10.0);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, v, __) {
        final text = v.caption.text.trim();
        if (text.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, bottom),
            child: Container(
              color: AppSettings.subBg ? const Color(0xA6050305) : Colors.transparent,
              padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: PxFont.text((fullscreen ? 17 : 12) * _scale, color: Px.bone, height: 1.25)
                    .copyWith(shadows: PxFont.outline(1.2)),
              ),
            ),
          ),
        );
      },
    );
  }
}


/// The watch party under the portrait player: code, who is here, chat.
class _PartyPanel extends StatefulWidget {
  final PartyConnection party;
  final VoidCallback onLeave;
  const _PartyPanel({required this.party, required this.onLeave});

  @override
  State<_PartyPanel> createState() => _PartyPanelState();
}

class _PartyPanelState extends State<_PartyPanel> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    widget.party.say(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.party;
    return ColoredBox(
      color: Px.ink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const PixelSprite(Sprites.party, scale: 2),
              const SizedBox(width: 8),
              Text(p.code, style: PxFont.label(10, color: Px.gold)),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: p.members,
                  builder: (_, m, __) => ValueListenableBuilder<String>(
                    valueListenable: p.status,
                    builder: (_, st, __) => Text(
                      st.isNotEmpty ? st : '${m.length} watching: ${m.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PxFont.text(12, color: Px.ash),
                    ),
                  ),
                ),
              ),
              PixelIconButton(
                sprite: Sprites.flag,
                tooltip: 'Copy invite',
                color: Px.ash,
                scale: 1.8,
                size: 40,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: p.inviteLink));
                  if (context.mounted) pixelToast(context, 'Invite link copied (party code ${p.code}).');
                },
              ),
              PixelIconButton(sprite: Sprites.close, tooltip: 'Leave the party', color: Px.ash, scale: 1.8, size: 40, onPressed: widget.onLeave),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: ValueListenableBuilder<List<(String, String)>>(
                valueListenable: p.chat,
                builder: (_, lines, __) => ListView(
                  reverse: true,
                  children: [
                    for (final (name, text) in lines.reversed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text.rich(TextSpan(children: [
                          if (name.isNotEmpty) TextSpan(text: '$name: ', style: PxFont.text(13, color: Px.bloodLight)),
                          TextSpan(text: text, style: PxFont.text(13, color: name.isEmpty ? Px.ashDark : Px.bone)),
                        ])),
                      ),
                  ],
                ),
              ),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 200,
                  style: PxFont.text(15),
                  decoration: const InputDecoration(hintText: 'Say something', counterText: '', isDense: true),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              PixelButton(label: 'Send', fontSize: 7, onPressed: _send),
            ]),
          ],
        ),
      ),
    );
  }
}
