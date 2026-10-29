import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/native_bridge.dart';
import '../ink/ink_widgets.dart';
import '../ink/manga.dart';

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

// --- toasts: speech bubbles ----------------------------------------------------------------------

OverlayEntry? _toast;
Timer? _toastTimer;

/// A message in a speech bubble that pops up from the foot of the screen
/// (with its tail pointing down at whatever said it), stays a few seconds and
/// pops away. [action] adds a red button in the bubble.
void mangaToast(BuildContext context, String text, {String? action, VoidCallback? onAction}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastTimer?.cancel();
  _toast?.remove();
  final key = GlobalKey<_ToastBubbleState>();
  late final OverlayEntry entry;
  void close() {
    _toastTimer?.cancel();
    key.currentState?.leave().then((_) {
      if (_toast == entry) _toast = null;
      if (entry.mounted) entry.remove();
    });
  }

  entry = OverlayEntry(
    builder: (ctx) => _ToastBubble(
      key: key,
      text: text,
      action: action,
      onAction: onAction == null
          ? null
          : () {
              close();
              onAction();
            },
    ),
  );
  _toast = entry;
  overlay.insert(entry);
  Sfx.play('pop');
  _toastTimer = Timer(const Duration(seconds: 4), close);
}

class _ToastBubble extends StatefulWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const _ToastBubble({super.key, required this.text, this.action, this.onAction});

  @override
  State<_ToastBubble> createState() => _ToastBubbleState();
}

class _ToastBubbleState extends State<_ToastBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  Future<void> leave() => _c.reverse();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 86;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.elasticOut.transform(_c.value);
          return Opacity(
            opacity: _c.value.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.4 + 0.6 * t, alignment: Alignment.bottomLeft, child: child),
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: SpeechBubble(
            tail: const Alignment(-0.6, 1),
            child: Row(children: [
              Expanded(child: Text(widget.text, style: MgFont.text(15))),
              if (widget.action != null) ...[
                const SizedBox(width: 10),
                InkButton(label: widget.action!, fontSize: 8, onPressed: widget.onAction),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// --- settings rows ----------------------------------------------------------------------

/// An on/off switch: a small panel lettered OFF, or red with ON! when on, the
/// block inside thrown across.
class InkSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const InkSwitch({super.key, required this.value, required this.onChanged, required this.label});

  void _flip() {
    Sfx.play('select');
    onChanged(!value);
  }

  @override
  Widget build(BuildContext context) => InkFocus(
        onActivate: _flip,
        child: Semantics(
          container: true,
          toggled: value,
          label: label,
          button: true,
          onTap: _flip,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: _flip,
            child: SizedBox(
              width: 62,
              height: 32,
              child: PanelBox(
                fill: value ? Mg.red : Mg.panel,
                shadow: 2,
                child: Stack(children: [
                  Align(
                    alignment: value ? Alignment.centerLeft : Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(value ? 'ON!' : 'OFF', style: MgFont.label(7, color: value ? Mg.white : Mg.gray)),
                    ),
                  ),
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutBack,
                    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: SizedBox(width: 18, height: 22, child: ColoredBox(color: Mg.ink)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// A settings row: a label and explanation on the left, a control on the right.
class SettingRow extends StatelessWidget {
  final String title;
  final String text;
  final Widget control;
  final VoidCallback? onTap;

  const SettingRow({super.key, required this.title, required this.text, required this.control, this.onTap});

  @override
  Widget build(BuildContext context) => InkFocus(
        onActivate: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: PanelBox(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title.toUpperCase(), style: MgFont.label(8.5)),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(text, style: MgFont.text(14, color: Mg.gray)),
                    ],
                  ]),
                ),
                const SizedBox(width: 12),
                control,
              ]),
            ),
          ),
        ),
      );
}

/// A value chip that opens a list to pick from.
class ChoiceChipButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const ChoiceChipButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkFocus(
        onActivate: onTap,
        child: Semantics(
          container: true,
          button: true,
          label: label,
          onTap: onTap,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            child: PanelBox(
              shadow: 2,
              padding: const EdgeInsets.fromLTRB(10, 7, 6, 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label.toUpperCase(), style: MgFont.label(7.5, height: 1.2)),
                const InkIcon(InkIcons.chevron, scale: 1.4),
              ]),
            ),
          ),
        ),
      );
}

/// A sheet of options, the current one stamped in red. Returns the pick. The
/// sheet is a panel slammed onto the page; its title sits in a caption box.
Future<T?> pickOption<T>(BuildContext context, String title, List<(T, String)> options, T? current) {
  Sfx.play('pop');
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Mg.ink.withValues(alpha: 0.45),
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: PanelBox(
          shadow: 5,
          borderWidth: 3,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    color: Mg.ink,
                    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                    child: Text(title.toUpperCase(), style: MgFont.heading(15, color: Mg.white)),
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final (value, label) in options)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Sfx.play('select');
                          Navigator.pop(ctx, value);
                        },
                        child: Container(
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Mg.tone, width: 1.5))),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
                          child: Row(children: [
                            Expanded(
                              child: Text(label.toUpperCase(),
                                  style: MgFont.label(8.5, color: value == current ? Mg.red : Mg.ink, height: 1.2)),
                            ),
                            if (value == current) const InkIcon(InkIcons.check, scale: 2, color: Mg.red),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// --- the shock panel ---------------------------------------------------------------------
// When no stream plays, the failure is a ガーン! panel (the manga sound of a
// shock). Every tap cracks it and jolts it; the third shatters it and runs
// [onDefeat] (a retry). The buttons below it still work for anyone not in
// the mood. Kept under the pixel UI's name, BossFight.

class BossFight extends StatefulWidget {
  final VoidCallback onDefeat;
  final double size;
  const BossFight({super.key, required this.onDefeat, this.size = 120});

  @override
  State<BossFight> createState() => _BossFightState();
}

class _BossFightState extends State<BossFight> {
  static const _hits = 3;
  int _left = _hits;
  final List<Offset> _cracks = [];

  void _hit(TapUpDetails d) {
    if (_left <= 0) return;
    final box = context.findRenderObject() as RenderBox?;
    final local = box == null ? Offset.zero : box.globalToLocal(d.globalPosition);
    setState(() {
      _left--;
      _cracks.add(local);
    });
    Sfx.play(_left > 0 ? 'hit' : 'don');
    if (_left <= 0) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) widget.onDefeat();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final done = _left <= 0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        container: true,
        button: true,
        label: 'Tap the panel ($_left taps left) to retry',
        child: GestureDetector(
          onTapUp: _hit,
          child: ImpactShake(
            trigger: _left,
            strength: 9,
            child: SizedBox(
              width: s * 1.7,
              height: s,
              child: CustomPaint(
                foregroundPainter: _CrackPainter(_cracks, done),
                child: SpeechBubble(
                  shout: true,
                  padding: EdgeInsets.zero,
                  child: Center(
                    child: done
                        ? SfxText('ドン!', size: s * 0.34, color: Mg.red)
                        : SfxText('ガーン!', size: s * 0.3, pop: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        done
            ? 'SMASHED. RETRYING…'
            : _left == _hits
                ? 'TAP THE PANEL TO RETRY'
                : '$_left MORE TAP${_left == 1 ? '' : 'S'}',
        style: MgFont.label(7, color: Mg.gray),
      ),
    ]);
  }
}

/// Cracks spreading from every tap: jagged ink lines, and on the last one a
/// burst across the whole panel.
class _CrackPainter extends CustomPainter {
  final List<Offset> at;
  final bool shattered;
  _CrackPainter(this.at, this.shattered);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Mg.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.miter;
    for (var n = 0; n < at.length; n++) {
      final rnd = math.Random(n * 97 + 5);
      final arms = shattered && n == at.length - 1 ? 9 : 5;
      for (var a = 0; a < arms; a++) {
        final angle = a / arms * 2 * math.pi + rnd.nextDouble() * 0.6;
        var pt = at[n];
        final path = Path()..moveTo(pt.dx, pt.dy);
        final reach = size.shortestSide * (shattered ? 0.9 : 0.35);
        for (var k = 0; k < 4; k++) {
          final turn = angle + (rnd.nextDouble() - 0.5) * 0.9;
          pt += Offset(math.cos(turn), math.sin(turn)) * reach / 4;
          path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CrackPainter old) => old.at.length != at.length || old.shattered != shattered;
}

/// Nothing to show: シーン… (the sound of silence), a heading, a line, and
/// maybe a button.
class EmptyState extends StatelessWidget {
  final String title;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SfxText('シーン…', size: 44, angle: -0.06),
        const SizedBox(height: 18),
        Text(title.toUpperCase(), textAlign: TextAlign.center, style: MgFont.heading(20)),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: MgFont.text(15, color: Mg.gray, height: 1.45)),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ]),
    );
  }
}
