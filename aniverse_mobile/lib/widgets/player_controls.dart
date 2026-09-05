import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

/// AniVerse player controls.
///
/// Replaces Chewie's stock Material controls: gradient scrims instead of a flat
/// dim, a red seek bar, 10s skip arcs, and Skip Intro / Skip Outro buttons fed
/// by the markers the API already returns.
class AniVersePlayerControls extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;
  final Map<String, dynamic>? intro;
  final Map<String, dynamic>? outro;
  final VoidCallback? onNextEpisode;

  const AniVersePlayerControls({
    super.key,
    required this.controller,
    required this.title,
    this.intro,
    this.outro,
    this.onNextEpisode,
  });

  @override
  State<AniVersePlayerControls> createState() => _AniVersePlayerControlsState();
}

class _AniVersePlayerControlsState extends State<AniVersePlayerControls> {
  bool _visible = true;
  Timer? _hideTimer;

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _c.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // Controls stay put while paused; hiding them mid-pause is annoying.
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _visible = false);
    });
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  void _togglePlay() {
    setState(() => _c.value.isPlaying ? _c.pause() : _c.play());
    _scheduleHide();
  }

  void _seekBy(int seconds) {
    final target = _c.value.position + Duration(seconds: seconds);
    final max = _c.value.duration;
    _c.seekTo(target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target));
    _scheduleHide();
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// A skip button when the playhead sits inside a marker range.
  Widget? _skipButton() {
    final pos = _c.value.position.inSeconds;

    Map<String, dynamic>? active;
    String label = '';
    if (widget.intro != null &&
        pos >= (widget.intro!['start'] ?? 0) &&
        pos <= (widget.intro!['end'] ?? 0)) {
      active = widget.intro;
      label = 'Skip Intro';
    } else if (widget.outro != null &&
        pos >= (widget.outro!['start'] ?? 0) &&
        pos <= (widget.outro!['end'] ?? 0)) {
      active = widget.outro;
      label = 'Skip Outro';
    }
    if (active == null) return null;

    return Positioned(
      right: 20,
      bottom: 90,
      child: ElevatedButton.icon(
        onPressed: () =>
            _c.seekTo(Duration(seconds: (active!['end'] as num).toInt())),
        icon: const Icon(Icons.fast_forward, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.92),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _c.value;
    final position = value.position;
    final duration = value.duration;
    final skip = _skipButton();

    return GestureDetector(
      onTap: _toggleVisible,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Skip buttons stay available even when the chrome is hidden.
          if (skip != null) skip,

          AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_visible,
              child: Stack(
                children: [
                  // Scrims: readable controls without dimming the whole frame.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.25, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Centre transport: back 10 / play / forward 10.
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoundButton(
                          icon: Icons.replay_10,
                          onTap: () => _seekBy(-10),
                        ),
                        const SizedBox(width: 28),
                        _RoundButton(
                          icon: value.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 64,
                          filled: true,
                          onTap: _togglePlay,
                        ),
                        const SizedBox(width: 28),
                        _RoundButton(
                          icon: Icons.forward_10,
                          onTap: () => _seekBy(10),
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: AniVerseTheme.red,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AniVerseTheme.red,
                            overlayColor: AniVerseTheme.red.withValues(alpha: 0.2),
                            thumbShape:
                                const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape:
                                const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            value: position.inMilliseconds
                                .clamp(0, duration.inMilliseconds)
                                .toDouble(),
                            max: duration.inMilliseconds
                                .toDouble()
                                .clamp(1, double.infinity),
                            onChanged: (v) {
                              _c.seekTo(Duration(milliseconds: v.round()));
                              _scheduleHide();
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Text(_fmt(position),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              const Spacer(),
                              if (widget.onNextEpisode != null)
                                TextButton.icon(
                                  onPressed: widget.onNextEpisode,
                                  icon: const Icon(Icons.skip_next,
                                      color: Colors.white, size: 18),
                                  label: const Text('Next',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              const Spacer(),
                              Text(_fmt(duration),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool filled;

  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? AniVerseTheme.red : Colors.black.withValues(alpha: 0.35),
          border: filled ? null : Border.all(color: Colors.white24),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: AniVerseTheme.red.withValues(alpha: 0.5),
                    blurRadius: 18,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}
