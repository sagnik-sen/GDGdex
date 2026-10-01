import 'dart:convert';

import 'package:gdgdex_server/api.dart';
import 'package:gdgdex_server/db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

late Api api;
late Db store;

Future<(int, Map<String, dynamic>, String?)> call(String method, String path, {Object? body, String? cookie}) async {
  final res = await api.call(
    Request(
      method,
      Uri.parse('http://x/$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {if (cookie != null) 'cookie': cookie},
    ),
  );
  final text = await res.readAsString();
  final setCookie = res.headers['set-cookie']?.split(';').first;
  return (res.statusCode, text.startsWith('{') ? jsonDecode(text) as Map<String, dynamic> : {'raw': text}, setCookie);
}

Future<String> login(String email, String reg) async {
  final (s, _, c) = await call('POST', 'api/login', body: {'email': email, 'regNo': reg});
  expect(s, 200);
  return c!;
}

Future<void> setEvent(String admin, String status) async =>
    expect((await call('POST', 'api/admin/event', body: {'status': status}, cookie: admin)).$1, 200);

void main() {
  late String alice, admin;
  late String bobKey, carolKey;

  setUp(() async {
    store = Db.memory();
    api = Api(store);
    store.createUser(name: 'Org', email: 'org@x.com', regNo: '20ORG0001', isAdmin: true);
    store.createUser(name: 'Alice', email: 'alice@x.com', regNo: '23BCE0001');
    bobKey = store.createUser(name: 'Bob', email: 'bob@x.com', regNo: '23BCE0002')['passkey'] as String;
    carolKey = store.createUser(name: 'Carol', email: 'carol@x.com', regNo: '23BCE0003')['passkey'] as String;
    alice = await login('Alice@X.com ', '23bce0001');
    admin = await login('org@x.com', '20ORG0001');
  });

  test('login rejects wrong reg no and never stores it raw', () async {
    expect((await call('POST', 'api/login', body: {'email': 'alice@x.com', 'regNo': 'nope'})).$1, 401);
    expect(store.one("SELECT 1 FROM users WHERE reg_hash LIKE '%0001%'"), isNull);
  });

  test('collecting is rejected before start and after end; admin start/end', () async {
    var (s, b, _) = await call('POST', 'api/collect', body: {'code': bobKey}, cookie: alice);
    expect((s, b['code']), (403, 'EVENT_NOT_STARTED'));
    await setEvent(admin, 'ACTIVE');
    expect((await call('POST', 'api/collect', body: {'code': bobKey}, cookie: alice)).$2['result'], 'NEW');
    await setEvent(admin, 'ENDED');
    (s, b, _) = await call('POST', 'api/collect', body: {'code': carolKey}, cookie: alice);
    expect((s, b['code']), (403, 'EVENT_ENDED'));
    final lb = (await call('GET', 'api/leaderboard')).$2;
    expect(lb['event']['status'], 'ENDED');
    expect(lb['entries'][0]['name'], 'Alice');
  });

  group('during event', () {
    setUp(() => setEvent(admin, 'ACTIVE'));

    test('QR payload lookup then collect; passkey; duplicates; self; invalid', () async {
      var (s, b, _) = await call('POST', 'api/lookup', body: {'code': 'GDGDEX:$bobKey'}, cookie: alice);
      expect(b['member']['name'], 'Bob');
      expect(b['member'].containsKey('passkey'), isFalse);
      expect(b['alreadyCollected'], isFalse);

      expect((await call('POST', 'api/collect', body: {'code': 'GDGDEX:$bobKey'}, cookie: alice)).$2['result'], 'NEW');
      // same person again via passkey, lowercase
      (s, b, _) = await call('POST', 'api/collect', body: {'code': bobKey.toLowerCase()}, cookie: alice);
      expect((s, b['result'], b['count']), (200, 'ALREADY', 1));

      final mine = (await call('GET', 'api/me', cookie: alice)).$2['passkey'];
      (s, b, _) = await call('POST', 'api/collect', body: {'code': mine}, cookie: alice);
      expect((s, b['code']), (400, 'SELF'));

      (s, b, _) = await call('POST', 'api/collect', body: {'code': 'ZZZZZZ'}, cookie: alice);
      expect((s, b['error']), (404, "That GDGdex entry doesn't exist."));
      // public dex id is not a valid collection code
      expect((await call('POST', 'api/collect', body: {'code': 'GDG-003'}, cookie: alice)).$1, 404);

      expect(store.one('SELECT COUNT(*) n FROM collections')!['n'], 1);
    });

    test('concurrent duplicate collects create one row; parallel collectors both succeed', () async {
      final bob = await login('bob@x.com', '23BCE0002');
      final results = await Future.wait([
        for (var i = 0; i < 20; i++) call('POST', 'api/collect', body: {'code': carolKey}, cookie: alice),
        call('POST', 'api/collect', body: {'code': carolKey}, cookie: bob),
      ]);
      expect(results.where((r) => r.$2['result'] == 'NEW').length, 2);
      expect(store.one('SELECT COUNT(*) n FROM collections')!['n'], 2);
    });

    test('DB enforces uniqueness and no self-collection regardless of app code', () {
      store.db.execute('INSERT INTO collections (collector_id, collected_id) VALUES (2, 3)');
      expect(
        () => store.db.execute('INSERT INTO collections (collector_id, collected_id) VALUES (2, 3)'),
        throwsA(anything),
      );
      expect(
        () => store.db.execute('INSERT INTO collections (collector_id, collected_id) VALUES (2, 2)'),
        throwsA(anything),
      );
    });

    test('leaderboard counts unique entries, ties broken by who got there first', () async {
      final bob = await login('bob@x.com', '23BCE0002');
      final aliceKey = (await call('GET', 'api/me', cookie: alice)).$2['passkey'];
      await call('POST', 'api/collect', body: {'code': bobKey}, cookie: alice);
      await call('POST', 'api/collect', body: {'code': bobKey}, cookie: alice);
      await call('POST', 'api/collect', body: {'code': aliceKey}, cookie: bob);
      await call('POST', 'api/collect', body: {'code': carolKey}, cookie: alice);
      final e = (await call('GET', 'api/leaderboard')).$2['entries'] as List;
      expect([e[0]['name'], e[0]['count']], ['Alice', 2]);
      expect([e[1]['name'], e[1]['count']], ['Bob', 1]);
      expect(e.every((x) => !(x as Map).containsKey('passkey')), isTrue);
    });

    test('disabled member: cannot be collected, cannot log in, session revoked', () async {
      final bob = await login('bob@x.com', '23BCE0002');
      await call('PATCH', 'api/admin/members/GDG-003', body: {'isActive': false}, cookie: admin);
      expect((await call('POST', 'api/collect', body: {'code': bobKey}, cookie: alice)).$1, 404);
      expect((await call('GET', 'api/me', cookie: bob)).$1, 401);
      expect((await call('POST', 'api/login', body: {'email': 'bob@x.com', 'regNo': '23BCE0002'})).$1, 403);
    });

    test('regenerated passkey invalidates the old one', () async {
      final r = (await call('POST', 'api/admin/members/GDG-003/passkey', cookie: admin)).$2;
      expect(r['member']['passkey'], isNot(bobKey));
      expect((await call('POST', 'api/collect', body: {'code': bobKey}, cookie: alice)).$1, 404);
    });
  });

  test('non-admins and anonymous users cannot reach admin endpoints', () async {
    for (final c in [alice, null]) {
      expect((await call('GET', 'api/admin/members', cookie: c)).$1, c == null ? 401 : 403);
      expect((await call('POST', 'api/admin/event', body: {'status': 'ACTIVE'}, cookie: c)).$1, c == null ? 401 : 403);
    }
    expect(store.event()['status'], 'NOT_STARTED');
  });

  test('admin creates member (duplicate email rejected) and exports CSV', () async {
    var (s, b, _) = await call(
      'POST',
      'api/admin/members',
      body: {'name': 'Dan', 'email': 'dan@x.com', 'regNo': '23BCE0004', 'role': 'Lead'},
      cookie: admin,
    );
    expect((s, b['member']['dexId']), (200, 'GDG-005'));
    expect(
      (await call(
        'POST',
        'api/admin/members',
        body: {'name': 'Dan2', 'email': 'DAN@x.com', 'regNo': '1'},
        cookie: admin,
      )).$1,
      409,
    );
    expect((await call('GET', 'api/admin/export/members.csv', cookie: admin)).$2['raw'], contains('dan@x.com'));
  });

  test('login is rate limited on failures only', () async {
    for (var i = 0; i < 15; i++) {
      expect((await call('POST', 'api/login', body: {'email': 'carol@x.com', 'regNo': '23BCE0003'})).$1, 200);
    }
    for (var i = 0; i < 10; i++) {
      await call('POST', 'api/login', body: {'email': 'carol@x.com', 'regNo': 'guess$i'});
    }
    expect((await call('POST', 'api/login', body: {'email': 'carol@x.com', 'regNo': '23BCE0003'})).$1, 429);
  });
}
