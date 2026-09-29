import 'dart:convert';

import 'package:aniverse_mobile/services/auth_service.dart';
import 'package:aniverse_mobile/services/history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.sessionExpired();
  });

  for (final creating in [false, true]) {
    test(
        '${creating ? 'registration' : 'login'} explains missing server routes',
        () async {
      await http.runWithClient(() async {
        final error = creating
            ? await AuthService.register('AnimeFan', 'password123')
            : await AuthService.login('AnimeFan', 'password123');
        expect(error, contains('Account services are unavailable'));
        expect(error, isNot(contains('Not Found')));
        expect(AuthService.signedIn, isFalse);
      },
          () => MockClient((request) async {
                expect(request.url.path,
                    creating ? '/api/auth/register' : '/api/auth/login');
                return http.Response('{"detail":"Not Found"}', 404);
              }));
    });
  }

  test('wrong password and duplicate username keep the useful server detail',
      () async {
    for (final entry in {
      401: 'Wrong username or password',
      409: 'That username is taken'
    }.entries) {
      await http.runWithClient(() async {
        final error = await AuthService.login('AnimeFan', 'password123');
        expect(error, entry.value);
      },
          () => MockClient((_) async =>
              http.Response(jsonEncode({'detail': entry.value}), entry.key)));
    }
  });

  test('unavailable server and malformed successful replies are recoverable',
      () async {
    for (final reply in [
      http.Response('<html>Bad gateway</html>', 502),
      http.Response('{"user":{"id":1}}', 200),
      http.Response('{"token":"session","user":{"id":"invalid"}}', 200),
      http.Response('not json', 200),
    ]) {
      await http.runWithClient(() async {
        expect(
            await AuthService.register('AnimeFan', 'password123'), isNotNull);
        expect(AuthService.signedIn, isFalse);
      }, () => MockClient((_) async => reply));
    }
  });

  test('network failure gives a connection error', () async {
    await http.runWithClient(() async {
      expect(await AuthService.login('AnimeFan', 'password123'),
          contains("Can't reach"));
    }, () => MockClient((_) async => throw http.ClientException('offline')));
  });

  test('successful registration saves a usable session and starts history sync',
      () async {
    var synced = false;
    await http.runWithClient(() async {
      expect(await AuthService.register('  AnimeFan  ', 'password123'), isNull);
      await HistoryService.sync();
      expect(AuthService.signedIn, isTrue);
      expect(AuthService.user.value?.username, 'AnimeFan');
      expect(AuthService.headers['Authorization'], 'Bearer session-token');
      expect(
          (await SharedPreferences.getInstance())
              .getString('aniverse_auth_token'),
          'session-token');
      expect(synced, isTrue);
    },
        () => MockClient((request) async {
              if (request.url.path == '/api/history') {
                expect(
                    request.headers['Authorization'], 'Bearer session-token');
                synced = true;
                return http.Response('{"entries":[]}', 200);
              }
              expect(request.url.path, '/api/auth/register');
              expect(jsonDecode(request.body)['username'], 'AnimeFan');
              return http.Response(
                  jsonEncode({
                    'token': 'session-token',
                    'user': {
                      'id': 1,
                      'username': 'AnimeFan',
                      'display_name': 'AnimeFan',
                      'provider': 'password'
                    },
                  }),
                  200);
            }));
  });
}
