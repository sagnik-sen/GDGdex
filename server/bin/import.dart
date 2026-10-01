import 'dart:io';

import 'package:gdgdex_server/db.dart';
import 'package:sqlite3/sqlite3.dart';

/// Usage: dart run bin/import.dart participants.csv [DB_PATH]
/// CSV header: name,email,reg_no,role[,is_admin,is_active,gdgdex_id,passkey,avatar_url]  (booleans: 1/yes/true)
/// gdgdex_id / passkey are kept when given, otherwise generated. Existing emails are skipped,
/// so re-running is safe.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run bin/import.dart participants.csv [db_path]');
    exit(64);
  }
  final store = Db.open(args.length > 1 ? args[1] : (Platform.environment['DB_PATH'] ?? 'gdgdex.db'));
  final lines = File(args[0]).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  final header = _split(lines.first.replaceFirst('\uFEFF', '')).map((h) => h.trim().toLowerCase()).toList();
  int col(String n) => header.indexOf(n);
  var added = 0, skipped = 0;
  for (final line in lines.skip(1)) {
    final c = _split(line);
    String get(String n) => col(n) >= 0 && col(n) < c.length ? c[col(n)].trim() : '';
    if (get('email').isEmpty || get('reg_no').isEmpty || get('name').isEmpty) {
      stderr.writeln('skip (missing name/email/reg_no): $line');
      skipped++;
      continue;
    }
    try {
      final u = store.createUser(
        name: get('name'),
        email: get('email'),
        regNo: get('reg_no'),
        role: get('role').isEmpty ? 'Member' : get('role'),
        avatarUrl: get('avatar_url').isEmpty ? null : get('avatar_url'),
        isAdmin: _truthy(get('is_admin')),
        isActive: get('is_active').isEmpty || _truthy(get('is_active')),
        dexNo: int.tryParse(get('gdgdex_id').replaceFirst(RegExp(r'^GDG-', caseSensitive: false), '')),
        passkey: get('passkey').isEmpty ? null : get('passkey'),
      );
      print('${u['dexId']}  ${u['passkey']}  ${u['name']}');
      added++;
    } on SqliteException catch (e) {
      if (!e.message.contains('users.email') && !e.message.contains('users.dex_no')) rethrow;
      stderr.writeln('skip (email or gdgdex_id already exists): ${get('email')}');
      skipped++;
    }
  }
  print('added $added, skipped $skipped');
}

bool _truthy(String v) => const ['1', 'yes', 'true', 'y'].contains(v.toLowerCase());

/// Minimal CSV field splitter with double-quote support.
List<String> _split(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var q = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (q) {
      if (ch == '"' && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else if (ch == '"') {
        q = false;
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      q = true;
    } else if (ch == ',') {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}
