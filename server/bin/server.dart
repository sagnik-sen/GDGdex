import 'dart:io';

import 'package:gdgdex_server/api.dart';
import 'package:gdgdex_server/db.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

/// Env: PORT (8080), DB_PATH (gdgdex.db), WEB_DIR (../app/build/web), SECURE_COOKIES (1 behind HTTPS).
Future<void> main() async {
  final env = Platform.environment;
  final api = Api(Db.open(env['DB_PATH'] ?? 'gdgdex.db'), secureCookies: env['SECURE_COOKIES'] == '1');
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
