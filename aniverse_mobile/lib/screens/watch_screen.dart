import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoPlayerController;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: isLoading
              ? const AniVerseLoader(size: 72, label: 'FINDING SOURCES')
              : controller != null && controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(controller),
                          AniVersePlayerControls(
                            controller: controller,
                            title: 'Episode ${widget.epNum}',
                            intro: _intro,
                            outro: _outro,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AniVerseTheme.textDim, size: 40),
                        const SizedBox(height: 12),
                        const Text('Failed to load video stream.',
                            style: TextStyle(color: Colors.white)),
                        const SizedBox(height: 6),
                        const Text('Try switching Audio in settings.',
                            style: TextStyle(color: AniVerseTheme.textFaint, fontSize: 12)),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              category = category == 'sub' ? 'dub' : 'sub';
                              _videoPlayerController?.dispose();
                              _videoPlayerController = null;
                              _loadStream();
                            });
                          },
                          child: Text('Switch to ${category == 'sub' ? 'DUB' : 'SUB'}',
                              style: const TextStyle(color: AniVerseTheme.red)),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
