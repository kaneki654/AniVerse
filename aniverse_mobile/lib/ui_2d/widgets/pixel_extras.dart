import 'package:flutter/material.dart';

import '../../services/native_bridge.dart';
import '../pixel/blood.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';

// --- anime helpers (the website's api.js titleOf / coverOf / airedEpisodes) -----------

String titleOf(Map? a) {
  final t = a?['title'];
  if (t is Map) {
    for (final k in const ['english', 'romaji']) {
      final v = t[k];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  return (a?['name'] ?? 'Untitled').toString();
}

String coverOf(Map? a) {
  final c = a?['coverImage'];
  if (c is Map) return (c['large'] ?? c['medium'] ?? '').toString();
  return (a?['cover'] ?? '').toString();
}

/// Episodes that can be played now: aired ones for a show still airing.
int airedEpisodes(Map? a) {
  final next = a?['nextAiringEpisode'];
  if (next is Map && next['episode'] is num && (next['episode'] as num) > 1) {
    return (next['episode'] as num).toInt() - 1;
  }
  if (a?['status'] == 'NOT_YET_RELEASED') return 0;
  final eps = a?['episodes'];
  return eps is num && eps > 0 ? eps.toInt() : 12;
}

/// A short pixel toast at the bottom of the screen.
void pixelToast(BuildContext context, String text, {String? action, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 4),
      persist: false,
      action: action == null ? null : SnackBarAction(label: action, textColor: Px.bloodLight, onPressed: onAction ?? () {}),
    ));
}

// --- settings rows ----------------------------------------------------------------------

/// An on/off switch drawn as a pixel slider.
class PixelSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const PixelSwitch({super.key, required this.value, required this.onChanged, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          Sfx.play('select');
          onChanged(!value);
        },
        child: SizedBox(
          width: 52,
          height: 30,
          child: PixelBox(
            fill: value ? Px.bloodDark : Px.panelHigh,
            shadow: 2,
            child: Align(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: SizedBox(width: 16, height: 16, child: ColoredBox(color: value ? Px.bloodLight : Px.ash)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row: a label and explanation on the left, a control on the right.
class SettingRow extends StatelessWidget {
  final String title;
  final String text;
  final Widget control;
  final VoidCallback? onTap;

  const SettingRow({super.key, required this.title, required this.text, required this.control, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PixelBox(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: PxFont.label(8)),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(text, style: PxFont.text(13, color: Px.ash)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              control,
            ],
          ),
        ),
      ),
    );
  }
}

/// A value chip that opens a list to pick from.
class ChoiceChipButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const ChoiceChipButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PixelBox(
        fill: Px.panelHigh,
        shadow: 2,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: PxFont.label(7, height: 1.3)),
          const SizedBox(width: 6),
          const PixelSprite(Sprites.chevron, scale: 1, color: Px.ash),
        ]),
      ),
    );
  }
}

/// A bottom sheet of options, the current one marked. Returns the pick.
Future<T?> pickOption<T>(BuildContext context, String title, List<(T, String)> options, T? current) {
  Sfx.play('click');
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: PixelBox(
          fill: Px.ink,
          border: Px.blood,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title.toUpperCase(), style: PxFont.label(8, color: Px.ash)),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (value, label) in options)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Sfx.play('select');
                            Navigator.pop(ctx, value);
                          },
                          child: Container(
                            color: value == current ? Px.panelHigh : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                            child: Row(children: [
                              Expanded(child: Text(label.toUpperCase(), style: PxFont.label(8, height: 1.3))),
                              if (value == current) SizedBox(width: 10, height: 10, child: ColoredBox(color: Px.bloodLight)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// --- the boss fight -----------------------------------------------------------------------
// When no stream plays, the failure skull is a glitch demon with five hit
// points. Every hit splatters; the last one runs [onDefeat] (a retry). The
// buttons below it still work for anyone not in the mood.

class BossFight extends StatefulWidget {
  final VoidCallback onDefeat;
  final double size;
  const BossFight({super.key, required this.onDefeat, this.size = 120});

  @override
  State<BossFight> createState() => _BossFightState();
}

class _BossFightState extends State<BossFight> {
  static const _hp = 5;
  static const _rows = [
    '..K..........K..', '.KHK........KHK.', '.KRRK......KRRK.', '..KRRKKKKKKRRK..',
    '...KRRRRRRRRK...', '..KRRRRRRRRRRK..', '.KRRWWRRRRWWRRK.', '.KRWYYWRRWYYWRK.',
    '.KRRWWRRRRWWRRK.', '.KrRRRRRRRRRRrK.', '..KrRRRKKRRRrK..', '..KrRKWKKWKRrK..',
    '...KrKWWWWKrK...', '...KrrKKKKrrK...', '....KrrrrrrK....', '.....KKKKKK.....',
  ];
  int hp = _hp;
  int flash = 0;
  int? deadAt;
  int frame = 0;

  void _hit(TapUpDetails d) {
    if (deadAt != null) return;
    setState(() {
      hp--;
      flash = 2;
      if (hp <= 0) deadAt = frame;
    });
    BloodSplat.show(context, d.globalPosition);
    Sfx.play(hp > 0 ? 'hit' : 'boss');
    if (hp <= 0) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) widget.onDefeat();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Hit the glitch ($hp hits left) to retry',
          child: GestureDetector(
            onTapUp: _hit,
            child: FrameClock(
              fps: 8,
              frames: 4096,
              builder: (_, f) {
                frame = f;
                final painter = _BossPainter(_rows, f, hp, flash > 0, deadAt == null ? null : f - deadAt!);
                if (flash > 0) flash--;
                return SizedBox(width: widget.size, height: widget.size, child: CustomPaint(painter: painter));
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(width: 180, child: PixelBar(fraction: hp / _hp, height: 12)),
        const SizedBox(height: 8),
        Text(
          deadAt != null ? 'SLAIN. RETRYING…' : hp == _hp ? 'HIT THE GLITCH TO RETRY' : '$hp MORE HIT${hp == 1 ? '' : 'S'}',
          style: PxFont.label(7, color: Px.ash),
        ),
      ],
    );
  }
}

class _BossPainter extends CustomPainter {
  final List<String> rows;
  final int frame;
  final int hp;
  final bool flash;
  final int? dying;
  _BossPainter(this.rows, this.frame, this.hp, this.flash, this.dying);

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / 22, glow: dying == null);
    final bob = dying != null ? 0 : (frame % 4 < 2 ? 0 : 1);
    final blink = frame % 16 == 0;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        var ch = rows[y][x];
        if (ch == '.') continue;
        if (ch == 'Y' && (blink || hp <= 2)) ch = hp <= 2 ? 'H' : 'R';
        // Dying: cells fall away in a stable, scattered order.
        if (dying != null && (x * 7 + y * 13) % 10 < dying!.clamp(0, 10)) continue;
        final c = flash && ch != 'K' ? Px.bone : (Px.keys[ch] ?? Px.bone);
        pc.px(3 + x, 3 + y + bob, c);
      }
    }
    pc.commit(strength: 0.9);
  }

  @override
  bool shouldRepaint(covariant _BossPainter old) => true;
}

/// Nothing to show: the skull, a heading, a line, and maybe a button.
class EmptyState extends StatelessWidget {
  final String title;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PixelSprite(Sprites.skull, scale: 4.5),
          const SizedBox(height: 16),
          Text(title.toUpperCase(), textAlign: TextAlign.center, style: PxFont.label(10).copyWith(shadows: PxFont.outline(1.2))),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: PxFont.text(14, color: Px.ash, height: 1.45)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
