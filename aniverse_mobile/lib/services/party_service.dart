import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'auth_service.dart';

/// What a party member is doing: the episode, and where in it.
class PartyState {
  final String anime;
  final int ep;
  final String category;
  final bool playing;
  final double t;
  final double at;
  final String by;

  const PartyState({
    required this.anime,
    required this.ep,
    required this.category,
    required this.playing,
    required this.t,
    this.at = 0,
    this.by = '',
  });

  factory PartyState.fromJson(Map j) => PartyState(
        anime: j['anime'].toString(),
        ep: (j['ep'] as num).toInt(),
        category: (j['category'] ?? 'sub').toString(),
        playing: j['playing'] == true,
        t: ((j['t'] ?? 0) as num).toDouble(),
        at: ((j['at'] ?? 0) as num).toDouble(),
        by: (j['by'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'type': 'state', 'anime': anime, 'ep': ep, 'category': category, 'playing': playing, 't': t};
}

/// A watch party: the server's /ws/party/{code} room, shared with the website.
/// Whoever plays, pauses, seeks or changes episode sends the new state; the
/// others follow it. Times are worked out on the server's clock.
class PartyConnection {
  final String code;
  final PartyState Function() getState;

  /// Someone else moved: [t] is where playback should be now.
  final void Function(PartyState state, double t) onState;

  final ValueNotifier<List<String>> members = ValueNotifier(const []);
  final ValueNotifier<List<(String, String)>> chat = ValueNotifier(const []); // (name, text); name '' = system
  final ValueNotifier<String> status = ValueNotifier('Connecting…');

  WebSocket? _ws;
  Timer? _ping;
  double _offset = 0;
  bool _closed = false;
  int _retry = 0;
  String _me = 'Guest';

  PartyConnection({required this.code, required this.getState, required this.onState});

  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static String newCode() {
    final r = math.Random.secure();
    return List.generate(6, (_) => _chars[r.nextInt(_chars.length)]).join();
  }

  static bool validCode(String c) => RegExp(r'^[A-Z0-9]{4,8}$').hasMatch(c.toUpperCase());

  static Future<String> _myName() async {
    final u = AuthService.user.value;
    if (u != null && u.displayName.isNotEmpty) return u.displayName;
    try {
      final prefs = await SharedPreferences.getInstance();
      var n = prefs.getString('av.party.name');
      if (n == null) {
        n = 'Guest-${newCode().substring(0, 4)}';
        await prefs.setString('av.party.name', n);
      }
      return n;
    } catch (_) {
      return 'Guest';
    }
  }

  String get inviteLink => '${ApiService.webUrl}/watch/${getState().anime}/${getState().ep}?party=$code';

  double get _serverNow => DateTime.now().millisecondsSinceEpoch / 1000 + _offset;
  double _where(PartyState s) => s.t + (s.playing ? math.max(0, _serverNow - s.at) : 0);

  void _line(String name, String text) {
    final list = [...chat.value, (name, text)];
    chat.value = list.length > 60 ? list.sublist(list.length - 60) : list;
  }

  Future<void> connect() async {
    _me = await _myName();
    if (_closed) return;
    final ws = ApiService.webUrl.replaceFirst(RegExp(r'^http'), 'ws');
    try {
      final socket = await WebSocket.connect('$ws/ws/party/$code?name=${Uri.encodeQueryComponent(_me)}')
          .timeout(const Duration(seconds: 15));
      if (_closed) {
        socket.close();
        return;
      }
      _ws = socket;
      _retry = 0;
      status.value = '';
      _ping?.cancel();
      // Tunnels drop quiet sockets; a ping now and then keeps the room open.
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
      socket.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
    } catch (_) {
      _onClosed();
    }
  }

  void _onMessage(dynamic data) {
    Map m;
    try {
      m = json.decode(data as String) as Map;
    } catch (_) {
      return;
    }
    if (m['now'] is num) _offset = (m['now'] as num).toDouble() - DateTime.now().millisecondsSinceEpoch / 1000;
    switch (m['type']) {
      case 'hello':
        _me = (m['you'] ?? _me).toString();
        members.value = [for (final x in (m['members'] as List? ?? const [])) x.toString()];
        _line('', 'You joined party $code as $_me.');
        if (m['state'] is Map) {
          final s = PartyState.fromJson(m['state'] as Map);
          onState(s, _where(s));
        } else {
          send(); // first in: what you are watching is the party's episode
        }
      case 'members':
        members.value = [for (final x in (m['members'] as List? ?? const [])) x.toString()];
        if (m['joined'] != null) {
          _line('', '${m['joined']} joined.');
          // Bring the newcomer to the exact spot; a paused room's state is already exact.
          final s = getState();
          if (s.playing) send(s);
        }
        if (m['left'] != null) _line('', '${m['left']} left.');
      case 'state':
        if (m['state'] is Map) {
          final s = PartyState.fromJson(m['state'] as Map);
          onState(s, _where(s));
        }
      case 'chat':
        _line((m['name'] ?? '').toString(), (m['text'] ?? '').toString());
    }
  }

  void _onClosed() {
    _ping?.cancel();
    _ws = null;
    if (_closed) return;
    status.value = 'Reconnecting…';
    final wait = Duration(milliseconds: math.min(15000, 1000 * (1 << math.min(_retry++, 4))));
    Timer(wait, () {
      if (!_closed) connect();
    });
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ws?.add(json.encode(m));
    } catch (_) {}
  }

  /// After anything the viewer did.
  void send([PartyState? s]) => _send((s ?? getState()).toJson());

  void say(String text) {
    final t = text.trim();
    if (t.isNotEmpty) _send({'type': 'chat', 'text': t});
  }

  /// Moving to another episode: tell the room, then go quiet, so this page
  /// cannot answer a newcomer with the old episode and bounce everyone back.
  void sendEpisode(int ep) {
    final s = getState();
    send(PartyState(anime: s.anime, ep: ep, category: s.category, playing: true, t: 0));
    close();
  }

  void close() {
    _closed = true;
    _ping?.cancel();
    _ws?.close();
    _ws = null;
  }
}
