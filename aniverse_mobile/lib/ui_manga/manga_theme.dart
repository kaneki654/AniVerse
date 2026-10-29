import 'package:flutter/material.dart';

import 'ink/manga.dart';

/// Theme for the manga UI: paper and ink, square panels with thick borders,
/// condensed lettering. Same member names as the other UIs' themes so the
/// screens read the same way.
class MangaTheme {
  static Color get red => Mg.red;
  static Color get redDark => Mg.redDark;
  static Color get bg => Mg.paper;
  static Color get surface => Mg.panel;
  static Color get surfaceHigh => Mg.panelHigh;
  static Color get skeleton => Mg.panelHigh;
  static Color get skeletonHigh => Mg.tone;
  static Color get textDim => Mg.gray;
  static Color get textFaint => Mg.grayLight;

  /// Poster scrim: ink deepening toward the foot, for lettering over art.
  static const LinearGradient posterScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0x55121010), Color(0xCC121010)],
    stops: [0.45, 0.7, 1.0],
  );

  static const _square = RoundedRectangleBorder(side: BorderSide(color: Mg.ink, width: 2.5));

  static ThemeData build(BuildContext context) {
    final base = ThemeData(brightness: Brightness.light, fontFamily: MgFont.body);
    return base.copyWith(
      // Transparent: PaperBackdrop paints the page behind every screen but the
      // player (whose Scaffold is black).
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: Mg.red,
      colorScheme: const ColorScheme.light(
        primary: Mg.red,
        onPrimary: Mg.white,
        secondary: Mg.ink,
        onSecondary: Mg.white,
        surface: Mg.panel,
        onSurface: Mg.ink,
        error: Mg.red,
      ),
      textTheme: base.textTheme.apply(fontFamily: MgFont.body, bodyColor: Mg.ink, displayColor: Mg.ink).copyWith(
            titleLarge: MgFont.heading(22),
            titleMedium: MgFont.label(11),
            titleSmall: MgFont.label(9),
            labelLarge: MgFont.label(10),
            labelMedium: MgFont.label(8),
            labelSmall: MgFont.label(7),
          ),
      // No ripple: panels press into the page instead (InkPress, InkButton).
      splashFactory: NoSplash.splashFactory,
      highlightColor: Mg.red.withValues(alpha: 0.12),
      appBarTheme: AppBarTheme(
        backgroundColor: Mg.paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Mg.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: MgFont.heading(20),
        iconTheme: const IconThemeData(color: Mg.ink),
        shape: const Border(bottom: BorderSide(color: Mg.ink, width: 3)),
      ),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const InkIcon(InkIcons.back, scale: 2.4),
      ),
      iconTheme: const IconThemeData(color: Mg.ink),
      dialogTheme: DialogThemeData(
        backgroundColor: Mg.panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Mg.ink, width: 3)),
        titleTextStyle: MgFont.heading(20),
        contentTextStyle: MgFont.text(15, color: Mg.gray),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Mg.panel,
        shape: _square,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: MgFont.text(15),
        actionTextColor: Mg.red,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Mg.ink,
          textStyle: MgFont.label(10),
          shape: const RoundedRectangleBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Mg.red,
          foregroundColor: Mg.white,
          textStyle: MgFont.label(10),
          shape: _square,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(textStyle: MgFont.label(9), shape: _square, elevation: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Mg.panel,
        labelStyle: MgFont.text(15, color: Mg.gray),
        hintStyle: MgFont.text(15, color: Mg.grayLight),
        floatingLabelStyle: MgFont.label(9, color: Mg.red),
        errorStyle: MgFont.text(13, color: Mg.red),
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Mg.ink, width: 2.5)),
        enabledBorder:
            const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Mg.ink, width: 2.5)),
        focusedBorder:
            const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Mg.red, width: 3)),
        errorBorder:
            const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Mg.red, width: 2.5)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Mg.red,
        selectionColor: Mg.red.withValues(alpha: 0.3),
        selectionHandleColor: Mg.red,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Mg.red),
      listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder()),
      dividerTheme: const DividerThemeData(color: Mg.ink, thickness: 2),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(color: Mg.ink),
        textStyle: MgFont.label(8, color: Mg.white),
      ),
    );
  }
}

/// Section heading: the title in a black caption box (white lettering, like
/// a narration box), a red brush stroke trailing off to the right, and an
/// optional MORE.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;

  const SectionHeader({super.key, required this.title, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.66),
            child: Transform(
              transform: Matrix4.skewX(-0.12),
              child: Container(
                color: Mg.ink,
                padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MgFont.heading(17, color: Mg.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: SizedBox(height: 14, child: CustomPaint(painter: _BrushStroke()))),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(children: [
                  Text('MORE', style: MgFont.label(8, color: Mg.red)),
                  const InkIcon(InkIcons.chevron, scale: 1.5, color: Mg.red),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// A dry red brush stroke: thick at the start, splitting into bristle lines
/// as it runs out.
class _BrushStroke extends CustomPainter {
  const _BrushStroke();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Mg.red;
    final h = size.height;
    final w = size.width;
    canvas.drawPath(
        Path()
          ..moveTo(0, h * 0.2)
          ..lineTo(w * 0.55, h * 0.4)
          ..lineTo(w * 0.62, h * 0.55)
          ..lineTo(0, h * 0.85)
          ..close(),
        p);
    p.strokeWidth = 1.2;
    for (var i = 0; i < 5; i++) {
      final y = h * (0.32 + i * 0.1);
      final end = w * (0.7 + 0.06 * ((i * 7) % 5));
      canvas.drawLine(Offset(w * 0.4, y), Offset(end, y + (i - 2) * 0.6), p);
    }
  }

  @override
  bool shouldRepaint(covariant _BrushStroke oldDelegate) => false;
}
