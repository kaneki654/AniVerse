import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/player_controls.dart';

class WatchScreen extends StatefulWidget {
  final String animeId;
  final int epNum;

  const WatchScreen({super.key, required this.animeId, required this.epNum});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  VideoPlayerController? _videoPlayerController;
  bool isLoading = true;
  String category = 'sub';
  Map<String, dynamic>? _intro;
  Map<String, dynamic>? _outro;

  /// Whether the system UI is currently hidden. Tracked so the immersive-mode
  /// call only fires on an actual change instead of on every rebuild.
  bool _immersive = false;

  @override
  void initState() {
    super.initState();
    // Rotation is what drives fullscreen, so landscape has to be allowed while
    // a video is open. The rest of the app stays portrait, which is why this is
    // set here and undone in dispose rather than in main().
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadStream();
  }

  Future<void> _loadStream() async {
    setState(() => isLoading = true);

    try {
      final data = await ApiService.getSources(widget.animeId, widget.epNum, category);
      final sources = (data['sources'] ?? []) as List;
      _intro = data['intro'] as Map<String, dynamic>?;
      _outro = data['outro'] as Map<String, dynamic>?;

      // Try each source in turn. A single failing server used to end the
      // attempt even when a working one sat next in the list, which is what
      // the web player does recover from.
      for (final source in sources) {
        final map = source as Map<String, dynamic>;
        final streamUrl = (map['url'] ?? '').toString();
        if (streamUrl.isEmpty) continue;

        // ExoPlayer infers the container from the URL's extension, and the
        // proxied URL is "/proxy/m3u8?url=..." with no ".m3u8" on the path, so
        // without this hint it runs progressive MP4 extractors over an HLS
        // playlist and fails with "None of the available extractors could read
        // the stream".
        final isHls = map['isM3U8'] == true || streamUrl.contains('m3u8');

        final controller = VideoPlayerController.networkUrl(
          Uri.parse(streamUrl),
          formatHint: isHls ? VideoFormat.hls : null,
        );

        try {
          await controller.initialize();
        } catch (e) {
          print('source ${map['serverName']} failed: $e');
          await controller.dispose();
          continue;
        }

        _videoPlayerController = controller;
        controller.play();
        break;
      }
    } catch (e) {
      print('loadStream failed: $e');
    }

    if (mounted) setState(() => isLoading = false);
  }

  /// Reload the current episode on the other audio track.
  void _toggleCategory() {
    final next = category == 'sub' ? 'dub' : 'sub';
    final old = _videoPlayerController;
    setState(() {
      category = next;
      _videoPlayerController = null;
    });
    old?.dispose();
    _loadStream();
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
    _videoPlayerController?.dispose();
    // Leave the device as the rest of the app expects to find it.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoPlayerController;
    // Landscape is fullscreen: no chrome, video filling the screen. This is the
    // auto-landscape behaviour Chewie used to provide before the player was
    // rebuilt with custom controls.
    final fullscreen =
        MediaQuery.of(context).orientation == Orientation.landscape;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncSystemUi(fullscreen));

    final ready = controller != null && controller.value.isInitialized;

    Widget body;
    if (isLoading) {
      body = const AniVerseLoader(size: 72, label: 'FINDING SOURCES');
    } else if (ready) {
      final player = Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(controller),
          AniVersePlayerControls(
            controller: controller,
            title: 'Episode ${widget.epNum}',
            intro: _intro,
            outro: _outro,
            category: category,
            onToggleCategory: _toggleCategory,
            isFullscreen: fullscreen,
            onToggleFullscreen: () => _toggleFullscreen(fullscreen),
          ),
        ],
      );

      final ratio = controller.value.aspectRatio == 0
          ? 16 / 9
          : controller.value.aspectRatio;

      // In landscape the video takes the whole screen; in portrait it keeps its
      // aspect ratio so the episode list is not pushed off-screen.
      body = fullscreen
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: player,
                ),
              ),
            )
          : AspectRatio(aspectRatio: ratio, child: player);
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AniVerseTheme.textDim, size: 40),
          const SizedBox(height: 12),
          const Text('Failed to load video stream.',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          Text('No $category source for this episode.',
              style: const TextStyle(
                  color: AniVerseTheme.textFaint, fontSize: 12)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _toggleCategory,
            child: Text('Switch to ${category == 'sub' ? 'DUB' : 'SUB'}',
                style: const TextStyle(color: AniVerseTheme.red)),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      // SafeArea would letterbox the video behind the notch in landscape, so it
      // only applies while the system bars are actually showing.
      body: fullscreen ? Center(child: body) : SafeArea(child: Center(child: body)),
    );
  }
}
