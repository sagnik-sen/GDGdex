import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  Json? _state;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final s = await Api.get('state');
      if (mounted) setState(() => _state = s);
    } catch (_) {
      /* landing still works without stats */
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final stats = _state?['stats'] as Json?;
    final top = ((_state?['top'] as List?) ?? []).cast<Json>().where((e) => e['count'] > 0).toList();
    return Scaffold(
      body: SafeArea(
        child: Narrow(
          maxWidth: 520,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const GdgDots(size: 16),
              const SizedBox(height: 16),
              Text('GDGdex', style: t.displayLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -2)),
              Text('Gotta GDG ’em all.', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: [
                  for (final (i, w) in ['Meet.', 'Scan.', 'Collect.'].indexed)
                    Text(
                      w,
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: gdgColors[i]),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Discover members of the GDG community by scanning their GDGdex QR or entering their passkey. '
                'Most unique entries when the event ends wins.',
                style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/dex'),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('ENTER GDGDEX'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), backgroundColor: gBlue),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/leaderboard'),
                icon: const Icon(Icons.leaderboard_outlined),
                label: const Text('VIEW LEADERBOARD'),
              ),
              if (_state != null) ...[
                const SizedBox(height: 32),
                Row(
                  children: [
                    _Stat('${stats!['members']}', 'Participants'),
                    const SizedBox(width: 10),
                    _Stat('${stats['collections']}', 'Entries found'),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Card(
                        child: SizedBox(
                          height: 86,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: FittedBox(fit: BoxFit.scaleDown, child: StatusPill(_state!['event']['status'])),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (top.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('TOP COLLECTORS', style: t.labelLarge?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final e in top)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(e, size: 40),
                      title: Text(e['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(e['role'] ?? ''),
                      trailing: Text('${e['count']}', style: mono.copyWith(fontSize: 20, fontWeight: FontWeight.w900)),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: SizedBox(
        height: 86,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: mono.copyWith(fontSize: 26, fontWeight: FontWeight.w900, color: gBlue),
            ),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    ),
  );
}
