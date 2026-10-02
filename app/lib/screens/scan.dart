import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';
import '../ui.dart';

const _qrPrefix = 'GDGDEX:';

/// Full collect loop: get a code (camera or typed) → confirm (QR only) → collect → celebrate.
/// "Scan next" on the success screen loops straight back to the camera.
Future<void> startCollect(BuildContext context, {required bool camera}) async {
  while (true) {
    if (!context.mounted) return;
    final code = camera ? await _scan(context) : await _askPasskey(context);
    if (code == null || !context.mounted) return;

    if (camera) {
      final ok = await _confirm(context, code);
      if (ok != true || !context.mounted) {
        if (ok == false) continue; // "Scan again"
        return;
      }
    }

    try {
      final r = await Api.post('collect', {'code': code});
      Api.refreshMe().catchError((_) => null);
      if (!context.mounted) return;
      final again = await _celebrate(context, r);
      if (again != true) return;
      camera = true;
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final retry = await _error(context, e);
      if (retry != true) return;
    }
  }
}

// ---------------------------------------------------------------- input

Future<String?> _scan(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ScannerPage()));

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _hint;

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue?.trim() ?? '';
      if (v.toUpperCase().startsWith(_qrPrefix)) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.pop(context, v);
        return;
      }
    }
    setState(() => _hint = "That's not a GDGdex QR.");
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('SCAN GDGDEX', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        actions: [IconButton(onPressed: _controller.toggleTorch, icon: const Icon(Icons.flashlight_on_outlined))],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access was blocked.\nAllow camera access in your browser settings, or enter the passkey instead.'
                      : 'Camera unavailable (${error.errorCode.name}).\nEnter the passkey instead.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // Viewfinder (hidden when the camera failed, so the error text stays readable)
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, state, _) => state.error != null
                ? const SizedBox.shrink()
                : Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint ?? 'Point at a GDGdex QR code',
                    style: TextStyle(color: _hint == null ? Colors.white : gYellow, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: () async {
                      final code = await _askPasskey(context);
                      if (code != null && context.mounted) Navigator.pop(context, code);
                    },
                    icon: const Icon(Icons.keyboard_alt_outlined),
                    label: const Text('ENTER PASSKEY INSTEAD'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askPasskey(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = c.text.trim().toUpperCase();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: const Text('ENTER PASSKEY', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        content: TextField(
          controller: c,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 12,
          style: mono.copyWith(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 6),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
          ],
          decoration: const InputDecoration(hintText: 'X7K9P2', counterText: ''),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('COLLECT')),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------- confirm

/// true = add, false = scan again, null = close.
Future<bool?> _confirm(BuildContext context, String code) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) => FutureBuilder(
    future: Api.post('lookup', {'code': code}),
    builder: (ctx, snap) {
      if (snap.hasError) {
        final e = snap.error;
        return _SheetBody(
          children: [
            const Icon(Icons.error_outline, size: 48, color: gRed),
            const SizedBox(height: 8),
            Text('$e', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('SCAN AGAIN')),
          ],
        );
      }
      if (!snap.hasData) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
      final m = snap.data!['member'] as Json;
      final already = snap.data!['alreadyCollected'] == true;
      return _SheetBody(
        children: [
          Avatar(m, size: 84),
          const SizedBox(height: 10),
          Text(m['name'], style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          Text('${m['role']}  ·  ${m['dexId']}', style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
          const SizedBox(height: 20),
          if (already) ...[
            const Text(
              'Already in your GDGdex!',
              style: TextStyle(fontWeight: FontWeight.w700, color: gYellow),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('SCAN SOMEONE ELSE')),
          ] else
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('ADD TO GDGDEX'),
              style: FilledButton.styleFrom(backgroundColor: gGreen),
            ),
        ],
      );
    },
  ),
);

class _SheetBody extends StatelessWidget {
  final List<Widget> children;
  const _SheetBody({required this.children});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final c in children) c is ButtonStyleButton ? SizedBox(width: double.infinity, child: c) : c],
      ),
    ),
  );
}

// ---------------------------------------------------------------- results

Future<bool?> _error(BuildContext context, ApiException e) => showDialog<bool>(
  context: context,
  builder: (ctx) => AlertDialog(
    icon: Icon(
      e.code == 'SELF' ? Icons.sentiment_very_satisfied : Icons.error_outline,
      size: 40,
      color: e.code == 'SELF' ? gYellow : gRed,
    ),
    title: Text(e.message, textAlign: TextAlign.center),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      if (!(e.code ?? '').startsWith('EVENT_'))
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(e.code == 'NETWORK' ? 'RETRY' : 'TRY AGAIN'),
        ),
    ],
  ),
);

/// Returns true for "scan next".
Future<bool?> _celebrate(BuildContext context, Json r) {
  final m = r['member'] as Json;
  final isNew = r['result'] == 'NEW';
  if (isNew) HapticFeedback.heavyImpact();
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Narrow(
          maxWidth: 380,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isNew ? '🎉 NEW GDGDEX ENTRY!' : 'ALREADY IN YOUR GDGDEX!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 18,
                        color: isNew ? gGreen : gYellow,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isNew ? 'You discovered' : 'You already have',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.outline),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isNew) const Positioned.fill(child: _Burst()),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: .3, end: 1),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.elasticOut,
                            builder: (_, s, child) => Transform.scale(scale: s, child: child),
                            child: Avatar(m, size: 104),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      m['name'],
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(m['role'] ?? '', style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
                    const SizedBox(height: 6),
                    Text(
                      'GDGdex #${(m['dexId'] as String).replaceFirst('GDG-', '')}',
                      style: mono.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Collected: ${r['count']}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: gBlue, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('SCAN NEXT'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: .9, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

/// Radial burst of GDG-coloured dots.
class _Burst extends StatelessWidget {
  const _Burst();
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (_, t, _) => CustomPaint(painter: _BurstPainter(t)),
  );
}

class _BurstPainter extends CustomPainter {
  final double t;
  _BurstPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 16; i++) {
      final a = i * pi / 8;
      final r = 40 + 45 * t;
      canvas.drawCircle(
        c + Offset(cos(a), sin(a)) * r,
        6 * (1 - t) + 1,
        Paint()..color = gdgColors[i % 4].withValues(alpha: 1 - t * .8),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Read-only view of a collected entry (never shows a passkey).
void showEntry(BuildContext context, Json m) => showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(m, size: 96),
        const SizedBox(height: 12),
        Text(
          m['name'],
          textAlign: TextAlign.center,
          style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(m['role'] ?? '', style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
        const SizedBox(height: 8),
        Text(m['dexId'], style: mono.copyWith(fontWeight: FontWeight.w800, fontSize: 18)),
        if (m['collectedAt'] != null) ...[
          const SizedBox(height: 8),
          Text('Discovered ${_time(m['collectedAt'])}', style: Theme.of(ctx).textTheme.bodySmall),
        ],
      ],
    ),
  ),
);

String _time(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '' : 'at ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
