import 'package:flutter/material.dart';

import '../../app_version.dart';
import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../../services/download_service.dart';
import '../../services/native_bridge.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../theme_2d.dart';
import '../intro/logo_intro.dart';
import '../intro/palette_transition.dart';
import '../widgets/pixel_extras.dart';

/// Settings: the server, the palette, sound, data saver, subtitles, the
/// player's background behaviour and new-episode alerts. The website has the
/// same choices on its Settings page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pip = false;

  static const _langs = ['', 'English', 'Spanish', 'Portuguese', 'French', 'German', 'Italian', 'Arabic', 'Russian', 'Indonesian'];

  @override
  void initState() {
    super.initState();
    NativeBridge.pipSupported().then((v) {
      if (mounted) setState(() => _pip = v);
    });
  }

  Future<void> _set(String key, Object value) async {
    await AppSettings.set(key, value);
    if (mounted) setState(() {});
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: ApiService.host);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SERVER ADDRESS'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://xxxx.trycloudflare.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('SAVE')),
        ],
      ),
    );
    if (saved == null || saved.trim().isEmpty) return;
    await ApiService.setHost(saved);
    if (mounted) setState(() {});
  }

  Future<void> _toggleAlerts(bool on) async {
    if (on && !await NativeBridge.requestNotifications()) {
      if (mounted) pixelToast(context, 'Notifications are off for AniVerse. Turn them on in Android settings.');
      return;
    }
    await _set('alerts', on);
    await NativeBridge.scheduleAlerts(on);
    if (on && mounted) pixelToast(context, "You'll get a notification when a show on My List airs a new episode.");
  }

  @override
  Widget build(BuildContext context) {
    const sizes = [('s', 'Small'), ('m', 'Medium'), ('l', 'Large'), ('xl', 'Extra large')];
    const subColors = [('white', 'White'), ('yellow', 'Yellow'), ('cyan', 'Cyan'), ('green', 'Green')];
    const textSizes = [(1.0, 'Normal'), (1.15, 'Large'), (1.3, 'Largest')];
    const volumes = [(0.15, 'Quiet'), (0.35, 'Normal'), (0.7, 'Loud')];
    String labelOf<T>(List<(T, String)> opts, T v) => opts.firstWhere((o) => o.$1 == v, orElse: () => opts[1]).$2;

    return Scaffold(
      appBar: AppBar(title: const Text('SETTINGS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionHeader(title: 'Server'),
          SettingRow(
            title: 'Server address',
            text: ApiService.host,
            onTap: _editServer,
            control: const PixelSprite(Sprites.chevron, scale: 1.6, color: Px.ash),
          ),
          const SizedBox(height: 12),
          const SectionHeader(title: 'Palette'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final MapEntry(key: id, value: name) in Px.themes.entries)
                GestureDetector(
                  // Each palette arrives with its own transition.
                  onTap: () => PaletteTransition.go(id),
                  child: PixelBox(
                    fill: Px.panelHigh,
                    border: AppSettings.theme.value == id ? Px.bloodLight : Px.black,
                    borderWidth: AppSettings.theme.value == id ? 3 : 2,
                    padding: const EdgeInsets.fromLTRB(10, 9, 12, 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 14, height: 14, child: ColoredBox(color: Px.swatch(id))),
                      const SizedBox(width: 8),
                      Text(name.toUpperCase(), style: PxFont.label(7, height: 1.3)),
                    ]),
                  ),
                ),
            ],
          ),
          SettingRow(
            title: 'Effects',
            text: 'The animation in the background, on taps and on buttons. Lite saves battery; Off keeps the screens still.',
            control: ChoiceChipButton(
              label: switch (AppSettings.effects) { 'lite' => 'Lite', 'off' => 'Off', _ => 'Full' },
              onTap: () async {
                final v = await pickOption(context, 'Effects', const [('full', 'Full'), ('lite', 'Lite'), ('off', 'Off')], AppSettings.effects);
                if (v == null) return;
                // The app rebuilds in the new level, the way a palette change does.
                await _set('effects', v);
              },
            ),
          ),
          SettingRow(
            title: 'Intro animation',
            text: 'The pixel-art logo intro when the app opens. Tap it to skip.',
            control: PixelSwitch(label: 'Intro animation', value: AppSettings.intro, onChanged: (v) => _set('intro', v)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: PixelButton(
              label: 'Replay intro',
              icon: Sprites.play,
              kind: PixelButtonKind.dark,
              fontSize: 8,
              onPressed: () => Navigator.of(context).push(PageRouteBuilder(
                opaque: true,
                pageBuilder: (ctx, _, __) => LogoIntro(onDone: () => Navigator.of(ctx).pop()),
              )),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader(title: 'Sound'),
          SettingRow(
            title: 'Sound effects',
            text: '8-bit blips for buttons, hits and achievements.',
            control: PixelSwitch(label: 'Sound effects', value: AppSettings.sfx, onChanged: (v) => _set('sfx', v)),
          ),
          SettingRow(
            title: 'Effects volume',
            text: 'How loud the blips are.',
            control: ChoiceChipButton(
              label: labelOf(volumes, AppSettings.volume),
              onTap: () async {
                final v = await pickOption(context, 'Effects volume', volumes, AppSettings.volume);
                if (v != null) {
                  await _set('volume', v);
                  Sfx.play('select');
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          const SectionHeader(title: 'Watching'),
          SettingRow(
            title: 'Data saver',
            text: 'Always play and download the lowest quality.',
            control: PixelSwitch(label: 'Data saver', value: AppSettings.dataSaver, onChanged: (v) => _set('dataSaver', v)),
          ),
          if (_pip)
            SettingRow(
              title: 'Picture in picture',
              text: 'Leaving the app while a video plays shrinks it into a floating window.',
              control: PixelSwitch(label: 'Picture in picture', value: AppSettings.pipAuto, onChanged: (v) => _set('pipAuto', v)),
            ),
          SettingRow(
            title: 'Background audio',
            text: 'Keep the sound playing with the screen off or the app in the background.',
            control: PixelSwitch(label: 'Background audio', value: AppSettings.bgAudio, onChanged: (v) => _set('bgAudio', v)),
          ),
          SettingRow(
            title: 'Skip length',
            text: 'How far the skip buttons, a double-tap and the remote jump.',
            control: ChoiceChipButton(
              label: '${AppSettings.seekStep} seconds',
              onTap: () async {
                final v = await pickOption(context, 'Skip length',
                    const [(5.0, '5 seconds'), (10.0, '10 seconds'), (15.0, '15 seconds'), (30.0, '30 seconds')],
                    AppSettings.seekStep.toDouble());
                if (v != null) _set('seekStep', v);
              },
            ),
          ),
          SettingRow(
            title: 'Skip recaps',
            text: 'Jump past the "previously on" at the start of an episode by itself, when it is known.',
            control: PixelSwitch(label: 'Skip recaps', value: AppSettings.skipRecap, onChanged: (v) => _set('skipRecap', v)),
          ),
          SettingRow(
            title: 'Subtitle colour',
            text: 'The colour subtitles are drawn in.',
            control: ChoiceChipButton(
              label: labelOf(subColors, AppSettings.subColor),
              onTap: () async {
                final v = await pickOption(context, 'Subtitle colour', subColors, AppSettings.subColor);
                if (v != null) _set('subColor', v);
              },
            ),
          ),
          SettingRow(
            title: 'Subtitle size',
            text: 'How big subtitles are drawn.',
            control: ChoiceChipButton(
              label: labelOf(sizes, AppSettings.subSize),
              onTap: () async {
                final v = await pickOption(context, 'Subtitle size', sizes, AppSettings.subSize);
                if (v != null) _set('subSize', v);
              },
            ),
          ),
          SettingRow(
            title: 'Subtitle background',
            text: 'A dark box behind subtitles, for bright scenes.',
            control: PixelSwitch(label: 'Subtitle background', value: AppSettings.subBg, onChanged: (v) => _set('subBg', v)),
          ),
          SettingRow(
            title: 'Subtitle language',
            text: 'Used when a stream has more than one.',
            control: ChoiceChipButton(
              label: AppSettings.subLang.isEmpty ? 'Default' : AppSettings.subLang,
              onTap: () async {
                final v = await pickOption(context, 'Subtitle language',
                    [for (final l in _langs) (l, l.isEmpty ? 'Source default' : l)], AppSettings.subLang);
                if (v != null) _set('subLang', v);
              },
            ),
          ),
          const SizedBox(height: 10),
          const SectionHeader(title: 'Downloads'),
          SettingRow(
            title: 'Wi-Fi only',
            text: 'Wait for Wi-Fi before downloading, so it never uses mobile data.',
            control: PixelSwitch(label: 'Wi-Fi only', value: AppSettings.wifiOnly, onChanged: (v) async {
              await _set('wifiOnly', v);
              DownloadService.resume();
            }),
          ),
          SettingRow(
            title: 'Storage limit',
            text: 'The most saved episodes may take up.',
            control: ChoiceChipButton(
              label: AppSettings.downloadLimitGb == 0 ? 'No limit' : '${AppSettings.downloadLimitGb.toStringAsFixed(0)} GB',
              onTap: () async {
                final v = await pickOption(context, 'Storage limit',
                    const [(0.0, 'No limit'), (2.0, '2 GB'), (5.0, '5 GB'), (10.0, '10 GB'), (20.0, '20 GB')],
                    AppSettings.downloadLimitGb);
                if (v != null) {
                  await _set('downloadLimitGb', v);
                  DownloadService.resume();
                }
              },
            ),
          ),
          SettingRow(
            title: 'Smart downloads',
            text: 'The next episode of each show on My List downloads by itself once it airs.',
            control: PixelSwitch(label: 'Smart downloads', value: AppSettings.smartDownloads, onChanged: (v) async {
              await _set('smartDownloads', v);
              if (v) DownloadService.smartFill();
            }),
          ),
          SettingRow(
            title: 'Delete when watched',
            text: "Remove an episode's saved copy once you've watched it to the end.",
            control: PixelSwitch(label: 'Delete when watched', value: AppSettings.autoDeleteWatched, onChanged: (v) => _set('autoDeleteWatched', v)),
          ),
          const SizedBox(height: 10),
          const SectionHeader(title: 'Alerts'),
          SettingRow(
            title: 'New-episode alerts',
            text: 'A notification when a show on My List airs a new episode, even with the app closed.',
            control: PixelSwitch(label: 'New-episode alerts', value: AppSettings.alerts, onChanged: _toggleAlerts),
          ),
          if (AppSettings.alerts)
            SettingRow(
              title: 'Quiet hours',
              text: 'No alerts at night; they arrive when quiet hours end.',
              control: ChoiceChipButton(
                label: AppSettings.quietFrom < 0 ? 'Off' : '${AppSettings.quietFrom}:00 - ${AppSettings.quietTo}:00',
                onTap: () async {
                  final v = await pickOption(context, 'Quiet hours',
                      const [(-1.0, 'Off'), (22.0, '22:00 - 08:00'), (23.0, '23:00 - 08:00'), (0.0, '00:00 - 08:00')],
                      AppSettings.quietFrom.toDouble());
                  if (v != null) _set('quietFrom', v);
                },
              ),
            ),
          if (AppSettings.alerts)
            Align(
              alignment: Alignment.centerLeft,
              child: PixelButton(
                label: 'Check now',
                icon: Sprites.bell,
                kind: PixelButtonKind.dark,
                fontSize: 8,
                onPressed: () async {
                  final n = await NativeBridge.checkAlertsNow();
                  if (context.mounted) pixelToast(context, n == 0 ? 'Nothing new on My List right now.' : '$n new episode alert${n == 1 ? '' : 's'}.');
                },
              ),
            ),
          const SizedBox(height: 10),
          const SectionHeader(title: 'Accessibility'),
          SettingRow(
            title: 'Text size',
            text: 'Make the text bigger everywhere in the app.',
            control: ChoiceChipButton(
              label: labelOf(textSizes, AppSettings.textScale),
              onTap: () async {
                final v = await pickOption(context, 'Text size', textSizes, AppSettings.textScale);
                if (v != null) _set('textScale', v);
              },
            ),
          ),
          SettingRow(
            title: 'High contrast',
            text: 'Brighter text and borders, and calmer backgrounds, on any palette.',
            control: PixelSwitch(label: 'High contrast', value: AppSettings.highContrast, onChanged: (v) => _set('highContrast', v)),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text('ANIVERSE PIXEL $kAppVersionName (BUILD $kAppBuildNumber)', style: PxFont.label(6, color: Px.ashDark)),
          ),
        ],
      ),
    );
  }
}
