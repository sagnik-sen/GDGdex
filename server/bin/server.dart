import 'dart:async';
import 'dart:io';

import 'package:gdgdex_server/api.dart';
import 'package:gdgdex_server/db.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

/// Env: PORT (8080), DB_PATH (gdgdex.db), WEB_DIR (../app/build/web), SECURE_COOKIES (1 behind HTTPS),
/// BACKUP_DIR (<db dir>/backups).
Future<void> main() async {
  final env = Platform.environment;
  final dbPath = env['DB_PATH'] ?? 'gdgdex.db';
  final store = Db.open(dbPath);
  final api = Api(store, secureCookies: env['SECURE_COOKIES'] == '1');

  // Snapshot every 5 minutes into BACKUP_DIR (default: <db dir>/backups), keeping the newest 24 (~2h).
  final backups = Directory(env['BACKUP_DIR'] ?? '${File(dbPath).absolute.parent.path}/backups')
    ..createSync(recursive: true);
  Timer.periodic(const Duration(minutes: 5), (_) {
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
      store.backupTo('${backups.path}/gdgdex-$stamp.db');
      final old = backups.listSync().whereType<File>().toList()..sort((a, b) => b.path.compareTo(a.path));
      for (final f in old.skip(24)) {
        f.deleteSync();
      }
    } catch (e) {
      stderr.writeln('backup failed: $e');
    }
  });
  final webDir = env['WEB_DIR'] ?? '../app/build/web';
  final static = Directory(webDir).existsSync()
      ? createStaticHandler(webDir, defaultDocument: 'index.html')
      : (Request _) => Response.notFound('Web build not found at $webDir. Run `flutter build web` in app/.');

  // index.html + Flutter bootstrap must never be cached, so a redeploy reaches every phone immediately.
  const noCache = {
    'index.html',
    'flutter_bootstrap.js',
    'flutter_service_worker.js',
    'main.dart.js',
    'version.json',
    '',
  };
  Handler web = (req) async {
    final res = await static(req);
    return noCache.contains(req.url.path) ? res.change(headers: {'cache-control': 'no-cache'}) : res;
  };

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler((req) => req.url.path.startsWith('api/') ? api.call(req) : web(req));

  final server = await io.serve(handler, InternetAddress.anyIPv4, int.parse(env['PORT'] ?? '8080'));
  server.autoCompress = true;
  print('GDGdex on http://${server.address.host}:${server.port}');
}
