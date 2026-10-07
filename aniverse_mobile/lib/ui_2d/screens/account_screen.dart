import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/history_service.dart';
import '../../services/native_bridge.dart';
import '../achievements.dart';
import '../theme_2d.dart';
import '../widgets/pixel_extras.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/poster_card.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// Sign in with Google or with a username and password, or see who is signed
/// in. Accounts are optional: everything works signed out, an account just
/// carries the watch history between devices.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ACCOUNT')),
      body: ValueListenableBuilder<AuthUser?>(
        valueListenable: AuthService.user,
        builder: (context, user, _) =>
            user == null ? const _SignIn() : _Profile(user: user),
      ),
    );
  }
}

// --- signed in ------------------------------------------------------------------

class _Profile extends StatefulWidget {
  final AuthUser user;

  const _Profile({required this.user});

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SIGN OUT?'),
        content: const Text(
          'Your history stays in your account. It will be removed from this '
          'phone until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: PxFont.label(9, color: Px.ash)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('SIGN OUT', style: PxFont.label(9, color: Px.bloodLight)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _signingOut = true);
    await AuthService.signOut();
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final handle = u.username != null ? '@${u.username}' : (u.email ?? '');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Center(child: UserAvatar(user: u, size: 92)),
        const SizedBox(height: 18),
        Center(
          child: Text(
            u.displayName.toUpperCase(),
            textAlign: TextAlign.center,
            style: PxFont.label(14).copyWith(shadows: PxFont.outline(1.5)),
          ),
        ),
        if (handle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Center(child: Text(handle, style: PxFont.text(15, color: Px.ash))),
        ],
        const SizedBox(height: 12),
        Center(
          child: PixelChip(
            u.provider == 'google' ? 'Google account' : 'AniVerse account',
            fill: Px.panelHigh,
          ),
        ),
        const SizedBox(height: 26),
        const ProgressCard(),
        const SizedBox(height: 18),
        const _Tracking(),
        const SizedBox(height: 18),
        _Tile(
          icon: Sprites.gear,
          title: 'Settings',
          subtitle: 'Palette, sound, subtitles, alerts',
          onTap: () => Navigator.push(context, FadeScaleRoute(page: const SettingsScreen())),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<int>(
          valueListenable: HistoryService.changes,
          builder: (context, _, __) {
            final n = HistoryService.latestPerAnime().length;
            return _Tile(
              icon: Sprites.clock,
              title: 'Watch history',
              subtitle: n == 0 ? 'Nothing yet' : '$n anime · synced to your account',
              onTap: () => Navigator.push(
                context,
                FadeScaleRoute(page: const HistoryScreen()),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _Tile(
          icon: Sprites.logout,
          title: _signingOut ? 'Signing out...' : 'Sign out',
          danger: true,
          onTap: _signingOut ? null : _signOut,
        ),
      ],
    );
  }
}

class _Tile extends StatefulWidget {
  final Sprite icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.danger = false,
  });

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.danger ? Px.bloodLight : Px.bone;
    return Semantics(
      button: true,
      label: widget.title,
      child: GestureDetector(
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: widget.onTap == null
            ? null
            : (_) {
                setState(() => _down = false);
                widget.onTap!();
              },
        child: PixelBox(
          fill: Px.panel,
          border: widget.danger ? Px.bloodDark : Px.black,
          pressed: _down,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              PixelSprite(widget.icon, scale: 2.2, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title.toUpperCase(), style: PxFont.label(10, color: color)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(widget.subtitle!, style: PxFont.text(13, color: Px.ash)),
                    ],
                  ],
                ),
              ),
              if (!widget.danger)
                const PixelSprite(Sprites.chevron, scale: 1.6, color: Px.ashDark),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square pixel avatar: the Google photo crushed to a sprite, or an initial
/// in the arcade face on blood.
class UserAvatar extends StatelessWidget {
  final AuthUser user;
  final double size;

  const UserAvatar({super.key, required this.user, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    final framed = size >= 48;
    final inner = url != null && url.isNotEmpty
        ? PixelCover(url: url, decodeWidth: 20)
        : ColoredBox(
            color: Px.blood,
            child: Center(
              child: Text(
                user.initial,
                style: PxFont.label(size * 0.42, height: 1)
                    .copyWith(shadows: PxFont.outline(size * 0.03)),
              ),
            ),
          );
    return SizedBox(
      width: size,
      height: size,
      child: PixelBox(
        fill: Px.black,
        shadow: framed ? 4 : 2,
        borderWidth: framed ? 3 : 2,
        child: inner,
      ),
    );
  }
}

// --- signed out -----------------------------------------------------------------

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  var _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _creating = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  AuthConfig? _config;

  @override
  void initState() {
    super.initState();
    AuthService.config().then((c) {
      if (mounted) setState(() => _config = c);
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = _creating
        ? await AuthService.register(_username.text, _password.text)
        : await AuthService.login(_username.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) _welcome();
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await AuthService.signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null && AuthService.signedIn) _welcome();
  }

  void _welcome() {
    final name = AuthService.user.value?.displayName;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(name == null ? 'Signed in' : 'Signed in as $name')),
    );
  }

  void _selectMode(bool creating) {
    if (_busy || creating == _creating) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _creating = creating;
      _error = null;
      // Keep the entered credentials, but discard validation from the other
      // form (for example, registration's minimum password length).
      _form = GlobalKey<FormState>();
      _confirm.clear();
      _hidePassword = true;
    });
  }

  InputDecoration _field(String label, Sprite icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(14),
          child: PixelSprite(icon, scale: 2, color: Px.ash),
        ),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    final googleReady = _config?.googleEnabled == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
      children: [
        const Center(child: AniVerseLogo(fontSize: 18)),
        const SizedBox(height: 30),
        Text(
          'Sign in to keep your watch history on every device.',
          textAlign: TextAlign.center,
          style: PxFont.text(14, color: Px.ash),
        ),
        const SizedBox(height: 22),
        PixelButton(
          label: 'Continue with Google',
          kind: PixelButtonKind.bone,
          expand: true,
          fontSize: 9,
          leading: Text('G', style: PxFont.label(14, color: googleReady ? Px.googleBlue : Px.ash)),
          onPressed: _busy || !googleReady ? null : _google,
        ),
        if (_config != null && !googleReady)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Google sign-in is not set up on this server yet.',
              textAlign: TextAlign.center,
              style: PxFont.text(13, color: Px.ashDark),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: SizedBox(height: 2, child: ColoredBox(color: Px.panelHigh))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('OR USE A USERNAME', style: PxFont.label(7, color: Px.ashDark)),
            ),
            Expanded(child: SizedBox(height: 2, child: ColoredBox(color: Px.panelHigh))),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: PixelButton(
                label: 'Sign in',
                kind: _creating ? PixelButtonKind.dark : PixelButtonKind.blood,
                expand: true,
                fontSize: 8,
                onPressed: _busy ? null : () => _selectMode(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PixelButton(
                label: 'Create account',
                kind: _creating ? PixelButtonKind.blood : PixelButtonKind.dark,
                expand: true,
                fontSize: 8,
                onPressed: _busy ? null : () => _selectMode(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  autocorrect: false,
                  style: PxFont.text(16),
                  textInputAction: TextInputAction.next,
                  autofillHints: [
                    _creating ? AutofillHints.newUsername : AutofillHints.username
                  ],
                  decoration: _field('Username', Sprites.user),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Enter a username';
                    if (_creating && !RegExp(r'^[A-Za-z0-9_.-]{3,24}$').hasMatch(s)) {
                      return '3-24 letters, numbers, or . _ -';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _hidePassword,
                  style: PxFont.text(16),
                  textInputAction: _creating ? TextInputAction.next : TextInputAction.done,
                  autofillHints: [
                    _creating ? AutofillHints.newPassword : AutofillHints.password
                  ],
                  onFieldSubmitted: (_) => _creating ? null : _submit(),
                  decoration: _field(
                    'Password',
                    Sprites.lock,
                    suffix: PixelIconButton(
                      sprite: _hidePassword ? Sprites.eye : Sprites.eyeOff,
                      tooltip: _hidePassword ? 'Show password' : 'Hide password',
                      color: Px.ash,
                      scale: 1.8,
                      onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.isEmpty) return 'Enter your password';
                    if (_creating && s.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                if (_creating) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: _hidePassword,
                    style: PxFont.text(16),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _field('Confirm password', Sprites.lock),
                    validator: (v) => v != _password.text ? "Passwords don't match" : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          PixelBox(
            fill: Px.bloodDeep,
            border: Px.blood,
            shadow: 2,
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PixelSprite(Sprites.skullSmall, scale: 2),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: PxFont.text(14))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        PixelButton(
          label: _creating ? 'Create account' : 'Sign in',
          expand: true,
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
        if (_creating)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              "There's no email and no password reset, so pick a password you'll remember.",
              textAlign: TextAlign.center,
              style: PxFont.text(13, color: Px.ashDark),
            ),
          ),
        const SizedBox(height: 34),
        // Progress counts signed out too; an account keeps it with the history.
        const ProgressCard(),
      ],
    );
  }
}


// --- level, rank, achievements ---------------------------------------------------

/// Level card, stats and badges, from watch history (so it counts signed out too).
class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryService.changes,
      builder: (context, _, __) {
        final s = Achievements.stats();
        final lv = Achievements.level(s);
        final got = Achievements.unlocked(s);
        final name = AuthService.user.value?.displayName ?? 'Player';
        Widget stat(String v, String label) => Expanded(
              child: PixelBox(
                padding: const EdgeInsets.fromLTRB(8, 8, 6, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v, style: PxFont.label(11)),
                  const SizedBox(height: 4),
                  Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: PxFont.label(5, color: Px.ash)),
                ]),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PixelBox(
              rivets: true,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                // The frame steps up every 10 levels: bronze, silver, gold, blood, legend.
                PixelBox(
                  fill: Px.blood,
                  border: Color(Achievements.frameColor(lv.frame)),
                  borderWidth: 4,
                  shadow: 3,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Center(
                      child: Text(name.trim().isEmpty ? 'P' : name.trim()[0].toUpperCase(),
                          style: PxFont.label(22).copyWith(shadows: PxFont.outline(1.5))),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('LV ${lv.level} · ${lv.rank.toUpperCase()}', style: PxFont.label(9, color: Px.gold)),
                    const SizedBox(height: 8),
                    PixelBar(fraction: lv.progress, height: 12),
                    const SizedBox(height: 6),
                    Text(lv.level >= 99 ? '${lv.xp} XP · MAX LEVEL' : '${lv.xp} XP · ${lv.toNext} TO LEVEL ${lv.level + 1}',
                        style: PxFont.label(6, color: Px.ash)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              stat('${s.finished}', 'Episodes'),
              const SizedBox(width: 8),
              stat('${s.anime}', 'Anime'),
              const SizedBox(width: 8),
              stat('${s.streak}', 'Day streak'),
              const SizedBox(width: 8),
              stat('${s.hours.floor()}h', 'Watched'),
            ]),
            const SizedBox(height: 18),
            SectionHeader(title: 'Achievements ${got.length}/${Achievements.badges.length}'),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
              children: [
                for (final b in Achievements.badges)
                  Opacity(
                    opacity: got.contains(b.id) ? 1 : 0.35,
                    child: PixelBox(
                      border: got.contains(b.id) ? Px.gold : Px.black,
                      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                      child: Column(children: [
                        PixelSprite(b.sprite, scale: 2.6, color: got.contains(b.id) ? Px.gold : Px.ash),
                        const SizedBox(height: 8),
                        Text(b.name.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, style: PxFont.label(5, height: 1.4)),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(b.text, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                              style: PxFont.text(10, color: Px.ash, height: 1.2)),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// --- AniList / MyAnimeList ------------------------------------------------------------

class _Tracking extends StatefulWidget {
  const _Tracking();

  @override
  State<_Tracking> createState() => _TrackingState();
}

class _TrackingState extends State<_Tracking> {
  Map<String, dynamic> _cfg = const {};
  Map<String, dynamic> _status = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await ApiService.trackingConfig();
    Map<String, dynamic> status = const {};
    try {
      final r = await http.get(Uri.parse('${ApiService.baseUrl}/tracking'), headers: AuthService.headers)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) status = Map<String, dynamic>.from(json.decode(r.body) as Map);
    } catch (_) {}
    if (mounted) {
      setState(() {
      _cfg = cfg;
      _status = status;
    });
    }
  }

  Future<void> _connect(String id) async {
    if (id == 'mal') {
      try {
        final r = await http.post(Uri.parse('${ApiService.baseUrl}/tracking/mal/start'), headers: AuthService.headers)
            .timeout(const Duration(seconds: 15));
        final url = (json.decode(r.body) as Map)['url'];
        if (r.statusCode == 200 && url is String) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          if (mounted) pixelToast(context, 'Finish on the MyAnimeList page, then come back here.', action: 'Refresh', onAction: _load);
        }
      } catch (_) {
        if (mounted) pixelToast(context, "Couldn't start the MyAnimeList sign-in.");
      }
      return;
    }
    // AniList shows a token on its own page; it is pasted back here.
    final authorize = (_cfg['anilist'] as Map?)?['authorize_url']?.toString();
    if (authorize == null) return;
    await launchUrl(Uri.parse(authorize), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    final ctl = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ANILIST TOKEN'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Approve AniVerse on the AniList page, then copy the long token it shows into this box.',
              style: PxFont.text(13, color: Px.ash)),
          const SizedBox(height: 10),
          TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'Paste the token')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('CONNECT')),
        ],
      ),
    );
    if (token == null || token.isEmpty) return;
    try {
      final r = await http.post(Uri.parse('${ApiService.baseUrl}/tracking/anilist'),
          headers: AuthService.headers, body: json.encode({'token': token})).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode == 200) {
        Sfx.play('achieve');
        pixelToast(context, 'AniList connected.');
      } else {
        pixelToast(context, "AniList didn't accept that token.");
      }
    } catch (_) {
      if (mounted) pixelToast(context, "Couldn't reach the server.");
    }
    _load();
  }

  Future<void> _disconnect(String id) async {
    try {
      await http.delete(Uri.parse('${ApiService.baseUrl}/tracking/$id'), headers: AuthService.headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String id, String name) {
      final st = _status[id] is Map ? _status[id] as Map : const {};
      final enabled = (_cfg[id] as Map?)?['enabled'] == true;
      final connected = st['connected'] == true;
      return SettingRow(
        title: name,
        text: connected
            ? 'Connected${st['account'] != null ? ' as ${st['account']}' : ''}.'
            : enabled
                ? 'Episodes you finish update your list.'
                : 'Not set up on this server yet.',
        control: connected
            ? PixelButton(label: 'Disconnect', kind: PixelButtonKind.dark, fontSize: 7, onPressed: () => _disconnect(id))
            : enabled
                ? PixelButton(label: 'Connect', fontSize: 7, onPressed: () => _connect(id))
                : const SizedBox.shrink(),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'Tracking'),
      row('anilist', 'AniList'),
      row('mal', 'MyAnimeList'),
    ]);
  }
}
