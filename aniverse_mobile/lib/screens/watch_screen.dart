import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../services/api_service.dart';

class WatchScreen extends StatefulWidget {
  final String animeId;
  final int epNum;

  const WatchScreen({super.key, required this.animeId, required this.epNum});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool isLoading = true;
  String category = 'sub';

  @override
  void initState() {
    super.initState();
    _loadStream();
  }

  Future<void> _loadStream() async {
    setState(() => isLoading = true);
    
    try {
      final data = await ApiService.getSources(widget.animeId, widget.epNum, category);
      if (data['streams'] != null && data['streams'].isNotEmpty) {
        final streamUrl = data['streams'][0]['url'];
        
        _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
        await _videoPlayerController!.initialize();
        
        _chewieController = ChewieController(
          videoPlayerController: _videoPlayerController!,
          autoPlay: true,
          looping: false,
          aspectRatio: 16 / 9,
          materialProgressColors: ChewieProgressColors(
            playedColor: const Color(0xFFE50914),
            handleColor: const Color(0xFFE50914),
            backgroundColor: Colors.grey,
            bufferedColor: Colors.white,
          ),
        );
      }
    } catch (e) {
      print(e);
    }
    
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Episode ${widget.epNum}'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                category = category == 'sub' ? 'dub' : 'sub';
                _videoPlayerController?.dispose();
                _chewieController?.dispose();
                _loadStream();
              });
            },
            child: Text(category.toUpperCase(), style: const TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator(color: Color(0xFFE50914))
            : _chewieController != null
                ? Chewie(controller: _chewieController!)
                : const Text('Failed to load video stream.', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
