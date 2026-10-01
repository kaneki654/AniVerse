import 'package:flutter/material.dart';

import 'pixel/fx.dart';
import 'pixel/pixel.dart';
import 'pixel/pixel_widgets.dart';
import 'pixel/sprites.dart';

/// Theme for the 2D (pixel art) UI.
///
/// Same member names as the classic theme so the screens read the same way,
/// but every value is from the pixel palette: flat colours, no gradients or
/// blur, stepped corners, pixel fonts.
class AniVerseTheme {
  static const Color red = Px.blood;
  static const Color redDark = Px.bloodDark;
  static const Color bg = Px.ink;
  static const Color surface = Px.panel;
  static const Color surfaceHigh = Px.panelHigh;
  static const Color skeleton = Px.panel;
  static const Color skeletonHigh = Px.panelHigh;
  static const Color textDim = Px.ash;
  static const Color textFaint = Px.ashDark;

  /// Poster scrim in hard bands rather than a smooth fade -- the stepped,
  /// dithered look of a 16-bit shadow.
  static const LinearGradient posterScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent, Colors.transparent,
      Color(0x66050305), Color(0x66050305),
      Color(0xB3050305), Color(0xB3050305),
    ],
    stops: [0.0, 0.5, 0.5, 0.72, 0.72, 1.0],
  );

  static ThemeData build(BuildContext context) {
    const border = PixelBorder(side: BorderSide(color: Px.black, width: 2));
    final base = ThemeData(brightness: Brightness.dark, fontFamily: PxFont.body);
    final display = base.textTheme.apply(
      fontFamily: PxFont.display,
      bodyColor: Px.bone,
      displayColor: Px.bone,
    );
    return base.copyWith(
      // Transparent: PixelBackdrop paints the ground, with embers on it, behind
      // every screen but the player (whose Scaffold is black).
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: Px.blood,
      colorScheme: const ColorScheme.dark(
        primary: Px.blood,
        onPrimary: Px.bone,
        secondary: Px.blood,
        onSecondary: Px.bone,
        surface: Px.panel,
        onSurface: Px.bone,
        error: Px.bloodLight,
      ),
      // Body copy is the dot-matrix face; anything that acts as a heading or
      // label is the 8-bit arcade face, sized down because it runs wide.
      textTheme: base.textTheme
          .apply(fontFamily: PxFont.body, bodyColor: Px.bone, displayColor: Px.bone)
          .copyWith(
            titleLarge: display.titleLarge?.copyWith(fontSize: 14),
            titleMedium: display.titleMedium?.copyWith(fontSize: 11),
            titleSmall: display.titleSmall?.copyWith(fontSize: 9),
            labelLarge: display.labelLarge?.copyWith(fontSize: 10),
            labelMedium: display.labelMedium?.copyWith(fontSize: 8),
            labelSmall: display.labelSmall?.copyWith(fontSize: 7),
          ),
      // Material's ink ripple is a smooth radial blend; a 2D UI presses
      // instead (see PixelButton).
      splashFactory: NoSplash.splashFactory,
      highlightColor: Px.blood.withValues(alpha: 0.18),
      appBarTheme: AppBarTheme(
        backgroundColor: Px.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: PxFont.label(12).copyWith(shadows: PxFont.outline(1.5)),
        iconTheme: const IconThemeData(color: Px.bone),
      ),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const PixelSprite(Sprites.back, scale: 2.2),
      ),
      iconTheme: const IconThemeData(color: Px.bone),
      dialogTheme: DialogThemeData(
        backgroundColor: Px.panel,
        surfaceTintColor: Colors.transparent,
        shape: const PixelBorder(side: BorderSide(color: Px.blood, width: 3), step: 4),
        titleTextStyle: PxFont.label(12),
        contentTextStyle: PxFont.text(15, color: Px.ash),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Px.panelHigh,
        shape: const PixelBorder(side: BorderSide(color: Px.blood, width: 2)),
        behavior: SnackBarBehavior.floating,
        contentTextStyle: PxFont.text(15),
        actionTextColor: Px.bloodLight,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Px.bone,
          textStyle: PxFont.label(10),
          shape: const PixelBorder(side: BorderSide.none),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Px.blood,
          foregroundColor: Px.bone,
          textStyle: PxFont.label(10),
          shape: border,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: PxFont.label(9),
          shape: border,
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Px.panel,
        labelStyle: PxFont.text(15, color: Px.ash),
        hintStyle: PxFont.text(15, color: Px.ashDark),
        floatingLabelStyle: PxFont.label(9, color: Px.bloodLight),
        errorStyle: PxFont.text(13, color: Px.bloodLight),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Px.black, width: 2),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Px.black, width: 2),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Px.blood, width: 3),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Px.bloodLight, width: 2),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Px.blood,
        selectionColor: Color(0x66D10A1A),
        selectionHandleColor: Px.blood,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Px.blood),
      listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder()),
      dividerTheme: const DividerThemeData(color: Px.panelHigh, thickness: 2),
      tooltipTheme: TooltipThemeData(
        decoration: const ShapeDecoration(color: Px.black, shape: PixelBorder()),
        textStyle: PxFont.label(8),
      ),
    );
  }
}

/// Section heading: a blood drop, the title in the arcade face, and an
/// optional MORE button.
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
          const PixelSprite(Sprites.bloodDrop, scale: 2.2),
          const SizedBox(width: 10),
          ConstrainedBox(
            // Room for the title first; the katana takes whatever is left.
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.62),
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PxFont.label(11).copyWith(shadows: [
                ...PxFont.outline(1.5),
                // Bloom: hard red copies a step out, no blur.
                for (final o in const [Offset(-3, 0), Offset(3, 0), Offset(0, -3), Offset(0, 3)])
                  Shadow(color: const Color(0x40D10A1A), offset: o),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: KatanaDivider()),
          const SizedBox(width: 6),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Text('MORE', style: PxFont.label(8, color: Px.bloodLight)),
                    const SizedBox(width: 6),
                    const PixelSprite(Sprites.chevron, scale: 1.2, color: Px.bloodLight),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
