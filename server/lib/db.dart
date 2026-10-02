import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// Unambiguous alphabet (no 0/O/1/I/L) — 31^6 ≈ 887M passkeys.
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
final _rng = Random.secure();

String newPasskey([int len = 6]) => List.generate(len, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();

String randomToken() => base64Url.encode(List.generate(32, (_) => _rng.nextInt(256))).replaceAll('=', '');

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// Registration numbers are guessable by pattern; hashing only protects a DB leak.
/// Rate limiting (see api.dart) is the real defence.
String hashSecret(String salt, String secret) =>
    Hmac(sha256, utf8.encode(salt)).convert(utf8.encode(secret.trim().toUpperCase())).toString();

String dexId(int n) => 'GDG-${n.toString().padLeft(3, '0')}';

const schema = '''
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (
  id          INTEGER PRIMARY KEY,
  dex_no      INTEGER NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  email       TEXT NOT NULL UNIQUE COLLATE NOCASE,
  reg_salt    TEXT NOT NULL,
  reg_hash    TEXT NOT NULL,
  role        TEXT NOT NULL DEFAULT 'Member',
  avatar_url  TEXT,
  passkey     TEXT NOT NULL UNIQUE,
  is_admin    INTEGER NOT NULL DEFAULT 0,
  is_active   INTEGER NOT NULL DEFAULT 1,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE IF NOT EXISTS collections (
  id            INTEGER PRIMARY KEY,
  collector_id  INTEGER NOT NULL REFERENCES users(id),
  collected_id  INTEGER NOT NULL REFERENCES users(id),
  created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (collector_id, collected_id),
  CHECK (collector_id <> collected_id)
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash  TEXT PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE IF NOT EXISTS event (
  id          INTEGER PRIMARY KEY CHECK (id = 1),
  name        TEXT NOT NULL DEFAULT 'GDGdex',
  status      TEXT NOT NULL DEFAULT 'NOT_STARTED' CHECK (status IN ('NOT_STARTED','ACTIVE','ENDED')),
  started_at  TEXT,
  ended_at    TEXT
);
INSERT OR IGNORE INTO event (id) VALUES (1);
''';

class Db {
  final Database db;
  Db(this.db) {
    db.execute(schema);
  }
  factory Db.open(String path) => Db(sqlite3.open(path));
  factory Db.memory() => Db(sqlite3.openInMemory());

  Row? one(String sql, [List<Object?> args = const []]) {
    final r = db.select(sql, args);
    return r.isEmpty ? null : r.first;
  }

  /// Creates a member. Throws [SqliteException] on duplicate email.
  Map<String, Object?> createUser({
    required String name,
    required String email,
    required String regNo,
    String role = 'Member',
    String? avatarUrl,
    bool isAdmin = false,
    bool isActive = true,
    int? dexNo,
    String? passkey,
  }) {
    final salt = randomToken();
    final next = dexNo ?? (one('SELECT COALESCE(MAX(dex_no), 0) + 1 n FROM users')!['n'] as int);
    // Retry on the (astronomically unlikely) passkey collision.
    for (var i = 0; ; i++) {
      try {
        db.execute(
          'INSERT INTO users (dex_no, name, email, reg_salt, reg_hash, role, avatar_url, passkey, is_admin, is_active) '
          'VALUES (?,?,?,?,?,?,?,?,?,?)',
          [
            next,
            name.trim(),
            email.trim().toLowerCase(),
            salt,
            hashSecret(salt, regNo),
            role.trim(),
            avatarUrl,
            i == 0 && passkey != null ? passkey.trim().toUpperCase() : newPasskey(),
            isAdmin ? 1 : 0,
            isActive ? 1 : 0,
          ],
        );
        return adminUser(dexId(next))!;
      } on SqliteException catch (e) {
        // A supplied passkey that collides gets replaced by a generated one.
        if (i < 5 && e.message.contains('users.passkey')) continue;
        rethrow;
      }
    }
  }

  String regeneratePasskey(int userId) {
    for (var i = 0; ; i++) {
      final pk = newPasskey();
      try {
        db.execute('UPDATE users SET passkey = ? WHERE id = ?', [pk, userId]);
        return pk;
      } on SqliteException {
        if (i >= 5) rethrow;
      }
    }
  }

  // ---- public projections (never include passkey / internal id) ----

  static const publicCols = 'u.dex_no, u.name, u.role, u.avatar_url';

  static Map<String, Object?> publicUser(Row r) => {
    'dexId': dexId(r['dex_no'] as int),
    'name': r['name'],
    'role': r['role'],
    'avatarUrl': r['avatar_url'],
  };

  static const activeCollections = '''
    SELECT c.* FROM collections c
    JOIN users a ON a.id = c.collector_id AND a.is_active = 1
    JOIN users b ON b.id = c.collected_id AND b.is_active = 1''';

  int collectibleTotal() => (one('SELECT COUNT(*) n FROM users WHERE is_active = 1')!['n'] as int) - 1;

  int countFor(int userId) =>
      one('SELECT COUNT(*) n FROM ($activeCollections) c WHERE c.collector_id = ?', [userId])!['n'] as int;

  /// Ranked by unique count desc; ties broken by who reached that count first.
  List<Map<String, Object?>> leaderboard({int? limit}) {
    final rows = db.select('''
      SELECT $publicCols, COUNT(c.id) n, MAX(c.created_at) last_at
      FROM users u LEFT JOIN ($activeCollections) c ON c.collector_id = u.id
      WHERE u.is_active = 1
      GROUP BY u.id
      ORDER BY n DESC, (last_at IS NULL), last_at ASC, u.dex_no ASC
      ${limit != null ? 'LIMIT $limit' : ''}''');
    var rank = 0;
    return [
      for (final r in rows) {...publicUser(r), 'count': r['n'], 'rank': ++rank, 'lastAt': r['last_at']},
    ];
  }

  /// Latest discoveries for the projector feed (names only, no secrets).
  List<Map<String, Object?>> recent({int limit = 8}) => [
    for (final r in db.select(
      '''
          SELECT a.name collector, b.name collected, b.dex_no, c.created_at FROM ($activeCollections) c
          JOIN users a ON a.id = c.collector_id JOIN users b ON b.id = c.collected_id
          ORDER BY c.created_at DESC, c.id DESC LIMIT ?''',
      [limit],
    ))
      {
        'collector': r['collector'],
        'collected': r['collected'],
        'dexId': dexId(r['dex_no'] as int),
        'at': r['created_at'],
      },
  ];

  /// Consistent snapshot of the live DB (safe while serving traffic).
  void backupTo(String path) => db.execute('VACUUM INTO ?', [path]);

  Map<String, Object?> event() {
    final e = one('SELECT * FROM event WHERE id = 1')!;
    return {'name': e['name'], 'status': e['status'], 'startedAt': e['started_at'], 'endedAt': e['ended_at']};
  }

  Map<String, Object?> stats() {
    final most = one('''
      SELECT $publicCols, COUNT(*) n FROM ($activeCollections) c JOIN users u ON u.id = c.collected_id
      GROUP BY u.id ORDER BY n DESC, u.dex_no LIMIT 1''');
    final top = leaderboard(limit: 1);
    return {
      'members': one('SELECT COUNT(*) n FROM users WHERE is_active = 1')!['n'],
      'collections': one('SELECT COUNT(*) n FROM ($activeCollections)')!['n'],
      'uniqueDiscovered': one('SELECT COUNT(DISTINCT collected_id) n FROM ($activeCollections)')!['n'],
      'mostCollected': most == null ? null : {...publicUser(most), 'count': most['n']},
      'topCollector': top.isEmpty || top.first['count'] == 0 ? null : top.first,
    };
  }

  Map<String, Object?>? adminUser(String dexIdStr) {
    final n = int.tryParse(dexIdStr.replaceFirst(RegExp(r'^GDG-', caseSensitive: false), ''));
    if (n == null) return null;
    final r = one('SELECT * FROM users WHERE dex_no = ?', [n]);
    return r == null ? null : adminProjection(r);
  }

  Map<String, Object?> adminProjection(Row r) => {
    ...publicUser(r),
    'email': r['email'],
    'passkey': r['passkey'],
    'isAdmin': r['is_admin'] == 1,
    'isActive': r['is_active'] == 1,
    'createdAt': r['created_at'],
    'count': countFor(r['id'] as int),
  };
}
