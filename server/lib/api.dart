import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';

const _cookie = 'gdgdex_session';

class ApiError implements Exception {
  final int status;
  final String message;
  final String? code;
  ApiError(this.status, this.message, [this.code]);
}

/// Fixed-window counter. ponytail: in-memory, single process; resets on restart, fine for a 2h event.
class RateLimiter {
  final int max;
  final Duration window;
  final _hits = <String, (DateTime, int)>{};
  RateLimiter(this.max, this.window);

  /// Throws once [key] has used up its budget, without spending any.
  void check(String key) {
    final e = _hits[key];
    if (e != null && DateTime.now().difference(e.$1) <= window && e.$2 >= max) {
      throw ApiError(429, 'Slow down — too many attempts. Try again in a minute.', 'RATE_LIMITED');
    }
  }

  void hit(String key) {
    final now = DateTime.now();
    final (start, n) = _hits[key] ?? (now, 0);
    final fresh = now.difference(start) > window;
    final count = fresh ? 1 : n + 1;
    _hits[key] = (fresh ? now : start, count);
    if (count > max) throw ApiError(429, 'Slow down — too many attempts. Try again in a minute.', 'RATE_LIMITED');
  }
}

class Api {
  final Db store;
  final bool secureCookies;
  final loginLimiter = RateLimiter(10, const Duration(minutes: 5));
  // Whole venue may share one NAT'd campus IP, so the per-IP cap is generous.
  final ipLimiter = RateLimiter(200, const Duration(minutes: 5)); // failures only
  final lookupLimiter = RateLimiter(30, const Duration(minutes: 1));
  Database get db => store.db;

  Api(this.store, {this.secureCookies = false});

  Future<Response> call(Request req) async {
    try {
      return await _route(req);
    } on ApiError catch (e) {
      return _json({'error': e.message, 'code': e.code}, status: e.status);
    } on FormatException {
      return _json({'error': 'Bad request'}, status: 400);
    }
  }

  Future<Response> _route(Request req) async {
    final path = req.url.path; // without leading slash, e.g. api/login
    final m = req.method;
    final seg = path.split('/');

    switch ((m, path)) {
      case ('GET', 'api/state'):
        return _json(
          _cached('state', () => {'event': store.event(), 'stats': store.stats(), 'top': store.leaderboard(limit: 5)}),
        );
      case ('GET', 'api/leaderboard'):
        return _json(_cached('leaderboard', () => {'event': store.event(), 'entries': store.leaderboard()}));
      case ('POST', 'api/login'):
        return _login(req);
      case ('POST', 'api/logout'):
        final t = _token(req);
        if (t != null) db.execute('DELETE FROM sessions WHERE token_hash = ?', [sha256Hex(t)]);
        return _json({'ok': true}, headers: {'set-cookie': _setCookie('', maxAge: 0)});
      case ('GET', 'api/me'):
        final u = _auth(req);
        return _json(_me(u));
      case ('POST', 'api/lookup'):
        final u = _auth(req);
        lookupLimiter.hit('u${u['id']}');
        final target = _target(u, (await _body(req))['code']);
        final already =
            store.one('SELECT 1 FROM collections WHERE collector_id = ? AND collected_id = ?', [
              u['id'],
              target['id'],
            ]) !=
            null;
        return _json({'member': Db.publicUser(target), 'alreadyCollected': already});
      case ('POST', 'api/collect'):
        final u = _auth(req);
        lookupLimiter.hit('u${u['id']}');
        final code = (await _body(req))['code'];
        return _json(_collect(u, code));
      case ('GET', 'api/collection'):
        final u = _auth(req);
        final rows = db.select(
          '''
          SELECT ${Db.publicCols}, c.created_at FROM collections c JOIN users u ON u.id = c.collected_id
          WHERE c.collector_id = ? AND u.is_active = 1 ORDER BY c.created_at DESC''',
          [u['id']],
        );
        return _json({
          'total': store.collectibleTotal(),
          'entries': [
            for (final r in rows) {...Db.publicUser(r), 'collectedAt': r['created_at']},
          ],
        });
    }

    if (seg.length >= 2 && seg[0] == 'api' && seg[1] == 'admin') {
      _admin(req);
      return _adminRoute(req, m, seg.sublist(2));
    }
    throw ApiError(404, 'Not found');
  }

  // ---------------- auth ----------------

  Future<Response> _login(Request req) async {
    final b = await _body(req);
    final email = (b['email'] as String? ?? '').trim().toLowerCase();
    final regNo = (b['regNo'] as String? ?? '').trim();
    final ip =
        req.headers['x-forwarded-for']?.split(',').first.trim() ??
        (req.context['shelf.io.connection_info'] as dynamic)?.remoteAddress?.address ??
        'unknown';
    // Only failed attempts spend budget, so a whole venue behind one NAT can log in at kickoff.
    loginLimiter.check('e:$email');
    ipLimiter.check(ip);
    final u = store.one('SELECT * FROM users WHERE email = ?', [email]);
    if (u == null || hashSecret(u['reg_salt'] as String, regNo) != u['reg_hash']) {
      try {
        loginLimiter.hit('e:$email');
        ipLimiter.hit(ip);
      } on ApiError {/* recorded; the next attempt gets the 429 */}
      throw ApiError(401, 'Email or registration number is incorrect.');
    }
    if (u['is_active'] != 1) throw ApiError(403, 'This GDGdex has been disabled. Talk to an organizer.');
    final token = randomToken();
    db.execute('INSERT INTO sessions (token_hash, user_id) VALUES (?, ?)', [sha256Hex(token), u['id']]);
    return _json(_me(u), headers: {'set-cookie': _setCookie(token, maxAge: 60 * 60 * 24 * 7)});
  }

  String _setCookie(String v, {required int maxAge}) =>
      '$_cookie=$v; Path=/; HttpOnly; SameSite=Lax; Max-Age=$maxAge${secureCookies ? '; Secure' : ''}';

  String? _token(Request req) {
    for (final part in (req.headers['cookie'] ?? '').split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2 && kv[0] == _cookie && kv[1].isNotEmpty) return kv[1];
    }
    return null;
  }

  Row _auth(Request req) {
    final t = _token(req);
    final u = t == null
        ? null
        : store.one('SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?', [
            sha256Hex(t),
          ]);
    if (u == null) throw ApiError(401, 'Please log in.', 'UNAUTHENTICATED');
    if (u['is_active'] != 1) throw ApiError(403, 'This GDGdex has been disabled.', 'DISABLED');
    return u;
  }

  Row _admin(Request req) {
    final u = _auth(req);
    if (u['is_admin'] != 1) throw ApiError(403, 'Organizers only.', 'FORBIDDEN');
    return u;
  }

  Map<String, Object?> _me(Row u) => {
    ...Db.publicUser(u),
    'email': u['email'],
    'passkey': u['passkey'],
    'qr': 'GDGDEX:${u['passkey']}',
    'isAdmin': u['is_admin'] == 1,
    'count': store.countFor(u['id'] as int),
    'total': store.collectibleTotal(),
    'event': store.event(),
  };

  // ---------------- collecting ----------------

  /// Accepts a raw passkey or the QR payload `GDGDEX:<passkey>`. Never accepts the public GDG-### id,
  /// otherwise anyone could enumerate 001..N without meeting people.
  Row _target(Row me, Object? code) {
    if (code is! String) throw ApiError(400, 'Enter a passkey.');
    final pk = code.trim().toUpperCase().replaceFirst(RegExp(r'^GDGDEX:'), '');
    final t = RegExp(r'^[A-Z0-9]{4,12}$').hasMatch(pk)
        ? store.one('SELECT * FROM users WHERE passkey = ? AND is_active = 1', [pk])
        : null;
    if (t == null) throw ApiError(404, "That GDGdex entry doesn't exist.", 'NOT_FOUND');
    if (t['id'] == me['id']) throw ApiError(400, "You can't catch yourself. Nice try. 💀", 'SELF');
    return t;
  }

  Map<String, Object?> _collect(Row me, Object? code) {
    final target = _target(me, code);
    // Synchronous block: no awaits, so nothing interleaves inside this isolate; the
    // UNIQUE + CHECK constraints are the real guarantee against duplicates.
    db.execute('BEGIN IMMEDIATE');
    try {
      final status = store.event()['status'];
      if (status != 'ACTIVE') {
        throw ApiError(
          403,
          status == 'ENDED' ? 'The event has ended — final rankings are in!' : "Collecting hasn't started yet.",
          'EVENT_$status',
        );
      }
      db.execute('INSERT INTO collections (collector_id, collected_id) VALUES (?, ?) ON CONFLICT DO NOTHING', [
        me['id'],
        target['id'],
      ]);
      final isNew = db.updatedRows == 1;
      db.execute('COMMIT');
      return {
        'result': isNew ? 'NEW' : 'ALREADY',
        'message': isNew ? 'New GDGdex entry!' : 'Already in your GDGdex!',
        'member': Db.publicUser(target),
        'count': store.countFor(me['id'] as int),
      };
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ---------------- admin ----------------

  Future<Response> _adminRoute(Request req, String m, List<String> seg) async {
    switch ((m, seg)) {
      case ('GET', ['stats']):
        return _json({'event': store.event(), 'stats': store.stats()});
      case ('POST', ['event']):
        final status = (await _body(req))['status'];
        if (status is! String || !const ['NOT_STARTED', 'ACTIVE', 'ENDED'].contains(status)) {
          throw ApiError(400, 'Invalid status');
        }
        db.execute(
          '''UPDATE event SET status = ?,
            started_at = CASE WHEN ? = 'ACTIVE' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE started_at END,
            ended_at   = CASE WHEN ? = 'ENDED'  THEN strftime('%Y-%m-%dT%H:%M:%fZ','now')
                              WHEN ? = 'ACTIVE' THEN NULL ELSE ended_at END
            WHERE id = 1''',
          [status, status, status, status],
        );
        _cache.clear();
        return _json({'event': store.event()});
      case ('GET', ['members']):
        final rows = db.select('SELECT * FROM users ORDER BY dex_no');
        return _json({
          'members': [for (final r in rows) store.adminProjection(r)],
        });
      case ('POST', ['members']):
        final b = await _body(req);
        for (final k in ['name', 'email', 'regNo']) {
          if ((b[k] as String? ?? '').trim().isEmpty) throw ApiError(400, '$k is required');
        }
        try {
          return _json({
            'member': store.createUser(
              name: b['name'],
              email: b['email'],
              regNo: b['regNo'],
              role: (b['role'] as String?)?.trim().isNotEmpty == true ? b['role'] : 'Member',
              avatarUrl: b['avatarUrl'],
              isAdmin: b['isAdmin'] == true,
            ),
          });
        } on SqliteException catch (e) {
          if (e.message.contains('users.email')) throw ApiError(409, 'A member with that email already exists.');
          rethrow;
        }
      case ('GET', ['members', final id]):
        final u = _userByDex(id);
        final rows = db.select(
          '''
          SELECT ${Db.publicCols}, c.created_at FROM collections c JOIN users u ON u.id = c.collected_id
          WHERE c.collector_id = ? ORDER BY c.created_at DESC''',
          [u['id']],
        );
        return _json({
          'member': store.adminProjection(u),
          'collection': [
            for (final r in rows) {...Db.publicUser(r), 'collectedAt': r['created_at']},
          ],
        });
      case ('PATCH', ['members', final id]):
        final u = _userByDex(id);
        final b = await _body(req);
        const cols = {'name': 'name', 'email': 'email', 'role': 'role', 'avatarUrl': 'avatar_url'};
        try {
          for (final e in cols.entries) {
            if (b[e.key] is String)
              db.execute('UPDATE users SET ${e.value} = ? WHERE id = ?', [(b[e.key] as String).trim(), u['id']]);
          }
          for (final e in {'isActive': 'is_active', 'isAdmin': 'is_admin'}.entries) {
            if (b[e.key] is bool)
              db.execute('UPDATE users SET ${e.value} = ? WHERE id = ?', [b[e.key] == true ? 1 : 0, u['id']]);
          }
          if (b['regNo'] is String && (b['regNo'] as String).trim().isNotEmpty) {
            db.execute('UPDATE users SET reg_hash = ? WHERE id = ?', [
              hashSecret(u['reg_salt'] as String, b['regNo']),
              u['id'],
            ]);
          }
        } on SqliteException catch (e) {
          if (e.message.contains('users.email')) throw ApiError(409, 'A member with that email already exists.');
          rethrow;
        }
        if (b['isActive'] == false) db.execute('DELETE FROM sessions WHERE user_id = ?', [u['id']]);
        return _json({
          'member': store.adminProjection(store.one('SELECT * FROM users WHERE id = ?', [u['id']])!),
        });
      case ('POST', ['members', final id, 'passkey']):
        final u = _userByDex(id);
        store.regeneratePasskey(u['id'] as int);
        return _json({
          'member': store.adminProjection(store.one('SELECT * FROM users WHERE id = ?', [u['id']])!),
        });
      case ('GET', ['export', 'members.csv']):
        final rows = db.select('SELECT * FROM users ORDER BY dex_no');
        final ranks = {for (final e in store.leaderboard()) e['dexId']: e['rank']};
        return _csv('gdgdex-members.csv', [
          ['dex_id', 'name', 'email', 'role', 'passkey', 'is_admin', 'is_active', 'collected', 'rank'],
          for (final r in rows)
            [
              dexId(r['dex_no'] as int),
              r['name'],
              r['email'],
              r['role'],
              r['passkey'],
              r['is_admin'],
              r['is_active'],
              store.countFor(r['id'] as int),
              ranks[dexId(r['dex_no'] as int)] ?? '',
            ],
        ]);
      case ('GET', ['export', 'collections.csv']):
        final rows = db.select('''
          SELECT a.dex_no an, a.name aname, b.dex_no bn, b.name bname, c.created_at FROM collections c
          JOIN users a ON a.id = c.collector_id JOIN users b ON b.id = c.collected_id ORDER BY c.created_at''');
        return _csv('gdgdex-collections.csv', [
          ['collector_id', 'collector', 'collected_id', 'collected', 'collected_at'],
          for (final r in rows) [dexId(r['an'] as int), r['aname'], dexId(r['bn'] as int), r['bname'], r['created_at']],
        ]);
    }
    throw ApiError(404, 'Not found');
  }

  Row _userByDex(String id) {
    final n = int.tryParse(id.replaceFirst(RegExp(r'^GDG-', caseSensitive: false), ''));
    final u = n == null ? null : store.one('SELECT * FROM users WHERE dex_no = ?', [n]);
    if (u == null) throw ApiError(404, 'No such member');
    return u;
  }

  // ---------------- helpers ----------------

  /// Every phone polls the public board; serve the same snapshot for 2s.
  /// ponytail: per-process cache, fine for one server instance.
  final _cache = <String, (DateTime, Object)>{};
  Object _cached(String key, Object Function() build) {
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(seconds: 2)) return hit.$2;
    final v = build();
    _cache[key] = (DateTime.now(), v);
    return v;
  }

  Future<Map<String, dynamic>> _body(Request req) async {
    final s = await req.readAsString();
    if (s.isEmpty) return {};
    final v = jsonDecode(s);
    if (v is! Map<String, dynamic>) throw const FormatException();
    return v;
  }

  Response _json(Object body, {int status = 200, Map<String, String> headers = const {}}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers},
  );

  Response _csv(String name, List<List<Object?>> rows) {
    String cell(Object? v) {
      final s = '${v ?? ''}';
      // Quote everything; prefix formula-looking cells so spreadsheets don't execute them.
      final safe = RegExp(r'^[=+\-@]').hasMatch(s) ? "'$s" : s;
      return '"${safe.replaceAll('"', '""')}"';
    }

    return Response.ok(
      rows.map((r) => r.map(cell).join(',')).join('\r\n'),
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="$name"',
        'cache-control': 'no-store',
      },
    );
  }
}
