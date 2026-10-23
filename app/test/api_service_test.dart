import 'dart:convert';
import 'dart:io';

import 'package:app/model/account.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/rust.dart';

const _userId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initRustLib();
  });

  test('accounts stored with the whole user still parse', () {
    final account = AccountMapper.fromJson(
      jsonEncode({
        'api_url': 'https://repolupe.example.com',
        'token': 'secret',
        'user': {
          'id': _userId,
          'role': 'ADMIN',
          'user_name': 'admin',
          'email': null,
          'can_manage_repositories': true,
          'must_change_password': false,
          'auto_commit': false,
          'full_name': null,
        },
      }),
    );
    expect(account.key, 'https://repolupe.example.com#$_userId');
    expect(account.user.userName, 'admin');
    expect(account.token, 'secret');
    expect(AccountMapper.fromJson(account.toJson()).key, account.key);
  });

  test('login and logout go through the Rust client', () async {
    final requests = <HttpRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add(request);
      final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
      final response = request.response;
      switch (request.uri.path) {
        case '/api/v1/login' when body['password'] == 'right':
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode({
              'token': 'session-token',
              'user': {
                'id': _userId,
                'role': 'USER',
                'user_name': 'alice',
                'can_login': true,
                'can_manage_repositories': true,
                'can_change_identity': true,
                'must_change_password': false,
                'auto_commit': false,
                'created_at': '2026-10-20T12:00:00+00:00',
              },
            }),
          );
        case '/api/v1/login':
          response.statusCode = 401;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'code': 'UNAUTHORIZED', 'message': 'Wrong credentials.'}));
        case '/api/v1/logout':
          response.statusCode = 204;
        default:
          response.statusCode = 404;
      }
      await response.close();
    });

    final apiUrl = 'http://127.0.0.1:${server.port}';
    final container = RefenaContainer();
    final api = container.redux(apiProvider);

    await expectLater(
      api.dispatchAsyncTakeResult(ApiLoginAction(apiUrl: apiUrl, userNameOrEmail: 'alice', password: 'wrong')),
      throwsA(isA<ClientError_Api>().having((e) => e.code, 'code', ErrorCode.unauthorized)),
    );

    final (account, user) = await api.dispatchAsyncTakeResult(ApiLoginAction(apiUrl: apiUrl, userNameOrEmail: 'alice', password: 'right'));
    expect(account.apiUrl, apiUrl);
    expect(user.userName, 'alice');
    expect(account.token, 'session-token');
    expect(account.user.id, _userId);
    expect(account.user.userName, 'alice');
    expect(requests.last.headers.value(HttpHeaders.acceptLanguageHeader), isNotEmpty);

    api.dispatch(ApiSetAccountAction(account));
    expect(container.read(apiProvider)?.account, account);

    await api.dispatchAsync(ApiLogoutAction(account: account));
    expect(requests.last.uri.path, '/api/v1/logout');
    expect(requests.last.headers.value(HttpHeaders.authorizationHeader), 'Bearer session-token');

    api.dispatch(ApiSetAccountAction(null));
    expect(container.read(apiProvider), isNull);
  });
}
