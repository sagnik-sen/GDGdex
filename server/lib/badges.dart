import 'package:qr/qr.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';

/// Printable lanyard cards (QR + passkey) for every active member, for people without a phone.
/// Rendered server-side as plain HTML so the browser's print dialog handles paging.
String badgesHtml(ResultSet users) {
  String esc(Object? v) =>
      '${v ?? ''}'.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  final cards = StringBuffer();
  for (final u in users) {
    cards.write('''
<div class="card">
  <div class="top"><span class="lens"></span><b>GDGDEX</b><span>${dexId(u['dex_no'] as int)}</span></div>
  <div class="name">${esc(u['name'])}</div>
  <div class="role">${esc(u['role'])}</div>
  ${_qrSvg('GDGDEX:${u['passkey']}')}
  <div class="pk">${esc(u['passkey'])}</div>
</div>''');
  }
  return '''<!doctype html><html><head><meta charset="utf-8"><title>GDGdex badges</title><style>
@page { size: A4; margin: 10mm; }
* { box-sizing: border-box; }
body { margin: 0; font-family: Roboto, Arial, sans-serif; color: #111; }
.hint { padding: 12px; font-size: 14px; } @media print { .hint { display: none; } }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6mm; }
.card { border: 1px solid #ccc; border-radius: 4mm; overflow: hidden; text-align: center; padding-bottom: 3mm; break-inside: avoid; }
.top { background: #EA4335; color: #fff; display: flex; justify-content: space-between; align-items: center; padding: 2mm 3mm; font-size: 10pt; letter-spacing: 1px; }
.lens { width: 4mm; height: 4mm; border-radius: 50%; background: #8FD3FF; border: 0.6mm solid #fff; }
.name { font-weight: 800; font-size: 12pt; margin-top: 2mm; padding: 0 2mm; }
.role { color: #666; font-size: 8pt; margin-bottom: 1mm; }
svg { width: 34mm; height: 34mm; }
.pk { font: 800 14pt monospace; letter-spacing: 2mm; }
</style></head><body>
<div class="hint">${users.length} badges. Print with Ctrl/Cmd+P (A4, background graphics on). Cut along the borders.</div>
<div class="grid">$cards</div></body></html>''';
}

String _qrSvg(String data) {
  final img = QrImage(QrCode(payload: QrPayload.fromString(data)));
  final n = img.moduleCount, q = 2; // quiet zone
  final path = StringBuffer();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (img.isDark(y, x)) path.write('M${x + q} ${y + q}h1v1h-1z');
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${n + 2 * q} ${n + 2 * q}" shape-rendering="crispEdges">'
      '<rect width="100%" height="100%" fill="#fff"/><path d="$path" fill="#000"/></svg>';
}
