import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../theme.dart';
import '../widgets/aniverse_logo.dart';
import 'history_screen.dart';

/// Sign in with Google or with a username and password, or see who is signed
/// in. Accounts are optional: everything works signed out, an account just
/// carries the watch history between devices.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('Account', style: TextStyle(fontSize: 18))),
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
        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your history stays in your account. It will be removed from this '
          'phone until you sign in again.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out',
                style: TextStyle(color: AniVerseTheme.red)),
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
        Center(child: UserAvatar(user: u, size: 88)),
        const SizedBox(height: 14),
        Center(
          child: Text(u.displayName,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        if (handle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(handle,
                style: const TextStyle(
                    color: AniVerseTheme.textDim, fontSize: 12)),
          ),
        ],
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AniVerseTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              u.provider == 'google' ? 'Google account' : 'AniVerse account',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ),
        const SizedBox(height: 28),
        ValueListenableBuilder<int>(
          valueListenable: HistoryService.changes,
          builder: (context, _, __) {
            final n = HistoryService.latestPerAnime().length;
            return _Tile(
              icon: Icons.history,
              title: 'Watch history',
              subtitle:
                  n == 0 ? 'Nothing yet' : '$n anime · synced to your account',
              onTap: () => Navigator.push(
                context,
                FadeScaleRoute(page: const HistoryScreen()),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _Tile(
          icon: Icons.logout,
          title: _signingOut ? 'Signing out…' : 'Sign out',
          danger: true,
          onTap: _signingOut ? null : _signOut,
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
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
  Widget build(BuildContext context) {
    return Material(
      color: AniVerseTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: danger ? AniVerseTheme.red : Colors.white70),
        title: Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: danger ? AniVerseTheme.red : Colors.white)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!,
                style: const TextStyle(
                    fontSize: 11, color: AniVerseTheme.textDim)),
        trailing: danger
            ? null
            : const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}

/// Round avatar: the Google photo when there is one, otherwise an initial.
class UserAvatar extends StatelessWidget {
  final AuthUser user;
  final double size;

  const UserAvatar({super.key, required this.user, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AniVerseTheme.red, AniVerseTheme.redDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        user.initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
    final url = user.avatarUrl;
    if (url == null || url.isEmpty) return initial;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => initial,
        errorWidget: (_, __, ___) => initial,
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
      SnackBar(
          content: Text(name == null ? 'Signed in' : 'Signed in as $name')),
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

  @override
  Widget build(BuildContext context) {
    final googleReady = _config?.googleEnabled == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        const Center(child: AniVerseLogo(fontSize: 26)),
        const SizedBox(height: 10),
        const Text(
          'Sign in to keep your watch history on every device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AniVerseTheme.textDim, fontSize: 12),
        ),
        const SizedBox(height: 28),
        _GoogleButton(
          onPressed: _busy || !googleReady ? null : _google,
        ),
        if (_config != null && !googleReady)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Google sign-in is not set up on this server yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AniVerseTheme.textFaint, fontSize: 11),
            ),
          ),
        const SizedBox(height: 22),
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('or use a username',
                  style:
                      TextStyle(color: AniVerseTheme.textFaint, fontSize: 11)),
            ),
            Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        const SizedBox(height: 18),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Sign in')),
            ButtonSegment(value: true, label: Text('Create account')),
          ],
          selected: {_creating},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AniVerseTheme.red,
            selectedForegroundColor: Colors.white,
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white24),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          onSelectionChanged: _busy ? null : (s) => _selectMode(s.first),
        ),
        const SizedBox(height: 18),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: [
                    _creating
                        ? AutofillHints.newUsername
                        : AutofillHints.username
                  ],
                  decoration: _field('Username', Icons.person_outline),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Enter a username';
                    if (_creating &&
                        !RegExp(r'^[A-Za-z0-9_.-]{3,24}$').hasMatch(s)) {
                      return '3-24 letters, numbers, or . _ -';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _hidePassword,
                  textInputAction:
                      _creating ? TextInputAction.next : TextInputAction.done,
                  autofillHints: [
                    _creating
                        ? AutofillHints.newPassword
                        : AutofillHints.password
                  ],
                  onFieldSubmitted: (_) => _creating ? null : _submit(),
                  decoration: _field('Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                          _hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white38),
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.isEmpty) return 'Enter your password';
                    if (_creating && s.length < 8) {
                      return 'At least 8 characters';
                    }
                    if (_creating && s.length > 128) {
                      return 'At most 128 characters';
                    }
                    return null;
                  },
                ),
                if (_creating) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: _hidePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _field('Confirm password', Icons.lock_outline),
                    validator: (v) =>
                        v != _password.text ? "Passwords don't match" : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AniVerseTheme.redDark.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AniVerseTheme.red.withValues(alpha: 0.5)),
            ),
            child: Text(_error!,
                style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AniVerseTheme.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(_creating ? 'Create account' : 'Sign in',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        if (_creating)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              "There's no email and no password reset, so pick a password you'll remember.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AniVerseTheme.textFaint, fontSize: 11),
            ),
          ),
      ],
    );
  }

  InputDecoration _field(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: AniVerseTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AniVerseTheme.red),
        ),
      );
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          disabledBackgroundColor: Colors.white24,
          disabledForegroundColor: Colors.white38,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onPressed == null ? Colors.white12 : Colors.white,
                border: Border.all(color: Colors.black12),
              ),
              child: const Text('G',
                  style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontWeight: FontWeight.w900,
                      fontSize: 14)),
            ),
            const SizedBox(width: 12),
            const Text('Continue with Google',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
