import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blood.dart';
import 'fx.dart';
import 'pixel.dart';
import 'theme_fx.dart';

/// Rectangle with its corners stepped in by one cell -- the shape of a pixel
/// art panel -- usable anywhere Material takes a shape (dialogs, snack bars,
/// buttons, input fields).
class PixelBorder extends OutlinedBorder {
  /// Size of the corner step, in logical pixels.
  final double step;

  const PixelBorder({super.side = const BorderSide(color: Px.black, width: 2), this.step = 3});

  static Path notched(Rect r, double n) {
    if (n <= 0) return Path()..addRect(r);
    return Path()
      ..moveTo(r.left + n, r.top)
      ..lineTo(r.right - n, r.top)
      ..lineTo(r.right - n, r.top + n)
      ..lineTo(r.right, r.top + n)
      ..lineTo(r.right, r.bottom - n)
      ..lineTo(r.right - n, r.bottom - n)
      ..lineTo(r.right - n, r.bottom)
      ..lineTo(r.left + n, r.bottom)
      ..lineTo(r.left + n, r.bottom - n)
      ..lineTo(r.left, r.bottom - n)
      ..lineTo(r.left, r.top + n)
      ..lineTo(r.left + n, r.top + n)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      notched(rect.deflate(side.width), step);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => notched(rect, step);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final ring = Path.combine(
      PathOperation.difference,
      notched(rect, step),
      notched(rect.deflate(side.width), step),
    );
    canvas.drawPath(ring, Paint()
      ..color = side.color
      ..isAntiAlias = false);
  }

  @override
  ShapeBorder scale(double t) =>
      PixelBorder(side: side.scale(t), step: step * t);

  @override
  PixelBorder copyWith({BorderSide? side, double? step}) =>
      PixelBorder(side: side ?? this.side, step: step ?? this.step);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is PixelBorder
      ? PixelBorder(
          side: BorderSide.lerp(a.side, side, t),
          step: lerpDouble(a.step, step, t)!,
        )
      : super.lerpFrom(a, t);
}

class _BoxPainter extends CustomPainter {
  final Color fill;
  final Color border;
  final double bw;
  final double shadow;
  final bool pressed;
  final bool bevel;

  _BoxPainter({
    required this.fill,
    required this.border,
    required this.bw,
    required this.shadow,
    required this.pressed,
    required this.bevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final face = Rect.fromLTWH(0, 0, size.width - shadow, size.height - shadow)
        .shift(pressed ? Offset(shadow, shadow) : Offset.zero);
    if (shadow > 0 && !pressed) {
      canvas.drawPath(
        PixelBorder.notched(face.shift(Offset(shadow, shadow)), bw),
        p..color = Px.black,
      );
    }
    canvas.drawPath(PixelBorder.notched(face, bw), p..color = border);
    final inner = face.deflate(bw);
    canvas.drawRect(inner, p..color = fill);
    if (bevel) {
      // One-cell bevel: a light edge top-left, a dark edge bottom-right. The
      // cheapest way to make a flat panel read as a raised 2D button.
      final c = bw;
      canvas.drawRect(Rect.fromLTWH(inner.left, inner.top, inner.width, c),
          p..color = Color.lerp(fill, Colors.white, 0.28)!);
      canvas.drawRect(Rect.fromLTWH(inner.left, inner.top, c, inner.height),
          p..color = Color.lerp(fill, Colors.white, 0.18)!);
      canvas.drawRect(Rect.fromLTWH(inner.left, inner.bottom - c, inner.width, c),
          p..color = Color.lerp(fill, Colors.black, 0.35)!);
      canvas.drawRect(Rect.fromLTWH(inner.right - c, inner.top, c, inner.height),
          p..color = Color.lerp(fill, Colors.black, 0.25)!);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter o) =>
      o.fill != fill || o.border != border || o.bw != bw ||
      o.shadow != shadow || o.pressed != pressed || o.bevel != bevel;
}

/// What goes over a panel's contents: corner rivets and the glint band. A
/// cover image filling the panel would hide them if they were painted under it.
class _FacePainter extends CustomPainter {
  final double bw;
  final double shadow;
  final bool pressed;
  final bool rivets;
  final double glint;

  _FacePainter({required this.bw, required this.shadow, required this.pressed,
      required this.rivets, required this.glint});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final inner = Rect.fromLTWH(0, 0, size.width - shadow, size.height - shadow)
        .shift(pressed ? Offset(shadow, shadow) : Offset.zero)
        .deflate(bw);
    if (rivets && inner.width > 24 && inner.height > 24) {
      // A pixel stud in each corner, lit on its top-left cell.
      const r = 3.0, inset = 4.0;
      for (final (dx, dy) in [
        (inner.left + inset, inner.top + inset),
        (inner.right - inset - r, inner.top + inset),
        (inner.left + inset, inner.bottom - inset - r),
        (inner.right - inset - r, inner.bottom - inset - r),
      ]) {
        canvas.drawRect(Rect.fromLTWH(dx - 1, dy - 1, r + 2, r + 2), p..color = Px.black);
        canvas.drawRect(Rect.fromLTWH(dx, dy, r, r), p..color = Px.ashDark);
        canvas.drawRect(Rect.fromLTWH(dx, dy, 1, 1), p..color = Px.bone);
      }
    }
    if (glint >= 0) {
      canvas.save();
      canvas.translate(inner.left, inner.top);
      GlintPainter(glint).paint(canvas, inner.size);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FacePainter o) =>
      o.bw != bw || o.shadow != shadow || o.pressed != pressed || o.rivets != rivets || o.glint != glint;
}

/// A pixel-art panel: stepped corners, a hard border, and a drop shadow with
/// no blur, offset down-right like every panel in a 16-bit game.
class PixelBox extends StatelessWidget {
  final Widget? child;

  /// The face colour; the palette's panel colour when null.
  final Color? fill;
  final Color border;
  final double borderWidth;
  final double shadow;
  final EdgeInsets padding;
  final bool pressed;
  final bool bevel;

  /// Corner studs, for the bigger panels.
  final bool rivets;

  /// A light band crossing the face at 0..1; below 0, none.
  final double glint;

  const PixelBox({
    super.key,
    this.child,
    this.fill,
    this.border = Px.black,
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
    final b = borderWidth;
    final press = pressed ? Offset(shadow, shadow) : Offset.zero;
    return CustomPaint(
      painter: _BoxPainter(
        fill: fill ?? Px.panel,
        border: border,
        bw: b,
        shadow: shadow,
        pressed: pressed,
        bevel: bevel,
      ),
      foregroundPainter: rivets || glint >= 0
          ? _FacePainter(bw: b, shadow: shadow, pressed: pressed, rivets: rivets, glint: glint)
          : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          b + padding.left + press.dx,
          b + padding.top + press.dy,
          b + padding.right + shadow - press.dx,
          b + padding.bottom + shadow - press.dy,
        ),
        child: child,
      ),
    );
  }
}

enum PixelButtonKind { blood, dark, bone }

/// A 2D game button. Pressing drops the face onto its shadow; a blood button
/// also bursts a small blood splat where it was hit.
class PixelButton extends StatefulWidget {
  final String label;
  final Sprite? icon;
  final VoidCallback? onPressed;
  final PixelButtonKind kind;
  final bool expand;
  final double fontSize;
  final bool busy;
  final Widget? leading;

  const PixelButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = PixelButtonKind.blood,
    this.expand = false,
    this.fontSize = 10,
    this.busy = false,
    this.leading,
  });

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  Widget _face(Color fill, Widget content, double glint) => PixelBox(
        fill: fill,
        pressed: _down,
        bevel: true,
        glint: glint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Center(widthFactor: 1, heightFactor: 1, child: content),
      );

  @override
  Widget build(BuildContext context) => PixelFocus(onActivate: _enabled ? () => widget.onPressed!() : null, child: _faceBuild(context));

  Widget _faceBuild(BuildContext context) {
    final (fill, text) = switch (widget.kind) {
      PixelButtonKind.blood => (Px.blood, Px.bone),
      PixelButtonKind.dark => (Px.panelHigh, Px.bone),
      PixelButtonKind.bone => (Px.bone, Px.black),
    };
    final faceFill = _enabled ? fill : Px.ashDark;
    final faceText = _enabled ? text : Px.ash;

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          PixelSpinner(color: faceText)
        else ...[
          if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 10)],
          if (widget.icon != null) ...[
            PixelSprite(widget.icon!, scale: widget.fontSize / 5, color: faceText),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              widget.label.toUpperCase(),
              textAlign: TextAlign.center,
              style: PxFont.label(widget.fontSize, color: faceText, height: 1.6),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true, // its own node: a screen reader can focus and press it
      button: true,
      enabled: _enabled,
      label: widget.label,
      // The gesture below is hidden from screen readers, so the tap is offered here.
      onTap: _enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: _enabled ? () => setState(() => _down = false) : null,
        onTapUp: _enabled
            ? (d) {
                setState(() => _down = false);
                if (widget.kind == PixelButtonKind.blood) {
                  BloodSplat.show(context, d.globalPosition);
                }
                widget.onPressed!();
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: _enabled && widget.kind == PixelButtonKind.blood && fxLevel != FxLevel.off
              // A light band sweeps the face every few seconds; buttons start
              // at different points of the loop so they do not flash together.
              ? FrameClock(
                  fps: 12,
                  frames: 72,
                  builder: (_, f) => _face(faceFill, content, glintAt(f + widget.label.length * 7, frames: 72)),
                )
              : _face(faceFill, content, -1),
        ),
      ),
    );
  }
}

/// Square icon button with a sprite, for app bars and the player.
class PixelIconButton extends StatefulWidget {
  final Sprite sprite;
  final VoidCallback? onPressed;
  final String tooltip;
  final double scale;
  final Color color;
  final bool framed;

  /// Tap target edge; 48 meets Material's minimum, the player's compact HUD
  /// goes smaller where space is tight.
  final double size;

  const PixelIconButton({
    super.key,
    required this.sprite,
    required this.onPressed,
    required this.tooltip,
    this.scale = 2.2,
    this.color = Px.bone,
    this.framed = false,
    this.size = 48,
  });

  @override
  State<PixelIconButton> createState() => _PixelIconButtonState();
}

class _PixelIconButtonState extends State<PixelIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => PixelFocus(onActivate: widget.onPressed, child: _faceBuild(context));

  Widget _faceBuild(BuildContext context) {
    final icon = PixelSprite(widget.sprite, scale: widget.scale, color: widget.color);
    return Semantics(
      container: true, // its own node: a screen reader can focus and press it
      button: true,
      label: widget.tooltip,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onPressed?.call();
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: widget.framed
                ? PixelBox(
                    fill: Px.panelHigh,
                    pressed: _down,
                    shadow: 2,
                    padding: const EdgeInsets.all(6),
                    child: icon,
                  )
                : Transform.translate(
                    offset: _down ? const Offset(2, 2) : Offset.zero,
                    child: icon,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Small label chip: genre tags, badges.
class PixelChip extends StatelessWidget {
  final String text;

  /// The chip colour; the palette's blood colour when null.
  final Color? fill;
  final Color color;
  final double fontSize;

  const PixelChip(this.text, {super.key, this.fill, this.color = Px.bone, this.fontSize = 7});

  @override
  Widget build(BuildContext context) {
    return PixelBox(
      fill: fill ?? Px.blood,
      shadow: 2,
      borderWidth: 2,
      padding: const EdgeInsets.fromLTRB(5, 4, 5, 3),
      child: Text(text.toUpperCase(), style: PxFont.label(fontSize, color: color, height: 1.2)),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double fraction;
  _BarPainter(this.fraction);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final c = (size.height / 4).clamp(1.0, 3.0);
    canvas.drawRect(Offset.zero & size, p..color = Px.black);
    final inner = Rect.fromLTWH(c, c, size.width - 2 * c, size.height - 2 * c);
    canvas.drawRect(inner, p..color = Px.bloodDeep);
    final w = (inner.width * fraction.clamp(0.0, 1.0) / c).floor() * c;
    if (w <= 0) return;
    final fill = Rect.fromLTWH(inner.left, inner.top, w, inner.height);
    canvas.drawRect(fill, p..color = Px.blood);
    canvas.drawRect(Rect.fromLTWH(fill.left, fill.top, w, c), p..color = Px.bloodLight);
    if (inner.height > 2 * c) {
      canvas.drawRect(Rect.fromLTWH(fill.left, fill.bottom - c, w, c), p..color = Px.bloodDark);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) => o.fraction != fraction;
}

/// Progress as a game health bar: a black frame, dark trough, and a blood fill
/// with a lit top edge. Fills in whole cells.
class PixelBar extends StatelessWidget {
  final double fraction;
  final double height;

  const PixelBar({super.key, required this.fraction, this.height = 8});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(painter: _BarPainter(fraction), size: Size.infinite),
      );
}

class _DitherPainter extends CustomPainter {
  final int frame;
  _DitherPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 4.0;
    final p = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, p..color = Px.panel);
    p.color = Px.panelHigh;
    // A checkerboard band that marches across in whole cells: the stepped,
    // dithered cousin of a smooth shimmer.
    final band = (frame * 3) % ((size.width / cell).ceil() + 24) - 12;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        final inBand = (x + y ~/ 2 - band).abs() < 6;
        if (inBand ? (x + y).isEven : (x + y) % 4 == 0) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DitherPainter o) => o.frame != frame;
}

/// Loading placeholder: a dithered pixel block with a stepped shimmer.
class PixelSkeleton extends StatelessWidget {
  final double? width;
  final double? height;

  const PixelSkeleton({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: FrameClock(
        fps: 10,
        frames: 60,
        builder: (_, f) => CustomPaint(painter: _DitherPainter(f)),
      ),
    );
  }
}

/// Four-frame spinner for busy buttons: a square chasing round a 3x3 ring.
class PixelSpinner extends StatelessWidget {
  final Color color;
  const PixelSpinner({super.key, this.color = Px.bone});

  static const _ring = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)];

  @override
  Widget build(BuildContext context) {
    return FrameClock(
      fps: 12,
      frames: 8,
      builder: (_, f) => SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _SpinnerPainter(f, color)),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final int frame;
  final Color color;
  _SpinnerPainter(this.frame, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / 3);
    for (var i = 0; i < 3; i++) {
      final (x, y) = PixelSpinner._ring[(frame - i) % 8];
      pc.px(x, y, i == 0 ? color : color.withValues(alpha: 0.45 - i * 0.12));
    }
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter o) => o.frame != frame || o.color != color;
}


// --- focus, for remotes and keyboards ------------------------------------------------------

/// Makes a tappable pixel widget reachable with a D-pad or keyboard (Android
/// TV remotes, game pads, Chromebooks): it takes focus in turn, shows a hard
/// pixel ring while focused, and Enter / Select / A presses it. On a touch
/// screen nothing changes -- the ring only shows in keyboard navigation.
class PixelFocus extends StatefulWidget {
  final Widget child;
  final VoidCallback? onActivate;
  final bool autofocus;

  /// For a parent that moves focus itself (a poster row remembering its place).
  final FocusNode? focusNode;
  const PixelFocus({super.key, required this.child, this.onActivate, this.autofocus = false, this.focusNode});

  @override
  State<PixelFocus> createState() => _PixelFocusState();
}

class _PixelFocusState extends State<PixelFocus> {
  bool _focused = false;

  /// True from a navigation key until the next touch. Flutter's own highlight
  /// mode ignores key events that Android marks as coming from a virtual
  /// keyboard -- and that is how the Google TV phone remote, and adb, send
  /// them -- so the ring would never show for those.
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
          return CustomPaint(foregroundPainter: ring ? const _FocusRingPainter() : null, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..isAntiAlias = false
      ..color = Px.bloodLight;
    // Just inside the control's edges: rows that clip their children (the
    // poster rows) would cut off a ring drawn outside them.
    const w = 2.0;
    final r = Offset.zero & size;
    // Four bars with the corners stepped in: a pixel ring, not a rounded one.
    canvas.drawRect(Rect.fromLTWH(r.left + w, r.top, r.width - 2 * w, w), p);
    canvas.drawRect(Rect.fromLTWH(r.left + w, r.bottom - w, r.width - 2 * w, w), p);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top + w, w, r.height - 2 * w), p);
    canvas.drawRect(Rect.fromLTWH(r.right - w, r.top + w, w, r.height - 2 * w), p);
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) => false;
}
