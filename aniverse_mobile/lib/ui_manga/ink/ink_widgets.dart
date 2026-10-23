import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/native_bridge.dart';
import 'manga.dart';

// --- painters -----------------------------------------------------------------------------------

/// Screentone: dots on a 45-degree grid. [from]..[to] is the density along
/// [axis] (a gradient tone), flat when [to] is null. [shift] slides the grid,
/// for tone that drifts.
class HalftonePainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double from;
  final double? to;
  final Axis axis;
  final double shift;

  const HalftonePainter({
    this.color = Mg.ink,
    this.spacing = 7,
    this.from = 0.35,
    this.to,
    this.axis = Axis.vertical,
    this.shift = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final s = spacing;
    final rowStep = s * 0.71;
    var row = 0;
    for (var y = -s + (shift % s); y < size.height + s; y += rowStep, row++) {
      for (var x = (row.isOdd ? s / 2 : 0.0) - s; x < size.width + s; x += s) {
        final t = axis == Axis.vertical ? (y / size.height) : (x / size.width);
        final d = to == null ? from : from + (to! - from) * t.clamp(0.0, 1.0);
        if (d <= 0.02) continue;
        canvas.drawCircle(Offset(x, y), s * 0.5 * math.sqrt(d.clamp(0.0, 1.0)), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HalftonePainter old) =>
      old.shift != shift || old.from != from || old.to != to || old.color != color;
}

/// Focus lines (集中線): black wedges converging on [center], leaving a clear
/// middle. [seed] picks the pattern; a new seed each frame makes them flicker
/// like an animated manga.
class FocusLinesPainter extends CustomPainter {
  final Alignment center;
  final int seed;
  final int count;
  final double clear; // fraction of the short side left empty
  final Color color;

  const FocusLinesPainter(
      {this.center = Alignment.center, this.seed = 0, this.count = 90, this.clear = 0.42, this.color = Mg.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final c = center.alongSize(size);
    final reach = size.longestSide * 1.2;
    final rnd = math.Random(seed);
    final p = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final a = (i / count) * 2 * math.pi + rnd.nextDouble() * 0.05;
      final inner = size.shortestSide * (clear + rnd.nextDouble() * 0.22);
      final w = 0.006 + rnd.nextDouble() * 0.016; // the wedge's half-angle
      final tip = c + Offset(math.cos(a), math.sin(a)) * inner;
      final l = c + Offset(math.cos(a - w), math.sin(a - w)) * reach;
      final r = c + Offset(math.cos(a + w), math.sin(a + w)) * reach;
      canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(l.dx, l.dy)..lineTo(r.dx, r.dy)..close(), p);
    }
  }

  @override
  bool shouldRepaint(covariant FocusLinesPainter old) => old.seed != seed || old.center != center;
}

/// Parallel speed lines streaking across, for motion: strokes of uneven length
/// sliding by [phase].
class SpeedStreakPainter extends CustomPainter {
  final double phase;
  final Color color;
  final double angle;

  const SpeedStreakPainter({this.phase = 0, this.color = Mg.ink, this.angle = -0.18});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    final rnd = math.Random(7);
    final span = size.longestSide * 1.4;
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 46; i++) {
      final y = (rnd.nextDouble() - 0.5) * span;
      final len = span * (0.1 + rnd.nextDouble() * 0.35);
      final x = ((rnd.nextDouble() + phase * (0.8 + rnd.nextDouble())) % 1.0) * (span + len) - span / 2 - len;
      p.strokeWidth = 0.8 + rnd.nextDouble() * 2.2;
      canvas.drawLine(Offset(x, y), Offset(x + len, y), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SpeedStreakPainter old) => old.phase != phase;
}

/// A speech bubble: a rounded body with a tail at [tail]'s side of its foot.
/// [shout] draws a jagged burst instead.
class BubblePainter extends CustomPainter {
  final Color fill;
  final Color border;
  final double width;
  final Alignment tail;
  final bool shout;

  const BubblePainter(
      {this.fill = Mg.panel, this.border = Mg.ink, this.width = 2.5, this.tail = Alignment.bottomLeft, this.shout = false});

  Path _path(Size s) {
    final body = Rect.fromLTWH(0, 0, s.width, s.height - 12);
    var path = Path();
    if (shout) {
      const spikes = 22;
      final c = body.center;
      for (var i = 0; i <= spikes * 2; i++) {
        final a = i / (spikes * 2) * 2 * math.pi;
        final k = i.isEven ? 1.0 : 0.84;
        final pt = c + Offset(math.cos(a) * body.width / 2 * k, math.sin(a) * body.height / 2 * k);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      path.close();
    } else {
      path.addRRect(RRect.fromRectAndRadius(body, Radius.circular(math.min(18, body.height / 2))));
    }
    final baseX = Alignment(tail.x.clamp(-0.7, 0.7), 1).alongSize(body.size).dx;
    final tailPath = Path()
      ..moveTo(baseX - 9, body.bottom - 2)
      ..lineTo(baseX + (tail.x < 0 ? -10 : 10), s.height)
      ..lineTo(baseX + 9, body.bottom - 2)
      ..close();
    path = Path.combine(PathOperation.union, path, tailPath);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant BubblePainter old) => old.fill != fill || old.tail != tail || old.shout != shout;
}

// --- panels --------------------------------------------------------------------------------------

/// A manga panel: white (or [fill]) inside a thick ink border, with a hard
/// offset shadow like a cut-out pasted on the page. [bevel] shades its foot
/// with screentone. [rivets] and [glint] are the pixel UI's and mean nothing
/// here; they stay so the shared screens read the same.
class PanelBox extends StatelessWidget {
  final Widget? child;
  final Color? fill;
  final Color border;
  final double borderWidth;
  final double shadow;
  final EdgeInsets padding;
  final bool pressed;
  final bool bevel;
  final bool rivets;
  final double glint;

  const PanelBox({
    super.key,
    this.child,
    this.fill,
    this.border = Mg.ink,
    this.borderWidth = 2,
    this.shadow = 3,
    this.padding = EdgeInsets.zero,
    this.pressed = false,
    this.bevel = false,
    this.rivets = false,
    this.glint = -1,
  });

  @override
  Widget build(BuildContext context) {
    final off = pressed ? 0.0 : shadow;
    final w = borderWidth + 0.5;
    Widget body = Container(
      decoration: BoxDecoration(
        color: fill ?? Mg.panel,
        border: Border.all(color: border, width: w),
        boxShadow: off <= 0 ? null : [BoxShadow(color: Mg.ink, offset: Offset(off, off))],
      ),
      padding: padding,
      child: child,
    );
    if (bevel) {
      body = Stack(children: [
        body,
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: EdgeInsets.all(w),
              child: const CustomPaint(painter: HalftonePainter(from: 0, to: 0.22, spacing: 6)),
            ),
          ),
        ),
      ]);
    }
    return Transform.translate(offset: pressed ? Offset(shadow, shadow) : Offset.zero, child: body);
  }
}

/// Paper behind a screen: the page colour, with screentone fading in at the
/// top and the foot like the margins of a printed page.
class PaperBackdrop extends StatelessWidget {
  final Widget child;
  const PaperBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Mg.paper,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: 0, left: 0, right: 0, height: 140,
            child: IgnorePointer(child: CustomPaint(painter: HalftonePainter(from: 0.16, to: 0, color: Mg.tone, spacing: 8))),
          ),
          const Positioned(
            bottom: 0, left: 0, right: 0, height: 110,
            child: IgnorePointer(child: CustomPaint(painter: HalftonePainter(from: 0, to: 0.14, color: Mg.tone, spacing: 8))),
          ),
          child,
        ],
      ),
    );
  }
}

/// A poster or still in a panel: the picture as it is (covers should stay
/// recognisable), screentone darkening its foot.
class InkCover extends StatelessWidget {
  final String url;
  final int decodeWidth;
  const InkCover({super.key, required this.url, this.decodeWidth = 300});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _NoArt();
    return Stack(fit: StackFit.expand, children: [
      CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: decodeWidth,
        placeholder: (_, __) => const InkSkeleton(),
        errorWidget: (_, __, ___) => const _NoArt(),
      ),
      const Positioned(
        left: 0, right: 0, bottom: 0, height: 28,
        child: IgnorePointer(child: CustomPaint(painter: HalftonePainter(from: 0, to: 0.5, spacing: 5))),
      ),
    ]);
  }
}

class _NoArt extends StatelessWidget {
  const _NoArt();
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Mg.panelHigh,
        child: CustomPaint(
          painter: HalftonePainter(from: 0.3, color: Mg.tone, spacing: 7),
          child: Center(child: InkIcon(InkIcons.skull, scale: 3, color: Mg.gray)),
        ),
      );
}

// --- buttons ------------------------------------------------------------------------------------

enum InkButtonKind { red, paper, ink }

/// A button cut from the page: bold condensed lettering in a heavy ink frame.
/// Held, it drops onto its shadow and tilts; let go, it slams back with a
/// burst of impact strokes round it.
class InkButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final InkButtonKind kind;
  final bool expand;
  final double fontSize;
  final bool busy;
  final Widget? leading;

  const InkButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = InkButtonKind.red,
    this.expand = false,
    this.fontSize = 10,
    this.busy = false,
    this.leading,
  });

  @override
  State<InkButton> createState() => _InkButtonState();
}

class _InkButtonState extends State<InkButton> with SingleTickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _fire() {
    final go = widget.onPressed;
    if (go == null || widget.busy) return;
    Sfx.play('click');
    if (mangaFx == MangaFx.full) _burst.forward(from: 0);
    go();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final (fill, fg) = switch (widget.kind) {
      InkButtonKind.red => (Mg.red, Mg.white),
      InkButtonKind.paper => (Mg.panel, Mg.ink),
      InkButtonKind.ink => (Mg.ink, Mg.white),
    };
    final color = enabled || widget.busy ? fg : Mg.grayLight;
    final face = PanelBox(
      fill: enabled || widget.busy ? fill : Mg.panelHigh,
      shadow: 3,
      pressed: _down,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8 + widget.fontSize * 0.2),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 8)],
          if (widget.icon != null && !widget.busy) ...[
            Icon(widget.icon, size: widget.fontSize * 2, color: color),
            const SizedBox(width: 6),
          ],
          if (widget.busy) ...[
            SizedBox(width: widget.fontSize * 1.8, height: widget.fontSize * 1.8, child: InkSpinner(color: fg)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(widget.label.toUpperCase(),
                overflow: TextOverflow.ellipsis, style: MgFont.label(widget.fontSize, color: color, height: 1.1)),
          ),
        ],
      ),
    );
    final landing = AnimatedBuilder(
      animation: _burst,
      builder: (_, child) {
        final t = _burst.value;
        if (t == 0 || t == 1) return child!;
        return CustomPaint(
          foregroundPainter: _BurstPainter(t),
          child: Transform.scale(scale: 1 + 0.08 * math.sin(t * math.pi), child: child),
        );
      },
      child: face,
    );
    return InkFocus(
      onActivate: enabled ? _fire : null,
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        label: widget.label,
        onTap: enabled ? _fire : null,
        excludeSemantics: true,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: () => setState(() => _down = false),
          onTap: enabled ? _fire : null,
          child: AnimatedRotation(turns: _down ? -0.006 : 0, duration: const Duration(milliseconds: 60), child: landing),
        ),
      ),
    );
  }
}

/// Short black strokes flying out from a button's edge as it lands.
class _BurstPainter extends CustomPainter {
  final double t;
  const _BurstPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = Mg.ink.withValues(alpha: 1 - t)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * 2 * math.pi + 0.2;
      final dir = Offset(math.cos(a), math.sin(a));
      final edge = Offset(dir.dx * size.width / 2, dir.dy * size.height / 2);
      final from = c + edge + dir * (6 + 14 * t);
      canvas.drawLine(from, from + dir * (8 * (1 - t) + 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

/// An icon on its own, optionally in a small panel ([framed]).
class InkIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double scale;
  final Color color;
  final bool framed;
  final double size;

  const InkIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.scale = 2.2,
    this.color = Mg.ink,
    this.framed = false,
    this.size = 48,
  });

  @override
  State<InkIconButton> createState() => _InkIconButtonState();
}

class _InkIconButtonState extends State<InkIconButton> {
  bool _down = false;

  void _fire() {
    if (widget.onPressed == null) return;
    Sfx.play('click');
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(widget.icon, size: widget.scale * 10, color: widget.color);
    final face = widget.framed
        ? PanelBox(fill: Mg.panel, shadow: 2, pressed: _down, padding: const EdgeInsets.all(6), child: icon)
        : AnimatedScale(scale: _down ? 0.82 : 1, duration: const Duration(milliseconds: 70), child: icon);
    return InkFocus(
      onActivate: widget.onPressed == null ? null : _fire,
      child: Tooltip(
        message: widget.tooltip,
        child: Semantics(
          container: true,
          button: true,
          label: widget.tooltip,
          onTap: widget.onPressed == null ? null : _fire,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            onTap: _fire,
            child: SizedBox(width: widget.size, height: widget.size, child: Center(child: face)),
          ),
        ),
      ),
    );
  }
}

/// A small tag: condensed caps in an ink outline.
class InkChip extends StatelessWidget {
  final String text;
  final Color? fill;
  final Color color;
  final double fontSize;

  const InkChip(this.text, {super.key, this.fill, this.color = Mg.ink, this.fontSize = 7});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
        decoration: BoxDecoration(color: fill ?? Mg.panel, border: Border.all(color: Mg.ink, width: 1.5)),
        child: Text(text.toUpperCase(), style: MgFont.label(fontSize, color: color, height: 1.1)),
      );
}

/// A progress bar: red ink filling an outlined strip, screentone in the rest.
class InkBar extends StatelessWidget {
  final double fraction;
  final double height;
  const InkBar({super.key, required this.fraction, this.height = 8});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Mg.panel, border: Border.all(color: Mg.ink, width: 1.5)),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth * fraction.clamp(0.0, 1.0);
            return Stack(children: [
              const Positioned.fill(child: CustomPaint(painter: HalftonePainter(from: 0.25, color: Mg.tone, spacing: 4))),
              Positioned(left: 0, top: 0, bottom: 0, width: w, child: const ColoredBox(color: Mg.red)),
            ]);
          }),
        ),
      );
}

/// A loading placeholder: screentone sliding across a grey panel.
class InkSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  const InkSkeleton({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: Mg.panelHigh,
          child: MangaClock(
            fps: 10,
            builder: (_, f) =>
                CustomPaint(painter: HalftonePainter(from: 0.32, color: Mg.tone, spacing: 8, shift: f * 1.5)),
          ),
        ),
      );
}

/// A brush circle (ensō) drawing itself round and round.
class InkSpinner extends StatefulWidget {
  final Color color;
  const InkSpinner({super.key, this.color = Mg.ink});

  @override
  State<InkSpinner> createState() => _InkSpinnerState();
}

class _InkSpinnerState extends State<InkSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (mangaFx != MangaFx.off) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: EnsoPainter(_c.value, widget.color)));
}

/// One stroke of an ensō: thick where the brush lands, thinning as it runs
/// dry, its start turning with [t].
class EnsoPainter extends CustomPainter {
  final double t;
  final Color color;
  const EnsoPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final start = t * 2 * math.pi;
    final sweep = 1.2 * math.pi + 0.5 * math.pi * math.sin(t * 2 * math.pi);
    const n = 28;
    final p = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final a = start + sweep * i / n;
      final w = r * 0.28 * (1 - i / n) + r * 0.06;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (r - w / 2), w / 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant EnsoPainter old) => old.t != t || old.color != color;
}

// --- motion -------------------------------------------------------------------------------------

/// Presses a panel into the page while held (it drops onto its shadow and
/// tilts a hair).
class InkPress extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const InkPress({super.key, required this.child, required this.onTap, this.focusNode});

  @override
  State<InkPress> createState() => _InkPressState();
}

class _InkPressState extends State<InkPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => InkFocus(
        onActivate: widget.onTap,
        focusNode: widget.focusNode,
        child: Semantics(
          container: true,
          button: true,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              transform: _down ? (Matrix4.translationValues(2, 2, 0)..rotateZ(-0.012)) : Matrix4.identity(),
              transformAlignment: Alignment.center,
              child: widget.child,
            ),
          ),
        ),
      );
}

/// Sound-effect lettering (ドン, ゴゴゴ): heavy kana in a white outline and an
/// ink one outside it, tilted. With [pop] it slams in -- huge, then settling
/// with a wobble -- after [delay].
class SfxText extends StatefulWidget {
  final String text;
  final double size;
  final Color color;
  final double angle;
  final bool pop;
  final Duration delay;

  const SfxText(this.text,
      {super.key, this.size = 40, this.color = Mg.ink, this.angle = -0.12, this.pop = true, this.delay = Duration.zero});

  @override
  State<SfxText> createState() => _SfxTextState();
}

class _SfxTextState extends State<SfxText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    if (!widget.pop || mangaFx == MangaFx.off) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final white = widget.color == Mg.white;
    final letters = Text(
      widget.text,
      style: MgFont.sfx(s, color: widget.color).copyWith(shadows: [
        ...MgFont.outline(s / 16, color: white ? Mg.ink : Mg.white),
        ...MgFont.outline(s / 9, color: white ? Mg.white : Mg.ink),
      ]),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.elasticOut.transform(_c.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: (_c.value * 4).clamp(0.0, 1.0),
          child: Transform.rotate(
              angle: widget.angle * (2 - t), child: Transform.scale(scale: 2.2 - 1.2 * t, child: child)),
        );
      },
      child: letters,
    );
  }
}

/// A speech bubble round [child]. [shout] draws a jagged burst instead.
class SpeechBubble extends StatelessWidget {
  final Widget child;
  final Alignment tail;
  final Color fill;
  final bool shout;
  final EdgeInsets padding;

  const SpeechBubble(
      {super.key,
      required this.child,
      this.tail = Alignment.bottomLeft,
      this.fill = Mg.panel,
      this.shout = false,
      this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 22)});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: BubblePainter(fill: fill, tail: tail, shout: shout),
        child: Padding(padding: shout ? padding * 1.6 : padding, child: child),
      );
}

/// Shakes [child] for a moment whenever [trigger] changes: the panel jolting
/// on an impact.
class ImpactShake extends StatefulWidget {
  final Widget child;
  final Object? trigger;
  final double strength;
  const ImpactShake({super.key, required this.child, this.trigger, this.strength = 6});

  @override
  State<ImpactShake> createState() => _ImpactShakeState();
}

class _ImpactShakeState extends State<ImpactShake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void didUpdateWidget(covariant ImpactShake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && mangaFx == MangaFx.full) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          if (t == 0 || t == 1) return child!;
          final k = widget.strength * (1 - t);
          final f = (t * 14).floor();
          return Transform.translate(offset: Offset(wobble(f, k), wobble(f + 31, k)), child: child);
        },
        child: widget.child,
      );
}

// --- page turns ---------------------------------------------------------------------------------

/// Screens change like turning a page: the new page sweeps in from the right
/// along a slanted fold, a line of ink on the fold and screentone shading the
/// page underneath. Back turns it the other way.
class PageTurnRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  PageTurnRoute({required this.page, bool backdrop = true})
      : super(
          transitionDuration: const Duration(milliseconds: 360),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (_, __, ___) => backdrop ? PaperBackdrop(child: page) : page,
          transitionsBuilder: (context, animation, secondary, child) {
            if ((MediaQuery.maybeDisableAnimationsOf(context) ?? false) || mangaFx == MangaFx.off) return child;
            final t = Curves.easeInOutCubic.transform(animation.value);
            if (t >= 1) return child;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                ClipPath(clipper: _FoldClipper(t), child: child),
                Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FoldPainter(t)))),
              ],
            );
          },
        ) {
    Sfx.play('page');
  }
}

/// Where the fold is: off the right edge at t = 0, past the left one at 1.
(Offset, Offset) _fold(Size s, double t) {
  final slant = s.width * 0.35;
  final x = s.width + slant - t * (s.width + 2 * slant);
  return (Offset(x + slant, 0), Offset(x, s.height));
}

class _FoldClipper extends CustomClipper<Path> {
  final double t;
  _FoldClipper(this.t);

  @override
  Path getClip(Size size) {
    final (top, bottom) = _fold(size, t);
    final far = size.width * 2;
    return Path()
      ..moveTo(top.dx, 0)
      ..lineTo(far, 0)
      ..lineTo(far, size.height)
      ..lineTo(bottom.dx, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _FoldClipper old) => old.t != t;
}

class _FoldPainter extends CustomPainter {
  final double t;
  _FoldPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final (top, bottom) = _fold(size, t);
    // Screentone on the old page, just short of the fold: its shadow.
    canvas.save();
    canvas.clipPath(Path()
      ..moveTo(top.dx - 46, 0)
      ..lineTo(top.dx, 0)
      ..lineTo(bottom.dx, size.height)
      ..lineTo(bottom.dx - 46, size.height)
      ..close());
    const HalftonePainter(from: 0.45, spacing: 6).paint(canvas, size);
    canvas.restore();
    canvas.drawLine(top, bottom, Paint()
      ..color = Mg.ink
      ..strokeWidth = 4);
  }

  @override
  bool shouldRepaint(covariant _FoldPainter old) => old.t != t;
}

// --- focus (TV remotes, keyboards) ------------------------------------------------------------

/// Makes a control reachable with arrow keys and Select, and rings it in ink
/// (black, with a red line inside) while it has focus -- only while keys are
/// in use, not after a tap.
class InkFocus extends StatefulWidget {
  final Widget child;
  final VoidCallback? onActivate;
  final bool autofocus;
  final FocusNode? focusNode;
  const InkFocus({super.key, required this.child, this.onActivate, this.autofocus = false, this.focusNode});

  @override
  State<InkFocus> createState() => _InkFocusState();
}

class _InkFocusState extends State<InkFocus> {
  bool _focused = false;

  // True from a navigation key until the next touch: Android marks the Google
  // TV phone remote (and adb) as a virtual keyboard, which Flutter's own
  // highlight mode ignores.
  static final ValueNotifier<bool> _keyNav = ValueNotifier<bool>(false);
  static bool _listening = false;
  static final _navKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.tab, LogicalKeyboardKey.select,
  };

  static void _listen() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler((e) {
      if (e is KeyDownEvent && _navKeys.contains(e.logicalKey)) _keyNav.value = true;
      return false;
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent) _keyNav.value = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final go = widget.onActivate;
    return FocusableActionDetector(
      enabled: go != null,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          go?.call();
          return null;
        }),
      },
      onFocusChange: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _keyNav,
        builder: (context, keys, child) {
          final ring = _focused && (keys || FocusManager.instance.highlightMode == FocusHighlightMode.traditional);
          return CustomPaint(foregroundPainter: ring ? const _InkRingPainter() : null, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

class _InkRingPainter extends CustomPainter {
  const _InkRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(2);
    canvas.drawRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Mg.ink);
    canvas.drawRect(r.deflate(3), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Mg.red);
  }

  @override
  bool shouldRepaint(covariant _InkRingPainter oldDelegate) => false;
}
