import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../pixel/blood.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';

/// Player controls for the 2D UI: a game HUD instead of gradient scrims --
/// hard bars edged in blood, sprite buttons, a health-bar seek track with a
/// blood-drop handle.
///
/// Same inputs and behaviour as the classic controls.
class AniVersePlayerControls extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;
  final Map<String, dynamic>? intro;
  final Map<String, dynamic>? outro;
  final VoidCallback? onNextEpisode;
  final String category;
  final VoidCallback? onToggleCategory;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  /// Hide the centre play/seek buttons while the buffering orb sits there.
  final bool hideTransport;

  /// Whether subtitles are showing; null when the source has none, which
  /// hides the CC button.
  final bool? captionsOn;
  final VoidCallback? onToggleCaptions;

  /// Told when the HUD shows or hides, so subtitles can move clear of it.
  final ValueChanged<bool>? onHudVisibleChanged;

  const AniVersePlayerControls({
    super.key,
    required this.controller,
    required this.title,
    this.intro,
    this.outro,
    this.onNextEpisode,
    this.category = 'sub',
    this.onToggleCategory,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.hideTransport = false,
    this.captionsOn,
    this.onToggleCaptions,
    this.onHudVisibleChanged,
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
    // A fresh HUD starts shown; the parent may remember an old one as hidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHudVisibleChanged?.call(_visible);
    });
  }

  @override
  void didUpdateWidget(covariant AniVersePlayerControls old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
    }
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
      if (!mounted) return;
      // A seek usually lands mid-buffer, and ExoPlayer reports "not playing"
      // for the whole stall -- which used to read as paused and leave the HUD
      // up for good. Still buffering is not paused: look again shortly.
      if (_c.value.isBuffering) return _scheduleHide();
      if (_c.value.isPlaying) _setVisible(false);
    });
  }

  void _setVisible(bool v) {
    setState(() => _visible = v);
    widget.onHudVisibleChanged?.call(v);
  }

  void _toggleVisible() {
    _setVisible(!_visible);
    if (_visible) _scheduleHide();
  }

  void _togglePlay() {
    setState(() => _c.value.isPlaying ? _c.pause() : _c.play());
    _scheduleHide();
  }

  void _seekBy(int seconds) {
    final target = _c.value.position + Duration(seconds: seconds);
    final max = _c.value.duration;
    _c.seekTo(target < Duration.zero ? Duration.zero : (target > max ? max : target));
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
    // Until a second before the end: landing on the end itself after a skip
    // should not leave the button up.
    if (widget.intro != null &&
        pos >= (widget.intro!['start'] ?? 0) &&
        pos < (widget.intro!['end'] ?? 0) - 1) {
      active = widget.intro;
      label = 'Skip intro';
    } else if (widget.outro != null &&
        pos >= (widget.outro!['start'] ?? 0) &&
        pos < (widget.outro!['end'] ?? 0) - 1) {
      active = widget.outro;
      label = 'Skip outro';
    }
    if (active == null) return null;
    return PixelButton(
      label: label,
      icon: Sprites.forward,
      kind: PixelButtonKind.bone,
      fontSize: 8,
      onPressed: () => _c.seekTo(Duration(seconds: (active!['end'] as num).toInt())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _c.value;
    final skip = _skipButton();
    const hud = Color(0xB3050305);
    // The portrait player is only ~230dp tall, so the HUD there is smaller:
    // full-size bars and buttons overlapped each other.
    final compact = !widget.isFullscreen;

    return GestureDetector(
      onTap: _toggleVisible,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // While the HUD is hidden the skip button floats bottom-right, so an
          // intro can still be skipped mid-watch.
          if (skip != null && !_visible) Positioned(right: 16, bottom: 20, child: skip),

          IgnorePointer(
            ignoring: !_visible,
            // Shown and hidden in one step, like a game HUD, not faded.
            child: Visibility(
              visible: _visible,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: Stack(
                children: [
                  // Top bar.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: hud,
                        border: Border(bottom: BorderSide(color: Px.blood, width: 2)),
                      ),
                      padding: EdgeInsets.fromLTRB(4, compact ? 0 : 4, 10, compact ? 0 : 4),
                      child: Row(
                        children: [
                          PixelIconButton(
                            sprite: Sprites.back,
                            tooltip: 'Back',
                            scale: compact ? 1.8 : 2.2,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          Expanded(
                            child: Text(
                              widget.title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PxFont.label(8).copyWith(shadows: PxFont.outline(1)),
                            ),
                          ),
                          if (widget.captionsOn != null && widget.onToggleCaptions != null) ...[
                            _CaptionsToggle(
                              on: widget.captionsOn!,
                              onTap: () {
                                widget.onToggleCaptions!();
                                _scheduleHide();
                              },
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (widget.onToggleCategory != null)
                            _AudioToggle(
                              category: widget.category,
                              onTap: () {
                                widget.onToggleCategory!();
                                _scheduleHide();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (!widget.hideTransport)
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SkipTen(
                              sprite: Sprites.rewind, size: compact ? 44 : 52, onTap: () => _seekBy(-10)),
                          SizedBox(width: compact ? 18 : 22),
                          _PlayButton(
                              playing: value.isPlaying, size: compact ? 54 : 68, onTap: _togglePlay),
                          SizedBox(width: compact ? 18 : 22),
                          _SkipTen(
                              sprite: Sprites.forward, size: compact ? 44 : 52, onTap: () => _seekBy(10)),
                        ],
                      ),
                    ),

                  // Bottom bar.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: hud,
                        border: Border(top: BorderSide(color: Px.blood, width: 2)),
                      ),
                      padding: EdgeInsets.fromLTRB(12, compact ? 0 : 6, 6, compact ? 0 : 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SeekBar(
                            height: compact ? 22 : 30,
                            value: value,
                            onSeek: (d) {
                              _c.seekTo(d);
                              _scheduleHide();
                            },
                          ),
                          Row(
                            children: [
                              Text(_fmt(value.position), style: PxFont.label(7, color: Px.bone)),
                              Text(' / ${_fmt(value.duration)}', style: PxFont.label(7, color: Px.ash)),
                              const Spacer(),
                              if (widget.onNextEpisode != null)
                                PixelIconButton(
                                  sprite: Sprites.skipNext,
                                  tooltip: 'Next episode',
                                  scale: 1.8,
                                  onPressed: widget.onNextEpisode,
                                ),
                              if (skip != null) ...[skip, const SizedBox(width: 6)],
                              if (widget.onToggleFullscreen != null)
                                PixelIconButton(
                                  sprite: widget.isFullscreen
                                      ? Sprites.fullscreenExit
                                      : Sprites.fullscreen,
                                  tooltip: widget.isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                                  scale: compact ? 1.6 : 2,
                                  size: compact ? 36 : 48,
                                  onPressed: () {
                                    widget.onToggleFullscreen!();
                                    _scheduleHide();
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
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

class _PlayButton extends StatefulWidget {
  final bool playing;
  final double size;
  final VoidCallback onTap;
  const _PlayButton({required this.playing, required this.onTap, this.size = 68});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.playing ? 'Pause' : 'Play',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (d) {
          setState(() => _down = false);
          BloodSplat.show(context, d.globalPosition);
          widget.onTap();
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: PixelBox(
            fill: Px.blood,
            pressed: _down,
            bevel: true,
            shadow: 4,
            borderWidth: 3,
            child: Center(
              child: PixelSprite(
                widget.playing ? Sprites.pause : Sprites.play,
                scale: widget.size / 23,
                color: Px.bone,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipTen extends StatelessWidget {
  final Sprite sprite;
  final double size;
  final VoidCallback onTap;
  const _SkipTen({required this.sprite, required this.onTap, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: sprite == Sprites.rewind ? 'Back 10 seconds' : 'Forward 10 seconds',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: PixelBox(
            fill: const Color(0xCC1B1114),
            shadow: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PixelSprite(sprite, scale: 2, color: Px.bone),
                const SizedBox(height: 3),
                Text('10', style: PxFont.label(7, color: Px.bone, height: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// CC button: lit while subtitles show; tap to turn them on or off.
class _CaptionsToggle extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _CaptionsToggle({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Subtitles ${on ? 'on' : 'off'}. Tap to turn ${on ? 'off' : 'on'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: PixelBox(
          fill: on ? Px.blood : Px.panel,
          shadow: 2,
          padding: const EdgeInsets.fromLTRB(7, 5, 7, 4),
          child: Text('CC', style: PxFont.label(8, color: on ? Px.bone : Px.ash, height: 1.2)),
        ),
      ),
    );
  }
}

/// SUB / DUB toggle: the track playing now; tap to switch.
class _AudioToggle extends StatelessWidget {
  final String category;
  final VoidCallback onTap;

  const _AudioToggle({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Audio: ${category == 'sub' ? 'subtitles' : 'dub'}. Tap to switch',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: PixelBox(
          fill: Px.blood,
          shadow: 2,
          padding: const EdgeInsets.fromLTRB(6, 5, 7, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelSprite(Sprites.swap, scale: 1.3),
              const SizedBox(width: 6),
              Text(category == 'sub' ? 'SUB' : 'DUB', style: PxFont.label(8, height: 1.2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seek track drawn as a health bar: black frame, dark trough, buffered in
/// ash, played in blood, and a blood-drop handle. Drag or tap anywhere.
class _SeekBar extends StatefulWidget {
  final VideoPlayerValue value;
  final ValueChanged<Duration> onSeek;
  final double height;

  const _SeekBar({required this.value, required this.onSeek, this.height = 30});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  double get _played {
    final d = widget.value.duration.inMilliseconds;
    return d <= 0 ? 0 : widget.value.position.inMilliseconds / d;
  }

  double get _buffered {
    final d = widget.value.duration.inMilliseconds;
    if (d <= 0) return 0;
    var end = 0;
    for (final r in widget.value.buffered) {
      if (r.end.inMilliseconds > end) end = r.end.inMilliseconds;
    }
    return end / d;
  }

  void _seekTo(double f, double width) {
    final frac = (f / width).clamp(0.0, 1.0);
    setState(() => _drag = frac);
    widget.onSeek(Duration(
        milliseconds: (widget.value.duration.inMilliseconds * frac).round()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Semantics(
          slider: true,
          label: 'Seek',
          value: '${((_drag ?? _played) * 100).round()}%',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _seekTo(d.localPosition.dx, w),
            onTapUp: (_) => setState(() => _drag = null),
            onHorizontalDragUpdate: (d) => _seekTo(d.localPosition.dx, w),
            onHorizontalDragEnd: (_) => setState(() => _drag = null),
            child: SizedBox(
              height: widget.height,
              width: w,
              child: CustomPaint(
                painter: _SeekPainter(
                  played: _drag ?? _played,
                  buffered: _buffered,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  final double played;
  final double buffered;
  _SeekPainter({required this.played, required this.buffered});

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 2.0;
    final pc = PixelCanvas(canvas, cell);
    final cols = (size.width / cell).floor();
    final mid = (size.height / cell / 2).floor();
    // Track: 4 cells tall, framed.
    pc.rect(0, mid - 2, cols, 5, Px.black);
    pc.rect(1, mid - 1, cols - 2, 3, Px.bloodDeep);
    final inner = cols - 2;
    final b = (inner * buffered.clamp(0.0, 1.0)).floor();
    pc.rect(1, mid - 1, b, 3, Px.ashDark);
    final p = (inner * played.clamp(0.0, 1.0)).floor();
    pc.rect(1, mid - 1, p, 3, Px.blood);
    pc.rect(1, mid - 1, p, 1, Px.bloodLight);
    // Handle: the blood drop sprite, centred on the playhead.
    const drop = Sprites.bloodDrop;
    final hx = (1 + p - drop.w ~/ 2).clamp(0, cols - drop.w);
    pc.sprite(drop, hx, mid - drop.h ~/ 2 - 1);
  }

  @override
  bool shouldRepaint(covariant _SeekPainter o) =>
      o.played != played || o.buffered != buffered;
}
